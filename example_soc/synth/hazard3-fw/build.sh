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

system_clock_hz="${HAZARD3_SYS_CLK_HZ:-50000000}"
case "${system_clock_hz}" in
25000000|50000000)
    ;;
*)
    echo "Unsupported HAZARD3_SYS_CLK_HZ: ${system_clock_hz} (use 25000000 or 50000000)" >&2
    exit 1
    ;;
esac

system_clock_flags=(-DHAZARD3_SYS_CLK_HZ=${system_clock_hz}u)

printf 'Hazard3 SDRAM profile: %s\n' "${memory_profile}"
printf 'Hazard3 system clock: %s Hz\n' "${system_clock_hz}"

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
    "${system_clock_flags[@]}" \
    start.S main.c \
    doom/doom_image_loader.c doom/doom_wad_loader.c doom/doom_port_smoke.c \
    doom/sdram_exec_test.c doom/sdram_exec_payload.S \
    -o hazard3-test.elf
