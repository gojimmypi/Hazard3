# ULX3S target with cached external SDR SDRAM and an indexed HDMI framebuffer.
# The ULX3S 12K does not have enough EBR capacity for the CPU SRAM, cache,
# framebuffers, and palette RAM used by this hardware configuration.

include ../project_paths.mk

CHIPNAME=fpga_ulx3s
TOP=fpga_ulx3s
DOTF=../fpga/fpga_ulx3s.f

HAZARD3_HDMI_EXTENDED_MODES ?= 1
ifeq ($(HAZARD3_HDMI_EXTENDED_MODES),1)
DEFINES += HAZARD3_HDMI_EXTENDED_MODES
else ifneq ($(HAZARD3_HDMI_EXTENDED_MODES),0)
$(error HAZARD3_HDMI_EXTENDED_MODES must be 0 or 1)
endif

# Select the actual ULX3S-85F system clock. 25 MHz keeps the original RTL.
HAZARD3_ULX3S_85F_SYS_CLK_MHZ ?= 25
ifeq ($(filter $(HAZARD3_ULX3S_85F_SYS_CLK_MHZ),25 40 50),)
$(error HAZARD3_ULX3S_85F_SYS_CLK_MHZ must be 25, 40, or 50)
endif
DEFINES += HAZARD3_ULX3S_85F_SYS_CLK_MHZ=$(HAZARD3_ULX3S_85F_SYS_CLK_MHZ)

# This must match the actual FPGA. Speed 8 is not valid for a speed-6 chip.
ECP5_PNR_SPEED_GRADE ?= 6
ifeq ($(filter $(ECP5_PNR_SPEED_GRADE),6 7 8),)
$(error ECP5_PNR_SPEED_GRADE must be 6, 7, or 8)
endif

SYNTH_OPT=-abc9
# Bring-up target: timing failures remain visible in the nextpnr report.
PNR_OPT=--timing-allow-fail --speed $(ECP5_PNR_SPEED_GRADE)

DEVICE=85k
PACKAGE=CABGA381

include $(SCRIPTS)/synth_ecp5.mk

# power-up initialization file for the new SDRAM cache tag RAM
$(CHIPNAME).json: ../soc/cache_tags_zero.hex ../soc/hazard3-boot-monitor.hex

../soc/hazard3-boot-monitor.hex:
	@echo "Missing $@; run Hazard3-Doom/scripts/build-ulx3s-doom.sh to build the resident monitor preload." >&2
	@false

# Get ujprog from: git@github.com:emard/tools.git
prog: bit
	ujprog $(CHIPNAME).bit

flash: bit
	ujprog -j flash $(CHIPNAME).bit
