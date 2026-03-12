#include "tb_cxxrtl_io.h"
#include "hazard3_csr.h"

#define TCONTROL_MPTE 0x80
#define TCONTROL_MTE 0x08

#define MCONTROL_ACTION_LSB 12
#define MCONTROL_M 0x40
#define MCONTROL_U 0x08
#define MCONTROL_EXECUTE 0x04

// Test intent: check that a hardware breakpoint on a CSR-writing instruction
// does not write to the CSR register file.

/*EXPECTED-OUTPUT***************************************************************

Enabling breakpoints
In breakpoint: mscratch = 0
After breakpoint: mscratch = 1

*******************************************************************************/

void __attribute__((interrupt)) handle_exception() {
	// Ensure triggers remain disabled when we return
	clear_csr(tcontrol, TCONTROL_MPTE);
	tb_printf("In breakpoint: mscratch = %d\n", read_csr(mscratch));
	// Return directly to excepting instruction -- it should not except the
	// second time because triggers are now disabled (assuming a trigger was
	// the cause for the exception!)
}

int main() {
	int trignum = 0;
	extern char csr_write_instr;
	uintptr_t addr = (uintptr_t)&csr_write_instr;
	write_csr(mscratch, 0);
	write_csr(mcause, 0);
	write_csr(mepc, 0);
	write_csr(tselect, trignum);
	write_csr(tdata1, MCONTROL_M | MCONTROL_EXECUTE);
	write_csr(tdata2, addr);
	tb_printf("Enabling breakpoints\n");
	set_csr(tcontrol, TCONTROL_MTE);
	asm volatile (
	".global csr_write_instr\n"
	"csr_write_instr:\n"
		"csrwi mscratch, 1\n"
	);
	tb_printf("After breakpoint: mscratch = %d\n", read_csr(mscratch));
	tb_assert(read_csr(mepc) == addr, "bad mepc\n");
	tb_assert(read_csr(mcause) == 3, "bad mcause\n");
}
