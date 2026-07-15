include ../project_paths.mk

CHIPNAME=fpga_ulx4m_ld
TOP=fpga_ulx4m_ld
DOTF=../fpga/fpga_ulx4m_ld.f

SYNTH_OPT=-abc9
PLACER=heap
PNR_OPT=--timing-allow-fail

DEVICE=um5g-85k
PACKAGE=CABGA381

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

.PHONY: fetch-uberddr3 dfu
