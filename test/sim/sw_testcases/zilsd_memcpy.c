#include "tb_cxxrtl_io.h"
#include <stdint.h>

#define BUF_WORDS 256

static inline uint32_t test_pattern(uint32_t i) {
	return (i + 1) * 0x07050301u;
}

// Loop 1: single ld, two sw
void __attribute__((naked)) copy1(void *dst, const void *src, uint32_t len) {
	(void)dst;
	(void)src;
	(void)len;
	asm volatile (
		"add a2, a2, a1\n"
		"bgeu a1, a2, 2f\n"
	"1:\n"
		// ld a4, a5, (a1)
		".insn 4, 0x00003003 + (14 << 7) + (11 << 15)\n"
		"sw a4, 0(a0)\n"
		"sw a5, 4(a0)\n"
		"addi a0, a0, 8\n"
		"addi a1, a1, 8\n"
		"bltu a1, a2, 1b\n"
	"2:\n"
		"ret\n"
		:
		:
		: "a4", "a5", "a6", "a7"
	);
}


// Loop 2: two lw, single sd
void __attribute__((naked)) copy2(void *dst, const void *src, uint32_t len) {
	(void)dst;
	(void)src;
	(void)len;
	asm volatile (
		"add a2, a2, a1\n"
		"bgeu a1, a2, 2f\n"
	"1:\n"
		"lw a4, 0(a1)\n"
		"lw a5, 4(a1)\n"
		// sd a4, a5, (a0)
		".insn 4, 0x00003023 + (14 << 20) + (10 << 15)\n"
		"addi a0, a0, 8\n"
		"addi a1, a1, 8\n"
		"bltu a1, a2, 1b\n"
	"2:\n"
		"ret\n"
		:
		:
		: "a4", "a5", "a6", "a7"
	);
}

// Loop 3: two ld, two sd (use some immediate bits)
void __attribute__((naked)) copy3(void *dst, const void *src, uint32_t len) {
	(void)dst;
	(void)src;
	(void)len;
	asm volatile (
		"add a2, a2, a1\n"
		"bgeu a1, a2, 2f\n"
	"1:\n"
		// ld a4, a5, 0(a1)
		".insn 4, 0x00003003 + (14 <<  7) + (11 << 15)\n"
		// ld a6, a7, 8(a1)
		".insn 4, 0x00003003 + (16 <<  7) + (11 << 15) + (8 << 20)\n"
		// sd a4, a5, 0(a0)
		".insn 4, 0x00003023 + (14 << 20) + (10 << 15)\n"
		// sd a6, a7, 8(a0)
		".insn 4, 0x00003023 + (16 << 20) + (10 << 15) + (8 <<  7)\n"
		"addi a0, a0, 16\n"
		"addi a1, a1, 16\n"
		"bltu a1, a2, 1b\n"
	"2:\n"
		"ret\n"
		:
		:
		: "a4", "a5", "a6", "a7"
	);
}



uint32_t buf0[BUF_WORDS];
uint32_t buf1[BUF_WORDS];

void init_zero(uint32_t *buf) {
	for (int i = 0; i < BUF_WORDS; ++i) {
		buf[i] = 0;
	}
}

void init_pattern(uint32_t *buf) {
	for (int i = 0; i < BUF_WORDS; ++i) {
		buf[i] = test_pattern(i);
	}
}

void check_pattern(uint32_t *buf) {
	for (int i = 0; i < BUF_WORDS; ++i) {
		tb_assert(
			buf[i] == test_pattern(i),
			"Failure at %08x: expected %08x, got %08x\n",
			(uintptr_t)&buf[i],
			test_pattern(i),
			buf[i]
		);
	}
}


typedef void (*copy_func_t)(void *, const void *, uint32_t);

void test_copy_func(copy_func_t func) {
	init_pattern(buf0);
	init_zero(buf1);
	func(buf1, buf0, sizeof(buf0));
	check_pattern(buf1);
}

int main(void) {
	tb_puts("Single ld\n");
	test_copy_func(copy1);
	tb_puts("Single sd\n");
	test_copy_func(copy2);
	tb_puts("Two ld, two sd\n");
	test_copy_func(copy3);
	return 0;
}
