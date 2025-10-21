#include "tb_cxxrtl_io.h"
#include "hazard3_csr.h"
#include "zilsd_macros.h"
#include "pmp.h"

// Check that ld/sd return the correct fault if either of the covered words
// lacks read/write permission (respectively).
//
// Check that PMP-failing sd does not write to words that lack permissions.
//
// Check that PMP-failing ld does not write back to the base register.

volatile int mcause = -1;
void __attribute__((interrupt)) handle_exception() {
	mcause = read_csr(mcause);
	write_csr(mcause, 0);
	uint32_t mepc = read_csr(mepc);
	if (((*(uint16_t*)mepc) & 0x3) == 0x3) {
		mepc += 4;
	} else {
		mepc += 2;
	}
	write_csr(mepc, mepc);
}

static uint32_t scratch[4];
static void set_scratch_rwx(int i, bool r, bool w, bool x) {
	write_csr(pmpaddr0, (uintptr_t)&scratch[i] >> 2);
	write_csr(pmpcfg0,
		(PMPCFG_A_NA4 << PMPCFG_A_LSB) |
		(r ? PMPCFG_R_BITS : 0x0) |
		(w ? PMPCFG_W_BITS : 0x0) |
		(x ? PMPCFG_X_BITS : 0x0)
	);
}

uint64_t __attribute__((naked)) ld_even_base(uint32_t *addr, uint32_t unused) {
	asm (
		"zilsd.ld x_a0, x_a0, 0\n"
		"ret\n"
	);
}

uint64_t __attribute__((naked)) ld_even_base_offset(uint32_t *addr, uint32_t unused) {
	asm (
		"addi a0, a0, 2047\n"
		"zilsd.ld x_a0, x_a0, -2047\n"
		"ret\n"
	);
}

uint64_t __attribute__((naked)) ld_odd_base(uint32_t unused, uint32_t *addr) {
	asm (
		"zilsd.ld x_a0, x_a1, 0\n"
		"ret\n"
	);
}

void __attribute__((naked)) sd_even_base(uint64_t data, uint32_t *addr, uint32_t unused) {
	asm (
		"zilsd.sd x_a0, x_a2, 0\n"
		"ret\n"
	);
}

void __attribute__((naked)) sd_odd_base(uint64_t data, uint32_t unused, uint32_t *addr) {
	asm (
		"zilsd.sd x_a0, x_a3, 0\n"
		"ret\n"
	);
}

void __attribute__((naked)) sd_odd_base_offset(uint64_t data, uint32_t unused, uint32_t *addr) {
	asm (
		"addi a3, a3, -2047\n"
		"zilsd.sd x_a0, x_a3, 2047\n"
		"ret\n"
	);
}

