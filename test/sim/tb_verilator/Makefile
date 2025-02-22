include ../project_paths.mk

TOP       = tb
DOTF      = tb.f
CONFIG    = default
TBEXEC    = $(patsubst %.f,%,$(DOTF))

FILE_LIST = $(shell HDL=$(HDL) $(SCRIPTS)/listfiles ../tb_common/$(DOTF))
VINCDIR   = $(shell HDL=$(HDL) $(SCRIPTS)/listfiles -f flati ../tb_common/$(DOTF))
BUILD_DIR = build-$(patsubst %.f,%,$(DOTF))
VOBJ_DIR  = $(BUILD_DIR)/obj_dir
VLIB      = $(VOBJ_DIR)/libV$(TOP).a

VERILATOR_ROOT := $(shell verilator --getenv VERILATOR_ROOT)
CXX       = g++
VERILATOR = verilator

CINCLUDE  = $(VOBJ_DIR) $(VERILATOR_ROOT)/include

.PHONY: clean all lint vcc vlib

all:  $(TBEXEC)
vcc:  $(BUILD_DIR)/vcc.touch
vlib: $(BUILD_DIR)/vlib.touch

$(BUILD_DIR)/vcc.touch: $(FILE_LIST) $(wildcard *.vh)
	mkdir -p $(VOBJ_DIR)
	$(VERILATOR) --Mdir $(VOBJ_DIR) --cc --top-module $(TOP) $(addprefix -I,$(VINCDIR)) $(FILE_LIST)
	touch $@

# CFG_GCH_IF_CLANG is set as a workaround for a verilator issue with newer GCC
# versions (see: https://github.com/verilator/verilator/issues/4730)
$(BUILD_DIR)/vlib.touch: $(BUILD_DIR)/vcc.touch
	$(MAKE) VERILATOR_ROOT=$(VERILATOR_ROOT) CFG_GCH_IF_CLANG=.gch -C $(VOBJ_DIR) -f V$(TOP).mk
	touch $@

clean::
	rm -rf $(BUILD_DIR) $(TBEXEC)

$(TBEXEC): $(BUILD_DIR)/vlib.touch tb.cpp
	$(CXX) -O3 $(addprefix -D,$(CDEFINES) $(CDEFINES_$(DOTF))) \
	  $(addprefix -I ,$(CINCLUDE)) $(wildcard $(VOBJ_DIR)/*.o) tb.cpp -o $(TBEXEC)

lint:
	$(VERILATOR) --lint-only --top-module $(TOP) -I$(HDL) $(FILE_LIST)
