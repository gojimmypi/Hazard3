#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIRMWARE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
DOOMGENERIC_DIR="${DOOMGENERIC_DIR:-${FIRMWARE_DIR}/third_party/doomgeneric/doomgeneric}"
TOOLCHAIN_PREFIX="${TOOLCHAIN_PREFIX:-/opt/riscv/bin/riscv32-unknown-elf-}"
CC="${TOOLCHAIN_PREFIX}gcc"
SIZE="${TOOLCHAIN_PREFIX}size"
BUILD_DIR="${SCRIPT_DIR}/build-size-probe"

require_tool()
{
    local tool="$1"

    if [[ "${tool}" == */* ]]; then
        [[ -x "${tool}" ]] || {
            echo "Missing required executable: ${tool}" >&2
            exit 1
        }
    else
        command -v "${tool}" >/dev/null 2>&1 || {
            echo "Missing required tool: ${tool}" >&2
            exit 1
        }
    fi
}

require_file()
{
    local path="$1"

    [[ -f "${path}" ]] || {
        echo "Missing required file: ${path}" >&2
        exit 1
    }
}

require_tool "${CC}"
require_tool "${SIZE}"
require_file "${SCRIPT_DIR}/doom_sources.sh"
require_file "${SCRIPT_DIR}/doom_build_flags.sh"
require_file "${DOOMGENERIC_DIR}/doomgeneric.c"
require_file "${DOOMGENERIC_DIR}/doomgeneric.h"

# shellcheck source=doom_sources.sh
source "${SCRIPT_DIR}/doom_sources.sh"
# shellcheck source=doom_build_flags.sh
source "${SCRIPT_DIR}/doom_build_flags.sh"

PORT_SOURCES=(
    doomgeneric_hazard3.c
    hazard3_newlib.c
    hazard3_platform_image.c
    doom_image_main.c
)

for source in "${DOOMGENERIC_SOURCES[@]}"; do
    require_file "${DOOMGENERIC_DIR}/${source}"
done
for source in "${PORT_SOURCES[@]}"; do
    require_file "${SCRIPT_DIR}/${source}"
done

rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"

GCC_VERSION="$("${CC}" -dumpfullversion -dumpversion)"
printf 'RISC-V GCC: %s\n' "${GCC_VERSION}"
printf 'Code generation: %s, %s\n' \
    "${DOOM_ARCH_FLAGS[0]}" "-Os (same flags as loadable image)"

objects=()

for source in "${DOOMGENERIC_SOURCES[@]}"; do
    object="${BUILD_DIR}/${source%.c}.o"
    echo "[CC upstream] ${source}"
    "${CC}" "${DOOM_COMMON_COMPILE_FLAGS[@]}" \
        "${DOOM_UPSTREAM_WARNING_FLAGS[@]}" \
        -c "${DOOMGENERIC_DIR}/${source}" -o "${object}"
    objects+=("${object}")
done

for source in "${PORT_SOURCES[@]}"; do
    object="${BUILD_DIR}/${source%.c}.o"
    echo "[CC port] ${source}"
    "${CC}" "${DOOM_COMMON_COMPILE_FLAGS[@]}" \
        "${DOOM_PORT_WARNING_FLAGS[@]}" \
        -c "${SCRIPT_DIR}/${source}" -o "${object}"
    objects+=("${object}")
done

echo
echo "RV32 Doom object-size total before final link:"
"${SIZE}" -t "${objects[@]}" | tail -n 1

echo
echo "Largest objects:"
"${SIZE}" "${objects[@]}" | awk 'NR > 1 { print }' | sort -k1,1nr | head -n 20

echo
echo "This is a compile/size probe, not the loadable Doom image."
echo "Use ./doom/build-doom-image.sh to link and package the SDRAM image."
