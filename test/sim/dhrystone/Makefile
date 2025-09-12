SRCS       := ../common/init.S src/dhrystone_main.c src/dhrystone.c src/util.c
APP        := dhrystone
CCFLAGS    := -O3 -fno-inline -std=c99 -march=rv32ima_zicsr_zifencei_zba_zbb_zbkb_zbs_zca_zcb_zcmp -Wno-implicit-function-declaration -Wno-implicit-int
MAX_CYCLES := 1000000

include ../common/src_only_app.mk
