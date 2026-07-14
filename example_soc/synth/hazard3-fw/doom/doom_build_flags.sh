#!/bin/bash

# Shared build flags for the Hazard3 Doom image and size probe.
#
# GCC 12.2.0 has an internal compiler error when this Doom source tree is
# compiled with the earlier -O3 plus Zba/Zbb/Zbs experiment. Keep the complete
# Doom build on the known-working RV32IMA/Os combination. Runtime performance
# still comes from the hardware cache, indexed framebuffer, block-RAM video
# buffers, DMA presentation path, and low-detail renderer.

if [[ -z "${DOOMGENERIC_DIR:-}" || -z "${SCRIPT_DIR:-}" ]]; then
    echo "doom_build_flags.sh must be sourced after SCRIPT_DIR and DOOMGENERIC_DIR are set" >&2
    return 1
fi

DOOM_ARCH_FLAGS=(
    -march=rv32ima_zicsr_zifencei
    -mabi=ilp32
)

DOOM_COMMON_COMPILE_FLAGS=(
    "${DOOM_ARCH_FLAGS[@]}"
    -mcmodel=medany
    -mno-relax
    -Os
    -g3
    -ffunction-sections
    -fdata-sections
    -fno-common
    -fno-pic
    -fno-pie
    -msmall-data-limit=0
    -D_DEFAULT_SOURCE
    -DNORMALUNIX
    -DLINUX
    -DSNDSERV
    -DDOOMGENERIC_RESX=320
    -DDOOMGENERIC_RESY=200
    -DCMAP256
    -DDOOMGENERIC_EXTERNAL_SCREENBUFFER
    -DHAZARD3_SHARED_SCREENBUFFER
    -I"${DOOMGENERIC_DIR}"
    -I"${SCRIPT_DIR}"
)

DOOM_UPSTREAM_WARNING_FLAGS=(
    -Wall
    -Wextra
    -Wno-unused-parameter
    -Wno-unused-but-set-parameter
    -Wno-unused-variable
    -Wno-unused-const-variable
    -Wno-sign-compare
    -Wno-missing-field-initializers
    -Wno-implicit-fallthrough
    -Wno-enum-conversion
    -Wno-type-limits
    -Wno-format
    -Wno-absolute-value
)

DOOM_PORT_WARNING_FLAGS=(
    -Wall
    -Wextra
    -Werror
)

DOOM_LINK_FLAGS=(
    "${DOOM_ARCH_FLAGS[@]}"
    -mcmodel=medany
    -mno-relax
    -nostartfiles
    -no-pie
    -Wl,--no-relax
)
