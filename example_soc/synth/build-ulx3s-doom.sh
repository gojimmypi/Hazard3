#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIRMWARE_DIR="${SCRIPT_DIR}/hazard3-fw"

require_file()
{
    local path="$1"

    [[ -f "${path}" ]] || {
        echo "Missing required file: ${path}" >&2
        exit 1
    }
}

require_tool()
{
    local tool="$1"

    command -v "${tool}" >/dev/null 2>&1 || {
        echo "Missing required tool: ${tool}" >&2
        exit 1
    }
}

require_tool make
require_file "${SCRIPT_DIR}/ULX3S.mk"
require_file "${FIRMWARE_DIR}/build.sh"
require_file "${FIRMWARE_DIR}/doom/build-doom-image.sh"

printf 'Building the ULX3S 85F Performance-R5 FPGA...\n'
(
    cd "${SCRIPT_DIR}"
    make -B -f ULX3S.mk
)

printf '\nBuilding the shared 50 MHz monitor with the 64 MiB map...\n'
(
    cd "${FIRMWARE_DIR}"
    HAZARD3_MEMORY_PROFILE=64m \
    HAZARD3_SYS_CLK_HZ=50000000 \
        ./build.sh
)

printf '\nBuilding the shared Performance-R5 Doom image...\n'
(
    cd "${FIRMWARE_DIR}"
    HAZARD3_MEMORY_PROFILE=64m \
        ./doom/build-doom-image.sh
)

require_file "${SCRIPT_DIR}/fpga_ulx3s.bit"
require_file "${FIRMWARE_DIR}/hazard3-test.elf"
require_file \
    "${FIRMWARE_DIR}/doom/build-doom-image/hazard3-doom.h3d"

printf '\nULX3S 85F Performance-R5 build complete.\n'
printf '  FPGA:    %s\n' "${SCRIPT_DIR}/fpga_ulx3s.bit"
printf '  Monitor: %s\n' "${FIRMWARE_DIR}/hazard3-test.elf"
printf '  Doom:    %s\n' \
    "${FIRMWARE_DIR}/doom/build-doom-image/hazard3-doom.h3d"
