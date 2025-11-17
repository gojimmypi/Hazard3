#include "tb_cxxrtl_io.h"
#include "hazard3_csr.h"

// Test that a fault occurring at each address loaded by a maximal Zcmp
// cm.popretz results in the expected mcause, mepc and GPR values.

volatile uint32_t __attribute__((aligned(16))) stackframe[16];
volatile uint32_t check_ra_s_regs[13];
volatile uint32_t sp_save;
volatile int expected_fault_idx;
volatile bool exception_taken;

extern uint16_t popret_instr;
void test_popret(int poison_idx) {
	// Clear poison so we can initialise the stack frame.
	tb_set_poison_addr(-1u);

	tb_printf("Setup, poison_idx=%d\n", poison_idx);

	// Alignment padding at bottom of frame
	for (int i = 0; i < 3; ++i) {
		stackframe[i] = 0;
	}
	// Return address is two instructions after the popret (the instruction
	// immediately after is an ebreak to check it doesn't fall through)
	stackframe[3] = (uintptr_t)&popret_instr + 4;
	// Eyecatchers for the s0 -> s11 registers.
	for (int i = 4; i < 16; ++i) {
		stackframe[i] = 0x50500000 + (i - 4);
	}

	if (poison_idx >= 0) {
		tb_set_poison_addr((uintptr_t)&stackframe[3 + poison_idx]);
	}

	expected_fault_idx = poison_idx;
	exception_taken = false;
	asm volatile (
		"la a0, sp_save\n"
		"sw sp, (a0)\n"
		"la sp, stackframe\n"
		// Clear regs loaded by popretz, so that if they have the correct value
		// afterward it isn't by chance.
		"li a0, -1\n"
		"li ra, -1\n"
		"li s0, -1\n"
		"li s1, -1\n"
		"li s2, -1\n"
		"li s3, -1\n"
		"li s4, -1\n"
		"li s5, -1\n"
		"li s6, -1\n"
		"li s7, -1\n"
		"li s8, -1\n"
		"li s9, -1\n"
		"li s10, -1\n"
		"li s11, -1\n"
		".global popret_instr\n"
	"popret_instr:\n"
		".insn 2, 0xbcf2\n" // cm.popretz {ra, s0-s11}, +64
		"c.ebreak\n"
		"lw sp, sp_save\n"
		:
		:
		:
		// Trashed by cm.popretz and our setup
		"ra", "s0", "s1", "s2", "s3", "s4", "s5", "s6",
		"s7", "s8", "s9", "s10", "s11",
		// Trashed by call to C function in exception handler
		"a0", "a1", "a2", "a3", "a4", "a5", "a6", "a7",
		"t0", "t1", "t2", "t3", "t4", "t5", "t6",
		// Trashed all over
		"memory"
	);
}

void __attribute__((naked)) handle_exception(void) {
	// Record register values, restore stack and tail into C function with the
	// actual checks.
	asm volatile (
		// don't touch a0; it's passed in-place
		"mv a1, sp\n"
		"lw sp, sp_save\n"
		"la a2, check_ra_s_regs\n"
		"sw ra,  0(a2)\n"
		"sw s0,  4(a2)\n"
		"sw s1,  8(a2)\n"
		"sw s2,  12(a2)\n"
		"sw s3,  16(a2)\n"
		"sw s4,  20(a2)\n"
		"sw s5,  24(a2)\n"
		"sw s6,  28(a2)\n"
		"sw s7,  32(a2)\n"
		"sw s8,  36(a2)\n"
		"sw s9,  40(a2)\n"
		"sw s10, 44(a2)\n"
		"sw s11, 48(a2)\n"
		"la ra, popret_instr + 4\n"
		"j handle_exception_impl\n"
	);
}

