#!/bin/bash

/opt/riscv/bin/riscv32-unknown-elf-gcc \
    -march=rv32ima_zicsr_zifencei \
    -mabi=ilp32 \
    -Os \
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
