#!/bin/bash

/opt/riscv/bin/riscv32-unknown-elf-gcc \
    -march=rv32imc_zicsr_zifencei_zba_zbb_zbs \
    -mabi=ilp32 \
    -O2 \
    -fomit-frame-pointer \
    -g3 \
    -ffreestanding \
    -fno-builtin \
    -nostdlib \
    -nostartfiles \
    -Wl,-T,link.ld \
    -Wl,-Map=hazard3-test.map \
    -Idoom \
    start.S main.c \
    doom/doom_image_loader.c doom/doom_wad_loader.c doom/doom_port_smoke.c \
    doom/sdram_exec_test.c doom/sdram_exec_payload.S \
    -o hazard3-test.elf
