include ../project_paths.mk

CHIPNAME=fpga_ulx4m_ld_blinky
TOP=fpga_ulx4m_ld_blinky
DOTF=../fpga/fpga_ulx4m_ld_blinky.f

SYNTH_OPT=-abc9
PLACER=heap
PNR_OPT=--timing-allow-fail --speed 8

# Select the exact ECP5 variant installed on the ULX4M-LD module. The shared
# fpgascripts default IDCODE is for LFE5U-85F and must be overridden for both
# LFE5UM and LFE5UM5G devices.
ULX4M_LD_DEVICE ?= um-85k
DEVICE=$(ULX4M_LD_DEVICE)
PACKAGE=CABGA381

ifeq ($(ULX4M_LD_DEVICE),um-85k)
DEVICE_IDCODE=0x01113043
else ifeq ($(ULX4M_LD_DEVICE),um5g-85k)
DEVICE_IDCODE=0x81113043
else
$(error Unsupported ULX4M_LD_DEVICE '$(ULX4M_LD_DEVICE)'; use um-85k or um5g-85k)
endif

include $(SCRIPTS)/synth_ecp5.mk

# Load through the ULX4M module DFU bootloader.
dfu: bit
	dfu-util -a 0 -D $(CHIPNAME).bit -R

# Build named copies so both device variants can be retained and tested.
bit-um:
	$(MAKE) -B -f ULX4M_LD_BLINKY_85F.mk ULX4M_LD_DEVICE=um-85k bit
	cp $(CHIPNAME).bit $(CHIPNAME)_um85.bit

bit-um5g:
	$(MAKE) -B -f ULX4M_LD_BLINKY_85F.mk ULX4M_LD_DEVICE=um5g-85k bit
	cp $(CHIPNAME).bit $(CHIPNAME)_um5g85.bit

.PHONY: dfu bit-um bit-um5g
