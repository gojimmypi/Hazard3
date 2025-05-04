#include "tb_cxxrtl_io.h"
#include "hazard3_csr.h"
#include "pmp.h"

// Check that PMP correctly controls U-mode R/W permissions, for all three
// access sizes.

#define MCAUSE_LOAD_FAULT 5
#define MCAUSE_STORE_FAULT 7
#define MCAUSE_ECALL_UMODE 8

/*EXPECTED-OUTPUT***************************************************************
Read with TOR
Read address 00000000
 -> 8
Read address 00000004
 -> 8
Read address 00000008
 -> 8
Read address 0000000c
 -> 5
*******************************************************************************/

typedef uint32_t uxlen_t;
typedef uxlen_t (*umode_func_2a_1r)(uxlen_t, uxlen_t);

// /!\ Unconventional control flow ahead

// Call a function in U-mode, from M-mode, with two register arguments and one
// register result. If the function traps, mcause/mepc indicate the trap
// cause. Otherwise mcause is set to U-mode ecall (= 8).	

uxlen_t __attribute__((naked)) call_umode(umode_func_2a_1r f, uxlen_t a0, uxlen_t a1) {
	asm (
		"addi sp, sp, -16                                                     \n"
		"sw s0, 0(sp)                                                         \n"
		"sw ra, 4(sp)                                                         \n"
		// Set up mret target address and mode
		"csrw mepc, a0                                                        \n"
		"li a0, 0x1800                                                        \n"
		"csrc mstatus, a0                                                     \n"
		// Set up arguments
		"mv a0, a1                                                            \n"
		"mv a1, a2                                                            \n"
		// Set up two return paths: trap -> mtvec, or ret -> ecall -> mtvec
		"la s0, 1f                                                            \n"
		"addi ra, s0, -4                                                      \n"
		"csrrw s0, mtvec, s0                                                  \n"
		// Call the function
		"mret                                                                 \n"
		// Join return paths and restore mtvec
		".p2align 2                                                           \n"
		"ecall                                                                \n"
		"1:                                                                   \n"
		"csrw mtvec, s0                                                       \n"
		// Then return via saved ra
		"lw s0, 0(sp)                                                         \n"
		"lw ra, 4(sp)                                                         \n"
		"addi sp, sp, 16                                                      \n"
		"ret                                                                  \n"
	);
}

void __attribute__((naked)) do_sw(uxlen_t a, uxlen_t d) {
	asm volatile (
		"sw a1, (a0)\n"
		"ecall\n"
	);
}

void __attribute__((naked)) do_sh(uxlen_t a, uxlen_t d) {
	asm volatile (
		"sh a1, (a0)\n"
		"ecall\n"
	);
}

void __attribute__((naked)) do_sb(uxlen_t a, uxlen_t d) {
	asm volatile (
		"sb a1, (a0)\n"
		"ecall\n"
	);
}

uxlen_t __attribute__((naked)) do_lw(uxlen_t a) {
	asm volatile (
		"lw a0, (a0)\n"
		"ecall"
	);
}

uxlen_t __attribute__((naked)) do_lhu(uxlen_t a) {
	asm volatile (
		"lhu a0, (a0)\n"
		"ecall"
	);
}

uxlen_t __attribute__((naked)) do_lbu(uxlen_t a) {
	asm volatile (
		"lbu a0, (a0)\n"
		"ecall"
	);
}

volatile uint32_t scratch_word;

int main() {
	tb_puts("Read with TOR\n");

	write_pmpcfg(0, 0);
	write_pmpcfg(1, 0);
	write_pmpcfg(2, 0);
	write_pmpcfg(3, 0);

	// Test the implicit 0 lower bound for region 0: grant read on the first 12 bytes
	write_pmpcfg(0, PMPCFG_A_TOR << PMPCFG_A_LSB | PMPCFG_R_BITS);
	write_pmpaddr(0, 0xc >> 2);

	// Grant execute on just the function of interest
	write_pmpaddr(2, (uintptr_t)do_lw >> 2);
	write_pmpaddr(3, ((uintptr_t)do_lw + 12u) >> 2);
	write_pmpcfg(3, PMPCFG_A_TOR << PMPCFG_A_LSB | PMPCFG_X_BITS);

	// First 3 succeed, last one faults
	for (int i = 0; i < 4; ++i) {
		uintptr_t addr = i << 2;
		tb_printf("Read address %08x\n", addr);
		write_csr(mcause, 0);
		(void)call_umode((umode_func_2a_1r)&do_lw, addr, 0);
		tb_printf(" -> %u\n", read_csr(mcause));
	}

	return 0;
}
