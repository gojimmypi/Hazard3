# ULX3S target with cached external SDR SDRAM and an indexed HDMI framebuffer.
# The ULX3S 12K does not have enough EBR capacity for the CPU SRAM, cache,
# framebuffers, and palette RAM used by this hardware configuration.

include ../project_paths.mk

CHIPNAME=fpga_ulx3s
TOP=fpga_ulx3s
DOTF=../fpga/fpga_ulx3s.f

# Match the canonical ULX3S 85F board/sweep default (standard VGA profile).
HAZARD3_HDMI_EXTENDED_MODES ?= 0
ifeq ($(HAZARD3_HDMI_EXTENDED_MODES),1)
DEFINES += HAZARD3_HDMI_EXTENDED_MODES
else ifneq ($(HAZARD3_HDMI_EXTENDED_MODES),0)
$(error HAZARD3_HDMI_EXTENDED_MODES must be 0 or 1)
endif

# The 85F is an LFE5U-85F-6 device; the clock is an independent choice.
HAZARD3_ULX3S_85F_SYS_CLK_MHZ ?= 25
ifneq ($(filter $(HAZARD3_ULX3S_85F_SYS_CLK_MHZ),25 40 50),$(HAZARD3_ULX3S_85F_SYS_CLK_MHZ))
$(error HAZARD3_ULX3S_85F_SYS_CLK_MHZ must be 25, 40, or 50)
endif
DEFINES += HAZARD3_ULX3S_85F_SYS_CLK_MHZ=$(HAZARD3_ULX3S_85F_SYS_CLK_MHZ)

# Register cache-hit responses at higher clock rates, or override explicitly.
# This changes the netlist and must never share a frozen cache with mode 0.
HAZARD3_ULX3S_85F_REGISTERED_READ_HITS ?= $(if $(filter 25,$(HAZARD3_ULX3S_85F_SYS_CLK_MHZ)),0,1)
ifeq ($(HAZARD3_ULX3S_85F_REGISTERED_READ_HITS),1)
DEFINES += HAZARD3_ULX3S_85F_REGISTERED_READ_HITS
else ifneq ($(HAZARD3_ULX3S_85F_REGISTERED_READ_HITS),0)
$(error HAZARD3_ULX3S_85F_REGISTERED_READ_HITS must be 0 or 1)
endif

# EBR SRAM write adapter optimization experiment. Default to the original
# zero-wait write buffer; setting 0 is intentionally opt-in and is not yet
# functionally or timing qualified for production use.
HAZARD3_ULX3S_85F_SRAM_WRITE_BUFFER ?= 1
ifneq ($(filter $(HAZARD3_ULX3S_85F_SRAM_WRITE_BUFFER),0 1),$(HAZARD3_ULX3S_85F_SRAM_WRITE_BUFFER))
$(error HAZARD3_ULX3S_85F_SRAM_WRITE_BUFFER must be 0 or 1)
endif
DEFINES += HAZARD3_ULX3S_85F_SRAM_WRITE_BUFFER=$(HAZARD3_ULX3S_85F_SRAM_WRITE_BUFFER)

# Separate write and read EBR ports: new, opt-in timing experiment.
HAZARD3_ULX3S_85F_SRAM_DUAL_PORT_RW ?= 0
ifneq ($(filter $(HAZARD3_ULX3S_85F_SRAM_DUAL_PORT_RW),0 1),$(HAZARD3_ULX3S_85F_SRAM_DUAL_PORT_RW))
$(error HAZARD3_ULX3S_85F_SRAM_DUAL_PORT_RW must be 0 or 1)
endif
ifeq ($(HAZARD3_ULX3S_85F_SRAM_DUAL_PORT_RW),1)
ifneq ($(HAZARD3_ULX3S_85F_SRAM_WRITE_BUFFER),1)
$(error SRAM_DUAL_PORT_RW=1 requires SRAM_WRITE_BUFFER=1)
endif
endif
DEFINES += HAZARD3_ULX3S_85F_SRAM_DUAL_PORT_RW=$(HAZARD3_ULX3S_85F_SRAM_DUAL_PORT_RW)

# Optional second cycle for the tag-hit and way-select decision. The additional
# AHB wait state is only supported alongside registered cache-hit responses.
HAZARD3_ULX3S_85F_CACHE_TAG_PIPELINE ?= 0
ifneq ($(filter $(HAZARD3_ULX3S_85F_CACHE_TAG_PIPELINE),0 1),$(HAZARD3_ULX3S_85F_CACHE_TAG_PIPELINE))
$(error HAZARD3_ULX3S_85F_CACHE_TAG_PIPELINE must be 0 or 1)
endif
ifeq ($(HAZARD3_ULX3S_85F_CACHE_TAG_PIPELINE),1)
ifneq ($(HAZARD3_ULX3S_85F_REGISTERED_READ_HITS),1)
$(error CACHE_TAG_PIPELINE=1 requires REGISTERED_READ_HITS=1)
endif
endif
DEFINES += HAZARD3_ULX3S_85F_CACHE_TAG_PIPELINE=$(HAZARD3_ULX3S_85F_CACHE_TAG_PIPELINE)

# Registered cache-tag write data addresses the current 27.14 ns worst path.
# 0=unchanged, 1=use registered lookup tag, 2=also separate per-way tag RAM.
# Mode 2 requires the all-zero ULX3S tag preload image (not arbitrary images).
HAZARD3_ULX3S_85F_TAG_RAM_MODE ?= 0
ifneq ($(filter $(HAZARD3_ULX3S_85F_TAG_RAM_MODE),0 1 2),$(HAZARD3_ULX3S_85F_TAG_RAM_MODE))
$(error HAZARD3_ULX3S_85F_TAG_RAM_MODE must be 0, 1, or 2)
endif
DEFINES += HAZARD3_ULX3S_85F_TAG_RAM_MODE=$(HAZARD3_ULX3S_85F_TAG_RAM_MODE)

# Hold each cacheable AHB address in a register before driving the EBR
# address pins. Adds one AHB wait cycle, but breaks the observed 27.92 ns
# CPU-to-cache-data-RAM address path. Not enabled for qualified builds.
HAZARD3_ULX3S_85F_CACHE_ADDR_PIPELINE ?= 0
ifneq ($(filter $(HAZARD3_ULX3S_85F_CACHE_ADDR_PIPELINE),0 1),$(HAZARD3_ULX3S_85F_CACHE_ADDR_PIPELINE))
$(error HAZARD3_ULX3S_85F_CACHE_ADDR_PIPELINE must be 0 or 1)
endif
ifeq ($(HAZARD3_ULX3S_85F_CACHE_ADDR_PIPELINE),1)
ifneq ($(HAZARD3_ULX3S_85F_REGISTERED_READ_HITS),1)
$(error CACHE_ADDR_PIPELINE=1 requires REGISTERED_READ_HITS=1)
endif
endif
DEFINES += HAZARD3_ULX3S_85F_CACHE_ADDR_PIPELINE=$(HAZARD3_ULX3S_85F_CACHE_ADDR_PIPELINE)

SYNTH_OPT=-abc9
# Direct Make invocations should also fail when timing is not met.
PNR_OPT=--speed 6

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
