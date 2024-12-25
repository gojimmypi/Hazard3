#include "tb_cxxrtl_io.h"
#include "zilsd_macros.h"
#include <stdint.h>

// Test intent: cover all registers and immediate values for c.sdsp and c.ldsp

#define LDSP_RANGE 512

uint32_t testbuf[2 * (LDSP_RANGE / 4)];

int main() {

	// Use c.sdsp to write a test pattern into testbuf using all registers and
	// immediate values reachable by c.sdsp (but not all combinations)

	asm volatile (
		// save gp as well as sp because gcc seems to ignore the clobber?
		"addi sp, sp, -8\n"
		"sw gp, 0(sp)\n"
		"sw tp, 4(sp)\n"
		"csrw mscratch, sp\n"
		"la sp, testbuf\n"
		"li x1,  1  * 0x07050301\n"
		"li x3,  3  * 0x07050301\n"
		"li x4,  4  * 0x07050301\n"
		"li x5,  5  * 0x07050301\n"
		"li x6,  6  * 0x07050301\n"
		"li x7,  7  * 0x07050301\n"
		"li x8,  8  * 0x07050301\n"
		"li x9,  9  * 0x07050301\n"
		"li x10, 10 * 0x07050301\n"
		"li x11, 11 * 0x07050301\n"
		"li x12, 12 * 0x07050301\n"
		"li x13, 13 * 0x07050301\n"
		"li x14, 14 * 0x07050301\n"
		"li x15, 15 * 0x07050301\n"
		"li x16, 16 * 0x07050301\n"
		"li x17, 17 * 0x07050301\n"
		"li x18, 18 * 0x07050301\n"
		"li x19, 19 * 0x07050301\n"
		"li x20, 20 * 0x07050301\n"
		"li x21, 21 * 0x07050301\n"
		"li x22, 22 * 0x07050301\n"
		"li x23, 23 * 0x07050301\n"
		"li x24, 24 * 0x07050301\n"
		"li x25, 25 * 0x07050301\n"
		"li x26, 26 * 0x07050301\n"
		"li x27, 27 * 0x07050301\n"
		"li x28, 28 * 0x07050301\n"
		"li x29, 29 * 0x07050301\n"
		"li x30, 30 * 0x07050301\n"
		"li x31, 31 * 0x07050301\n"
		".set i, 0\n"
		".rept 4\n"
		"zclsd.sdsp 0,  128 * i + 0\n"
		"zclsd.sdsp 2,  128 * i + 8\n"
		"zclsd.sdsp 4,  128 * i + 16\n"
		"zclsd.sdsp 6,  128 * i + 24\n"
		"zclsd.sdsp 8,  128 * i + 32\n"
		"zclsd.sdsp 10, 128 * i + 40\n"
		"zclsd.sdsp 12, 128 * i + 48\n"
		"zclsd.sdsp 14, 128 * i + 56\n"
		"zclsd.sdsp 16, 128 * i + 64\n"
		"zclsd.sdsp 18, 128 * i + 72\n"
		"zclsd.sdsp 20, 128 * i + 80\n"
		"zclsd.sdsp 22, 128 * i + 88\n"
		"zclsd.sdsp 24, 128 * i + 96\n"
		"zclsd.sdsp 26, 128 * i + 104\n"
		"zclsd.sdsp 28, 128 * i + 112\n"
		"zclsd.sdsp 30, 128 * i + 120\n"
		".set i, (i + 1)\n"
		".endr\n"
		"csrr sp, mscratch\n"
		"lw gp, 0(sp)\n"
		"lw tp, 4(sp)\n"
		"addi sp, sp, 8\n"
		:
		:
		: "x1", "x5", "x6", "x7", "x8", "x9", "x10", "x11", "x12",
		  "x13", "x14", "x15", "x16", "x17", "x18", "x19", "x20", "x21", "x22",
		  "x23", "x24", "x25", "x26", "x27", "x28", "x29", "x30", "x31", "memory"
	);

	tb_puts("Checking sdsp pattern\n");
	for (int i = 0; i < LDSP_RANGE / 4; ++i) {
		int regindex = i % 32;
		uint32_t expected_value =
			regindex == 0 ? 0                   : // zero is hardwired
			regindex == 1 ? 0                   : // {zero, ra} is mapped to {zero, zero}
			regindex == 2 ? (uintptr_t)&testbuf : regindex * 0x07050301;
		tb_assert(
			testbuf[i] == expected_value,
			"Mismatch at %d: expected %08x, got %08x\n",
			i, expected_value, testbuf[i]
		);
	}

	return 0;
}
