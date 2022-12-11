ifndef SRCS
$(error Must define list of test sources as SRCS)
endif

ifndef APP
$(error Must define application name as APP)
endif

CCFLAGS      ?=
LDSCRIPT     ?= ../common/memmap.ld
CROSS_PREFIX ?= riscv32-unknown-elf-
TBDIR        ?= ../tb_cxxrtl
INCDIR       ?= ../common
# INCDIR       += /mnt/c/temp/testhaz/hazard3/test/sim/wolfssl_test/wolfssl/
INCDIR       += ./
# INCDIR       += /mnt/c/temp/testhaz/hazard3/test/sim/wolfssl_test/wolfssl/wolfcrypt
# INCDIR       += /mnt/c/temp/testhaz/hazard3/test/sim/wolfssl_test/wolfssl/wolfcrypt/benchmark
MAX_CYCLES   ?= 100000
TMP_PREFIX   ?= tmp/

###############################################################################

.SUFFIXES:
.PHONY: all run view tb clean clean_tb

all: run

run: $(TMP_PREFIX)$(APP).bin
	$(TBDIR)/tb --bin $(TMP_PREFIX)$(APP).bin --vcd $(TMP_PREFIX)$(APP)_run.vcd --cycles $(MAX_CYCLES)

view: run
	gtkwave $(TMP_PREFIX)$(APP)_run.vcd

bin: $(TMP_PREFIX)$(APP).bin

tb:
	$(MAKE) -C $(TBDIR) tb

clean:
	rm -rf $(TMP_PREFIX)

clean_tb: clean
	$(MAKE) -C $(TBDIR) clean

###############################################################################

%: %.c *.h
	$(CC) -W -o $@ $< $(CFLAGS) $(LIBS)

$(TMP_PREFIX)$(APP).bin: $(TMP_PREFIX)$(APP).elf
	$(CROSS_PREFIX)objcopy -O binary $^ $@
	$(CROSS_PREFIX)objdump -h $^ > $(TMP_PREFIX)$(APP).dis
	$(CROSS_PREFIX)objdump -d $^ >> $(TMP_PREFIX)$(APP).dis

$(TMP_PREFIX)$(APP).elf: $(SRCS) $(wildcard %.h)
	mkdir -p $(TMP_PREFIX)
#	$(CROSS_PREFIX)gcc  -Wl,-z,norelro -ffunction-sections -fdata-sections $(CCFLAGS) $(SRCS) -T $(LDSCRIPT) $(addprefix -I,$(INCDIR))  -o $@
	$(CROSS_PREFIX)gcc -Os  -ffunction-sections -fdata-sections $(CCFLAGS) $(SRCS) -T $(LDSCRIPT) $(addprefix -I,$(INCDIR))  -o $@  -Wl,--gc-sections
	$(CROSS_PREFIX)size  $@
	$(CROSS_PREFIX)strip  -s -R .comment -R .gnu.version $@
	$(CROSS_PREFIX)strip  --strip-unneeded $@
	$(CROSS_PREFIX)size  $@

