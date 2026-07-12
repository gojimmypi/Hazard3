#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIRMWARE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
DOOMGENERIC_DIR="${DOOMGENERIC_DIR:-${FIRMWARE_DIR}/third_party/doomgeneric/doomgeneric}"
TOOLCHAIN_PREFIX="${TOOLCHAIN_PREFIX:-/opt/riscv/bin/riscv32-unknown-elf-}"
CC="${TOOLCHAIN_PREFIX}gcc"
SIZE="${TOOLCHAIN_PREFIX}size"
BUILD_DIR="${SCRIPT_DIR}/build-size-probe"

if [[ ! -f "${DOOMGENERIC_DIR}/doomgeneric.c" ]]; then
    printf '%s\n' \
        "Missing ozkl/doomgeneric source at:" \
        "  ${DOOMGENERIC_DIR}" \
        "" \
        "Clone it with:" \
        "  mkdir -p ${FIRMWARE_DIR}/third_party" \
        "  git clone https://github.com/ozkl/doomgeneric.git ${FIRMWARE_DIR}/third_party/doomgeneric" \
        >&2
    exit 1
fi

# shellcheck source=doom_sources.sh
source "${SCRIPT_DIR}/doom_sources.sh"

rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"

COMMON_FLAGS=(
    -march=rv32ima_zicsr_zifencei
    -mabi=ilp32
    -Os
    -g0
    -ffreestanding
    -fno-builtin
    -ffunction-sections
    -fdata-sections
    -fno-common
    -Wall
    -Wextra
    -D_DEFAULT_SOURCE
    -DNORMALUNIX
    -DLINUX
    -DSNDSERV
    -DDOOMGENERIC_RESX=320
    -DDOOMGENERIC_RESY=200
    -DCMAP256
    -I"${DOOMGENERIC_DIR}"
    -I"${SCRIPT_DIR}"
)

objects=()

for source in "${DOOMGENERIC_SOURCES[@]}"; do
    object="${BUILD_DIR}/${source%.c}.o"
    echo "[CC] ${source}"
    "${CC}" "${COMMON_FLAGS[@]}" \
        -c "${DOOMGENERIC_DIR}/${source}" \
        -o "${object}"
    objects+=("${object}")
done

for source in doomgeneric_hazard3.c hazard3_newlib.c; do
    object="${BUILD_DIR}/${source%.c}.o"
    echo "[CC] ${source}"
    "${CC}" "${COMMON_FLAGS[@]}" \
        -c "${SCRIPT_DIR}/${source}" \
        -o "${object}"
    objects+=("${object}")
done

echo
echo "RV32 Doom object-size total before final link and garbage collection:"
"${SIZE}" -t "${objects[@]}" | tail -n 1

echo
echo "Largest objects:"
"${SIZE}" "${objects[@]}" | awk 'NR > 1 { print }' | sort -k1,1nr | head -n 20

echo
echo "This is a compile/size probe, not the loadable Doom image."
echo "Use ./doom/build-doom-image.sh to link and package the SDRAM image."