int main() {
	write_csr(hazard3_csr_pmpcfgm0, 1u << 0);
	for (int rwx = 0; rwx < 8; ++rwx) {
		bool r = (rwx >> 2) & 1;
		bool w = (rwx >> 1) & 1;
		bool x = (rwx >> 0) & 1;
		tb_printf("R=%d W=%d X=%d\n", r, w, x);
		// Walk PMP region over all four scratch words. ld/sd is always to
		// middle two words.
		for (int i = 0; i < 4; ++i) {
			tb_printf("%d\n", i);
			set_scratch_rwx(i, 1, 1, 1);
			scratch[0] = 0xaaaa0000;
			scratch[1] = 0xaaaa0001;
			scratch[2] = 0xaaaa0002;
			scratch[3] = 0xaaaa0003;
			set_scratch_rwx(i, r, w, x);

			uint64_t ret;
			mcause = -1;
			ret = ld_even_base(&scratch[1], 0);
			if (r || i == 0 || i == 3) {
				tb_assert(mcause == -1, "ld_even_base faulted with read permission\n");
				tb_assert((ret & 0xffffffff) == 0xaaaa0001, "ld_even_base bad readback 0\n");
				tb_assert((ret >> 32) == 0xaaaa0002, "ld_even_base bad readback 1\n");
			} else {
				tb_assert(mcause == 5, "ld_even_base failed to fault\n");
				tb_assert((ret & 0xffffffff) == (uintptr_t)&scratch[1], "ld_even_base clobbered base\n");
			}
			mcause = -1;
			ret = ld_even_base_offset(&scratch[1], 0);
			if (r || i == 0 || i == 3) {
				tb_assert(mcause == -1, "ld_even_base_offset faulted with read permission\n");
				tb_assert((ret & 0xffffffff) == 0xaaaa0001, "ld_even_base_offset bad readback 0\n");
				tb_assert((ret >> 32) == 0xaaaa0002, "ld_even_base_offset bad readback 1\n");
			} else {
				tb_assert(mcause == 5, "ld_even_base_offset failed to fault\n");
				tb_assert((ret & 0xffffffff) == (uintptr_t)&scratch[1] + 2047, "ld_even_base_offset clobbered base\n");
			}
			mcause = -1;
			ret = ld_odd_base(0, &scratch[1]);
			if (r || i == 0 || i == 3) {
				tb_assert(mcause == -1, "ld_odd_base faulted with read permission\n");
				tb_assert((ret & 0xffffffff) == 0xaaaa0001, "ld_odd_base bad readback 0\n");
				tb_assert((ret >> 32) == 0xaaaa0002, "ld_odd_base bad readback 1\n");
			} else {
				tb_assert(mcause == 5, "ld_odd_base failed to fault\n");
				tb_assert((ret >> 32) == (uintptr_t)&scratch[1], "ld_odd_base clobbered base\n");
			}

			mcause = -1;
			sd_even_base(0xbbbb2222bbbb1111ull, &scratch[1], 0);
			set_scratch_rwx(i, 1, 1, 1);
			if (w || i == 0 || i == 3) {
				tb_assert(mcause == -1, "sd_even_base faulted with write permission\n");
				tb_assert(scratch[1] == 0xbbbb1111, "sd_even_base bad write 0: %08x\n", scratch[1]);
				tb_assert(scratch[2] == 0xbbbb2222, "sd_even_base bad write 1: %08x\n", scratch[2]);
			} else {
				tb_assert(mcause == 7, "sd_even_base failed to fault\n");
				if (i == 1) {
					tb_assert(scratch[1] == 0xaaaa0001, "sd_even_base wrote bad permission word 1\n");
				}
				if (i == 2) {
					tb_assert(scratch[2] == 0xaaaa0002, "sd_even_base wrote bad permission word 2\n");
				}
			}

			scratch[0] = 0xaaaa0000;
			scratch[1] = 0xaaaa0001;
			scratch[2] = 0xaaaa0002;
			scratch[3] = 0xaaaa0003;
			set_scratch_rwx(i, r, w, x);
			sd_odd_base(0xbbbb2222bbbb1111ull, 0, &scratch[1]);
			set_scratch_rwx(i, 1, 1, 1);
			if (w || i == 0 || i == 3) {
				tb_assert(mcause == -1, "sd_odd_base faulted with write permission\n");
				tb_assert(scratch[1] == 0xbbbb1111, "sd_odd_base bad write 0: %08x\n", scratch[1]);
				tb_assert(scratch[2] == 0xbbbb2222, "sd_odd_base bad write 1: %08x\n", scratch[2]);
			} else {
				tb_assert(mcause == 7, "sd_odd_base failed to fault\n");
				if (i == 1) {
					tb_assert(scratch[1] == 0xaaaa0001, "sd_odd_base wrote bad permission word 1\n");
				}
				if (i == 2) {
					tb_assert(scratch[2] == 0xaaaa0002, "sd_odd_base wrote bad permission word 2\n");
				}
			}

			scratch[0] = 0xaaaa0000;
			scratch[1] = 0xaaaa0001;
			scratch[2] = 0xaaaa0002;
			scratch[3] = 0xaaaa0003;
			set_scratch_rwx(i, r, w, x);
			sd_odd_base_offset(0xbbbb2222bbbb1111ull, 0, &scratch[1]);
			set_scratch_rwx(i, 1, 1, 1);
			if (w || i == 0 || i == 3) {
				tb_assert(mcause == -1, "sd_odd_base_offset faulted with write permission\n");
				tb_assert(scratch[1] == 0xbbbb1111, "sd_odd_base_offset bad write 0: %08x\n", scratch[1]);
				tb_assert(scratch[2] == 0xbbbb2222, "sd_odd_base_offset bad write 1: %08x\n", scratch[2]);
			} else {
				tb_assert(mcause == 7, "sd_odd_base_offset failed to fault\n");
				if (i == 1) {
					tb_assert(scratch[1] == 0xaaaa0001, "sd_odd_base_offset wrote bad permission word 1\n");
				}
				if (i == 2) {
					tb_assert(scratch[2] == 0xaaaa0002, "sd_odd_base_offset wrote bad permission word 2\n");
				}
			}

		}
	}
	return 0;
}
