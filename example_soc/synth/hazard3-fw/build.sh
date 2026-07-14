#!/bin/bash

memory_profile="${HAZARD3_MEMORY_PROFILE:-64m}"
case "${memory_profile}" in
64m)
    memory_profile_flags=()
    ;;
32m)
    memory_profile_flags=(-DHAZARD3_SDRAM_32MB)
    ;;
*)
    echo "Unsupported HAZARD3_MEMORY_PROFILE: ${memory_profile} (use 64m or 32m)" >&2
    exit 1
    ;;
esac

printf 'Hazard3 SDRAM profile: %s\n' "${memory_profile}"

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
    "${memory_profile_flags[@]}" \
    start.S main.c \
    doom/doom_image_loader.c doom/doom_wad_loader.c doom/doom_port_smoke.c \
    doom/sdram_exec_test.c doom/sdram_exec_payload.S \
    -o hazard3-test.elf
