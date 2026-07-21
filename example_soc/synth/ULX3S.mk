# ULX3S target with cached external SDR SDRAM and an indexed HDMI framebuffer.
# The ULX3S 12K does not have enough EBR capacity for the CPU SRAM, cache,
# framebuffers, and palette RAM used by this hardware configuration.

include ../project_paths.mk

CHIPNAME=fpga_ulx3s
TOP=fpga_ulx3s
DOTF=../fpga/fpga_ulx3s.f

SYNTH_OPT=-abc9
# Bring-up target: timing failures remain visible in the nextpnr report.
PNR_OPT=--timing-allow-fail

DEVICE=um5g-85k
PACKAGE=CABGA381

include $(SCRIPTS)/synth_ecp5.mk

# power-up initialization file for the new SDRAM cache tag RAM
$(CHIPNAME).json: ../soc/cache_tags_zero.hex

# Get ujprog from: git@github.com:emard/tools.git
prog: bit
	ujprog $(CHIPNAME).bit

flash: bit
	ujprog -j flash $(CHIPNAME).bit
