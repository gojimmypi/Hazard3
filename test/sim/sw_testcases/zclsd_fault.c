#include "tb_cxxrtl_io.h"
#include "hazard3_csr.h"
#include "zilsd_macros.h"
#include <stdint.h>

// Test intent: check bus faults on ld/sd report correct exceptions, and ld
// does not clobber its base register (this is the same as zilsd_fault, but
// using the equivalent zclsd instructions)

void clear_exception_state(void) {
	write_csr(mepc, 0);
	write_csr(mcause, 0);
}

#define LD_CLOBBER_FIRST(addr)  \
	asm volatile (              \
	"mv a0, %0\n"               \
	"zclsd.ld x_a0, x_a0, 0\n"  \
	"mv %0, a0\n"               \
	: "+r" (addr)               \
	:                           \
	: "a0", "a1", "memory"      \
	);

#define LD_CLOBBER_SECOND(addr) \
	asm volatile (              \
	"mv a1, %0\n"               \
	"zclsd.ld x_a0, x_a1, 0\n"  \
	"mv %0, a1\n"               \
	: "+r" (addr)               \
	:                           \
	: "a0", "a1", "memory"      \
	);

#define SD_EVEN_BASE(addr)      \
	asm volatile (              \
	"mv a0, %0\n"               \
	"addi a1, a0, 1\n"          \
	"zclsd.sd x_a0, x_a0, 0\n"  \
	: "+r" (addr)               \
	:                           \
	: "a0", "a1", "memory"      \
	);

#define SD_ODD_BASE(addr)       \
	asm volatile (              \
	"mv a1, %0\n"               \
	"addi a0, a1, 1\n"          \
	"zclsd.sd x_a0, x_a1, 0\n"  \
	: "+r" (addr)               \
	:                           \
	: "a0", "a1", "memory"      \
	);

void __attribute__((interrupt)) handle_exception(void) {
	tb_printf("mcause = %u\n", read_csr(mcause));
	// Assume 16-bit as this is just Zclsd:
	write_csr(mepc, read_csr(mepc) + 2);
}

uint32_t scratch[2];

int main() {
	scratch[0] = 0x12430001;
	scratch[1] = 0x12340002;

	// Load faults

	tb_puts("ld, clobber first, fault first\n");
	uintptr_t addr = (uintptr_t)&scratch[0];
	tb_set_poison_addr((uintptr_t)&scratch[0]);
	clear_exception_state();
	LD_CLOBBER_FIRST(addr);
	tb_assert(addr == (uintptr_t)&scratch[0], "bad address\n");
	tb_assert(read_csr(mcause) == 5, "bad exception cause\n");

	tb_puts("ld, clobber first, fault second\n");
	addr = (uintptr_t)&scratch[0];
	tb_set_poison_addr((uintptr_t)&scratch[1]);
	clear_exception_state();
	LD_CLOBBER_FIRST(addr);
	tb_assert(addr == (uintptr_t)&scratch[0], "bad address\n");
	tb_assert(read_csr(mcause) == 5, "bad exception cause\n");

	tb_puts("ld, clobber second, fault first\n");
	addr = (uintptr_t)&scratch[0];
	tb_set_poison_addr((uintptr_t)&scratch[0]);
	clear_exception_state();
	LD_CLOBBER_SECOND(addr);
	tb_assert(addr == (uintptr_t)&scratch[0], "bad address\n");
	tb_assert(read_csr(mcause) == 5, "bad exception cause\n");

	tb_puts("ld, clobber second, fault second\n");
	addr = (uintptr_t)&scratch[0];
	tb_set_poison_addr((uintptr_t)&scratch[1]);
	clear_exception_state();
	LD_CLOBBER_SECOND(addr);
	tb_assert(addr == (uintptr_t)&scratch[0], "bad address\n");
	tb_assert(read_csr(mcause) == 5, "bad exception cause\n");

	tb_puts("ld, clobber first, no fault\n");
	addr = (uintptr_t)&scratch[0];
	tb_set_poison_addr(-1u);
	clear_exception_state();
	LD_CLOBBER_FIRST(addr);
	tb_assert(addr == scratch[0], "bad load result\n");
	tb_assert(read_csr(mcause) == 0, "bad exception cause\n");

	tb_puts("ld, clobber second, no fault\n");
	addr = (uintptr_t)&scratch[0];
	tb_set_poison_addr(-1u);
	clear_exception_state();
	LD_CLOBBER_SECOND(addr);
	tb_assert(addr == scratch[1], "bad load result\n");
	tb_assert(read_csr(mcause) == 0, "bad exception cause\n");

	// Store faults

	tb_puts("sd, even base, fault first\n");
	addr = (uintptr_t)&scratch[0];
	tb_set_poison_addr((uintptr_t)&scratch[0]);
	clear_exception_state();
	SD_EVEN_BASE(addr);
	tb_assert(addr == (uintptr_t)&scratch[0], "bad address\n");
	tb_assert(read_csr(mcause) == 7, "bad exception cause\n");

	tb_puts("sd, even base, fault second\n");
	addr = (uintptr_t)&scratch[0];
	tb_set_poison_addr((uintptr_t)&scratch[1]);
	clear_exception_state();
	SD_EVEN_BASE(addr);
	tb_assert(addr == (uintptr_t)&scratch[0], "bad address\n");
	tb_assert(read_csr(mcause) == 7, "bad exception cause\n");

	tb_puts("sd, odd base, fault first\n");
	addr = (uintptr_t)&scratch[0];
	tb_set_poison_addr((uintptr_t)&scratch[0]);
	clear_exception_state();
	SD_ODD_BASE(addr);
	tb_assert(addr == (uintptr_t)&scratch[0], "bad address\n");
	tb_assert(read_csr(mcause) == 7, "bad exception cause\n");

	tb_puts("sd, odd base, fault second\n");
	addr = (uintptr_t)&scratch[0];
	tb_set_poison_addr((uintptr_t)&scratch[1]);
	clear_exception_state();
	SD_ODD_BASE(addr);
	tb_assert(addr == (uintptr_t)&scratch[0], "bad address\n");
	tb_assert(read_csr(mcause) == 7, "bad exception cause\n");

	tb_set_poison_addr(-1u);

	// Load and store alignment (should just fault on Hazard3)

	scratch[0] = 0;
	scratch[1] = 1;
	for (uint32_t i = 1u; i <= 3u; ++i) {
		tb_printf("ld, align = %u\n", i);
		addr = (uintptr_t)&scratch[0] + i;
		clear_exception_state();
		asm volatile (
			"mv a0, %0\n"
			"zilsd.ld x_a0, x_a0, 0\n"
			"mv %0, a0\n"
			: "+r" (addr)
			:
			: "a0", "a1", "memory"
		);
		tb_assert(addr == (uintptr_t)&scratch[0] + i, "bad address\n");
		tb_assert(read_csr(mcause) == 4, "bad mcause\n");

		tb_printf("sd, align = %u\n", i);
		clear_exception_state();
		asm volatile (
			"mv a0, %0\n"
			"mv a1, %0\n"
			"zilsd.sd x_a0, x_a0, 0\n"
			: "+r" (addr)
			:
			: "a0", "a1", "memory"
		);
		tb_assert(scratch[0] == 0, "scratch[0] overwritten\n");
		tb_assert(scratch[1] == 1, "scratch[1] overwritten\n");
		tb_assert(read_csr(mcause) == 6, "bad mcause\n");
	}

	return 0;

}
