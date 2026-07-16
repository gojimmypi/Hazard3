include ../project_paths.mk

CHIPNAME=fpga_ulx4m_ld
TOP=fpga_ulx4m_ld
DOTF=../fpga/fpga_ulx4m_ld.f

SYNTH_OPT=-abc9
PLACER=heap
PNR_OPT=--timing-allow-fail --speed 8

# Select the exact ECP5 variant installed on the ULX4M-LD module. The shared
# fpgascripts default IDCODE is for LFE5U-85F and must be overridden for both
# LFE5UM and LFE5UM5G devices.
ULX4M_LD_DEVICE ?= um-85k
DEVICE=$(ULX4M_LD_DEVICE)
PACKAGE=CABGA381
OPENFPGALOADER ?= ./openFPGALoader.exe

ifeq ($(ULX4M_LD_DEVICE),um-85k)
DEVICE_IDCODE=0x01113043
else ifeq ($(ULX4M_LD_DEVICE),um5g-85k)
DEVICE_IDCODE=0x81113043
else
$(error Unsupported ULX4M_LD_DEVICE '$(ULX4M_LD_DEVICE)'; use um-85k or um5g-85k)
endif

include $(SCRIPTS)/synth_ecp5.mk

UBERDDR3_SOURCES= \
    ../third_party/UberDDR3/rtl/ddr3_top.v \
    ../third_party/UberDDR3/rtl/ddr3_controller.v \
    ../third_party/UberDDR3/rtl/ecp5_phy/ddr3_phy_ecp5.v \
    ../third_party/UberDDR3/rtl/ecp5_phy/iserdes_soft.v \
    ../third_party/UberDDR3/rtl/ecp5_phy/oserdes_soft.v

# Populate the pinned native-Verilog dependency once, then review and commit
# those source files normally.
fetch-uberddr3:
	../third_party/UberDDR3/fetch_sources.sh

$(UBERDDR3_SOURCES):
	@if [ ! -f "$@" ]; then \
		echo "Missing UberDDR3 native-Verilog source: $@"; \
		echo "Run: make -f ULX4M_LD_85F.mk fetch-uberddr3"; \
		exit 1; \
	fi

# Power-up initialization file for the unified SDRAM/DDR3 cache tag RAM.
$(CHIPNAME).json: ../soc/cache_tags_zero.hex $(UBERDDR3_SOURCES)

# Load through the ULX4M module DFU bootloader.
dfu: bit
	dfu-util -a 0 -D $(CHIPNAME).bit -R

# Build named copies for each FPGA variant. The normal $(CHIPNAME).bit is
# also produced so the existing dfu target and programming commands continue
# to work unchanged. Use make -B with bit-um or bit-um5g to force a rebuild.
$(CHIPNAME)_um85.bit:
	$(MAKE) -B -f ULX4M_LD_85F.mk ULX4M_LD_DEVICE=um-85k bit
	cp $(CHIPNAME).bit $@

$(CHIPNAME)_um5g85.bit:
	$(MAKE) -B -f ULX4M_LD_85F.mk ULX4M_LD_DEVICE=um5g-85k bit
	cp $(CHIPNAME).bit $@

bit-um: $(CHIPNAME)_um85.bit

bit-um5g: $(CHIPNAME)_um5g85.bit

# Program the named variant through the ULX4M USB DFU bootloader. These targets
# use the Windows openFPGALoader binary from WSL, matching the proven board
# programming path. Override OPENFPGALOADER when it is installed elsewhere.
program-um: $(CHIPNAME)_um85.bit
	$(OPENFPGALOADER) --dfu --vid 0x1d50 --pid 0x614b --altsetting 0 \
		$<

program-um5g: $(CHIPNAME)_um5g85.bit
	$(OPENFPGALOADER) --dfu --vid 0x1d50 --pid 0x614b --altsetting 0 \
		$<

.PHONY: fetch-uberddr3 dfu bit-um bit-um5g program-um program-um5g
