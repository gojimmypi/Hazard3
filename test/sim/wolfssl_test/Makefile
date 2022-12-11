PROGRAM ?= wolfssl_test

WOLFSSL_SRC_DIR := ./wolfssl

SRCS := ../common/init.S main.c
APP  := wolfssl_test
# CCFLAGS = -march=rv32i -Os -g
# AFLAGS = -march=rv32i
$(info WOLFSSL_SRC_DIR= $(WOLFSSL_SRC_DIR) )

## CCFLAGS = -march=rv32i_zicsr_zba_zbb_zbc_zbs -Os
##AFLAGS = -march=rv32i_zicsr_zba_zbb_zbc_zbs

CCFLAGS = -march=rv32i  -g
AFLAGS = -march=rv32i
# CCFLAGS = -march=rv32i_zicsr_zba_zbb_zbc_zbs -Os -g
# AFLAGS = -march=rv32i_zicsr_zba_zbb_zbc_zbs

# This line must be added in your freedom-e-sdk/scripts/standalone.mk
# RISCV_CFLAGS   += -I$(WOLFSSL_SRC_DIR) -I$(WOLFSSL_SRC_DIR)/IDE/ECLIPSE/SIFIVE -DWOLFSSL_USER_SETTINGS
# WOLFSSL_SRC_DIR variable must be set in the environment when GNU make is started.
# export WOLFSSL_SRC_DIR=~/freedom-e-sdk/software/wolfssl

WOLFSSL_CFLAGS += -I$(WOLFSSL_SRC_DIR) \
				  -DWOLFSSL_USER_SETTINGS

# $(info WOLFSSL_CFLAGS= $(WOLFSSL_CFLAGS) )

# SRCS += $(wildcard $(WOLFSSL_SRC_DIR)/src/*.c)
SRCS += $(wildcard $(WOLFSSL_SRC_DIR)/wolfcrypt/src/*.c)
# SRCS += $(wildcard $(WOLFSSL_SRC_DIR)/wolfcrypt/test/test.c)
SRCS += $(wildcard $(WOLFSSL_SRC_DIR)/wolfcrypt/benchmark/*.c)
# SRCS += $(wildcard $(WOLFSSL_SRC_DIR)/wolfcrypt/benchmark/*.h)
SRCS := $(filter-out %bio.c %evp.c %pk.c %conf.c %x509.c %x509_str.c, $(SRCS))

# $(info SRCS)
# SRC =$(SRC_FILES)
#	 $(WOLFSSL_SRC_DIR)/wolfcrypt/test/test.c
#	 $(WOLFSSL_SRC_DIR)/wolfcrypt/benchmark/benchmark.c

# OPT_CFLAGS = -specs=nano.specs
#OPT_CFLAGS += -O3 -DTIME -DNOENUM -Wno-implicit -mexplicit-relocs -save-temps
#OPT_CFLAGS += -fno-inline -fno-builtin-printf -fno-common -falign-functions=4

# override the __stack_size and __heap_size default values of 0x400
# Hazard3 has variable amounts of data SRAM, depending on target
# The __stack_size and __heap_size symbols are defined in the linker metal.default.ld
# script in the freedom-e-sdk.
override CCFLAGS += $(OPT_CFLAGS) $(WOLFSSL_CFLAGS) \
                     -Xlinker --defsym=__stack_size=0x2700 \
                     -Xlinker --defsym=__heap_size=0x2700


include ../common/src_only_app.mk

# $(PROGRAM): $(SRC)
#	$(CC) $(CFLAGS) $(SRC) $(LDFLAGS) $(LDLIBS) -o $@


