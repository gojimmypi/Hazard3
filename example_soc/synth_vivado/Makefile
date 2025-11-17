include ../project_paths.mk

DOTF=$(PROJ_ROOT)example_soc/fpga/fpga_arty_a7.f

FILES=$(shell HDL=$(HDL) $(SCRIPTS)/listfiles $(DOTF))
INCDIRS=$(shell HDL=$(HDL) $(SCRIPTS)/listfiles -f flati $(DOTF))

.PHONY: bit prog clean

bit: fpga.bit

fpga.bit: $(FILES) $(INCDIR) $(wildcard *.xdc) synth.tcl
	@echo "set FILES {$(FILES)}" > filelist.tcl
	@echo "set INCDIRS {$(INCDIRS)}" >> filelist.tcl
	vivado -mode batch -source synth.tcl 2>&1 | tee synth.log

prog: fpga.bit
	vivado -mode batch -source program.tcl

clean:
	rm -f *.dcp *.log *.jou *.bit *.rpt filelist.tcl
	rm -rf .Xil
