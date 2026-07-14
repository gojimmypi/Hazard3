include ../project_paths.mk

CHIPNAME=fpga_ulx4m_ls
TOP=fpga_ulx4m_ls
DOTF=../fpga/fpga_ulx4m_ls.f

SYNTH_OPT=-abc9
PLACER=heap
PNR_OPT=--timing-allow-fail

# The current Doom design uses 164 DP16KD blocks. Only an 85K ECP5 has enough
# block RAM for this exact architecture; the common ULX4M-LS 12K cannot fit it.
DEVICE=85k
PACKAGE=CABGA381

include $(SCRIPTS)/synth_ecp5.mk

# Power-up initialization file for the SDRAM cache tag RAM.
$(CHIPNAME).json: ../soc/cache_tags_zero.hex

# JTAG programming through an attached ULX4M HAT/FTDI interface.
prog: bit
	fujprog $(CHIPNAME).bit

# Native ULX4M DFU bootloader programming through the module USB port.
dfu: bit
	dfu-util -a 0 -D $(CHIPNAME).bit -R
