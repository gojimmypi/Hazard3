#include "tb_cxxrtl_io.h"
#include "hazard3_csr.h"
#include "amo_outline.h"
#include "pmp.h"

// Check that AMOs fail with mcause=store/AMO fault if an address lacks either
// read or write permissions

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

static uint32_t scratch_word = 0;

static void set_scratch_rwx(bool r, bool w, bool x) {
	write_csr(pmpcfg0,
		(PMPCFG_A_NA4 << PMPCFG_A_LSB) |
		(r ? PMPCFG_R_BITS : 0x0) |
		(w ? PMPCFG_W_BITS : 0x0) |
		(x ? PMPCFG_X_BITS : 0x0)
	);
}

static void test_amo_func(uint32_t (*f)(uint32_t, uint32_t*), bool r, bool w, bool x, uint32_t initial, uint32_t wdata, uint32_t expect) {
	set_scratch_rwx(1, 1, 1);
	scratch_word = initial;
	mcause = -1;
	set_scratch_rwx(r, w, x);
	uint32_t readback = f(wdata, &scratch_word);
	set_scratch_rwx(1, 1, 1);
	if (r && w) {
		tb_assert(mcause == -1, "Unexpected fault: %d\n", mcause);
		tb_assert(scratch_word == expect, "Failed to modify: %08x\n", scratch_word);
		tb_assert(readback == initial, "Bad readback: %08x\n");
	} else {
		tb_assert(mcause == 7, "Not the expected fault: %d\n", mcause);
		tb_assert(scratch_word == initial, "Unexpected modify: %08x\n", scratch_word);
	}
}

int main() {
	write_csr(pmpaddr0, (uintptr_t)&scratch_word >> 2);
	write_csr(hazard3_csr_pmpcfgm0, 1u << 0);
	for (int r = 0; r <= 1; ++r) {
		for (int w = 0; w <= 1; ++w) {
			for (int x = 0; x <= 1; ++x) {
				tb_printf("R=%d W=%d X=%d\n", r, w, x);
				tb_puts("amoswap\n");
				test_amo_func(amoswap, r, w, x, 0x1234, 0x5678, 0x5678);
				tb_puts("amoadd\n");
				test_amo_func(amoadd,  r, w, x, 0x80000001, 1, 0x80000002);
				tb_puts("amoxor\n");
				test_amo_func(amoxor,  r, w, x, 0xaaaaaaaa, 0xffff, 0xaaaa5555);
				tb_puts("amoand\n");
				test_amo_func(amoand,  r, w, x, 0xaaaaaaaa, 0xffff, 0x0000aaaa);
				tb_puts("amoor\n");
				test_amo_func(amoor,   r, w, x, 0xaaaaaaaa, 0xffff, 0xaaaaffff);
				tb_puts("amomin\n");
				test_amo_func(amomin,  r, w, x, -1, 1, -1);
				tb_puts("amomax\n");
				test_amo_func(amomax,  r, w, x, -1, -2, -1);
				tb_puts("amominu\n");
				test_amo_func(amominu, r, w, x, 0x80000000, 0x0, 0x0);
				tb_puts("amomaxu\n");
				test_amo_func(amomaxu, r, w, x, 0x80000000, 0x0, 0x80000000);
			}
		}
	}
	return 0;
}

/*EXPECTED-OUTPUT***************************************************************
R=0 W=0 X=0
amoswap
amoadd
amoxor
amoand
amoor
amomin
amomax
amominu
amomaxu
R=0 W=0 X=1
amoswap
amoadd
amoxor
amoand
amoor
amomin
amomax
amominu
amomaxu
R=0 W=1 X=0
amoswap
amoadd
amoxor
amoand
amoor
amomin
amomax
amominu
amomaxu
R=0 W=1 X=1
amoswap
amoadd
amoxor
amoand
amoor
amomin
amomax
amominu
amomaxu
R=1 W=0 X=0
amoswap
amoadd
amoxor
amoand
amoor
amomin
amomax
amominu
amomaxu
R=1 W=0 X=1
amoswap
amoadd
amoxor
amoand
amoor
amomin
amomax
amominu
amomaxu
R=1 W=1 X=0
amoswap
amoadd
amoxor
amoand
amoor
amomin
amomax
amominu
amomaxu
R=1 W=1 X=1
amoswap
amoadd
amoxor
amoand
amoor
amomin
amomax
amominu
amomaxu
*******************************************************************************/