void handle_exception_impl(uint32_t a0, uint32_t sp) {
	exception_taken = true;
	tb_printf("Entered exception, mcause = %u\n", read_csr(mcause));
	tb_assert(read_csr(mepc) == (uintptr_t)&popret_instr,
			"Bad exception PC: %08x\n", read_csr(mepc));
	bool expect_exception = expected_fault_idx != -1 && expected_fault_idx != -1;
	tb_assert(a0 == (expect_exception ? -1 : 0), "Bad a0: %08x\n", a0);
	tb_assert(sp == (uintptr_t)&stackframe[0] + (expect_exception ? 0 : 64),
		"Bad sp value: %08x\n", sp);
	write_csr(mcause, 0);
	write_csr(mepc, 0);
	if (expected_fault_idx != 0) {
		tb_assert(check_ra_s_regs[0] == (uintptr_t)&popret_instr + 4,
			"Bad loaded ra value\n");
	}
	// s regs can be put in expected output because the value doesn't depend
	// on binary layout.
	for (int i = 0; i < 12; ++i) {
		tb_put_u32(check_ra_s_regs[i + 1]);
	}
}

int main() {
	for (int i = -1; i <= 13; ++i) {
		test_popret(i);
		tb_printf("Returned\n");
		bool expect_exception = i != -1 && i != 13;
		tb_assert(exception_taken == expect_exception,
			"expected exception_taken == %d\n", expect_exception);
	}
}

/*EXPECTED-OUTPUT**************************************************************

Setup, poison_idx=-1
Returned
Setup, poison_idx=0
Entered exception, mcause = 5
ffffffff
ffffffff
ffffffff
ffffffff
ffffffff
ffffffff
ffffffff
ffffffff
ffffffff
ffffffff
ffffffff
ffffffff
Returned
Setup, poison_idx=1
Entered exception, mcause = 5
ffffffff
ffffffff
ffffffff
ffffffff
ffffffff
ffffffff
ffffffff
ffffffff
ffffffff
ffffffff
ffffffff
ffffffff
Returned
Setup, poison_idx=2
Entered exception, mcause = 5
50500000
ffffffff
ffffffff
ffffffff
ffffffff
ffffffff
ffffffff
ffffffff
ffffffff
ffffffff
ffffffff
ffffffff
Returned
Setup, poison_idx=3
Entered exception, mcause = 5
50500000
50500001
ffffffff
ffffffff
ffffffff
ffffffff
ffffffff
ffffffff
ffffffff
ffffffff
ffffffff
ffffffff
Returned
Setup, poison_idx=4
Entered exception, mcause = 5
50500000
50500001
50500002
ffffffff
ffffffff
ffffffff
ffffffff
ffffffff
ffffffff
ffffffff
ffffffff
ffffffff
Returned
Setup, poison_idx=5
Entered exception, mcause = 5
50500000
50500001
50500002
50500003
ffffffff
ffffffff
ffffffff
ffffffff
ffffffff
ffffffff
ffffffff
ffffffff
Returned
Setup, poison_idx=6
Entered exception, mcause = 5
50500000
50500001
50500002
50500003
50500004
ffffffff
ffffffff
ffffffff
ffffffff
ffffffff
ffffffff
ffffffff
Returned
Setup, poison_idx=7
Entered exception, mcause = 5
50500000
50500001
50500002
50500003
50500004
50500005
ffffffff
ffffffff
ffffffff
ffffffff
ffffffff
ffffffff
Returned
Setup, poison_idx=8
Entered exception, mcause = 5
50500000
50500001
50500002
50500003
50500004
50500005
50500006
ffffffff
ffffffff
ffffffff
ffffffff
ffffffff
Returned
Setup, poison_idx=9
Entered exception, mcause = 5
50500000
50500001
50500002
50500003
50500004
50500005
50500006
50500007
ffffffff
ffffffff
ffffffff
ffffffff
Returned
Setup, poison_idx=10
Entered exception, mcause = 5
50500000
50500001
50500002
50500003
50500004
50500005
50500006
50500007
50500008
ffffffff
ffffffff
ffffffff
Returned
Setup, poison_idx=11
Entered exception, mcause = 5
50500000
50500001
50500002
50500003
50500004
50500005
50500006
50500007
50500008
50500009
ffffffff
ffffffff
Returned
Setup, poison_idx=12
Entered exception, mcause = 5
50500000
50500001
50500002
50500003
50500004
50500005
50500006
50500007
50500008
50500009
5050000a
ffffffff
Returned
Setup, poison_idx=13
Returned

******************************************************************************/