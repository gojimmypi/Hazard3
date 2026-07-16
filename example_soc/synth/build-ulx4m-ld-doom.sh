#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIRMWARE_DIR="${SCRIPT_DIR}/hazard3-fw"
FPGA_LOG="${SCRIPT_DIR}/ulx4m_ld_um_build.log"
BITSTREAM="${SCRIPT_DIR}/fpga_ulx4m_ld_um85.bit"
EXPECTED_PART="Part: LFE5UM-85F-8CABGA381"

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
require_tool strings
require_tool grep
require_tool head
require_tool tee
require_file "${SCRIPT_DIR}/ULX4M_LD_85F.mk"
require_file "${FIRMWARE_DIR}/build.sh"
require_file "${FIRMWARE_DIR}/doom/build-doom-image.sh"

printf 'Building ULX4M-LD FPGA for LFE5UM-85F-8BG381C...\n'
(
    cd "${SCRIPT_DIR}"
    make -B -f ULX4M_LD_85F.mk bit-um 2>&1 | tee "${FPGA_LOG}"
)

part_line="$(strings -a "${BITSTREAM}" | grep -F 'Part:' | head -n 1 || true)"
if [[ "${part_line}" != "${EXPECTED_PART}" ]]; then
    echo "Unexpected FPGA part in ${BITSTREAM}: ${part_line:-not found}" >&2
    echo "Expected: ${EXPECTED_PART}" >&2
    exit 1
fi

if ! grep -F -- '--um-85k' "${FPGA_LOG}" >/dev/null ||
    ! grep -F -- '--speed 8' "${FPGA_LOG}" >/dev/null ||
    ! grep -F -- '--idcode 0x01113043' "${FPGA_LOG}" >/dev/null; then
    echo "FPGA build log does not contain the required UM-85K settings." >&2
    exit 1
fi

printf '\nBuilding the 25 MHz monitor with the 64 MiB ULX4M-LD map...\n'
(
    cd "${FIRMWARE_DIR}"
    HAZARD3_MEMORY_PROFILE=64m \
    HAZARD3_SYS_CLK_HZ=25000000 \
        ./build.sh
)

printf '\nBuilding the linked Doom image with the matching 64 MiB map...\n'
(
    cd "${FIRMWARE_DIR}"
    HAZARD3_MEMORY_PROFILE=64m \
        ./doom/build-doom-image.sh
)

require_file "${FIRMWARE_DIR}/hazard3-test.elf"
require_file "${FIRMWARE_DIR}/doom/build-doom-image/hazard3-doom.h3d"

printf '\nULX4M-LD Doom build complete.\n'
printf '  FPGA:   %s\n' "${BITSTREAM}"
printf '  Monitor:%s\n' "${FIRMWARE_DIR}/hazard3-test.elf"
printf '  Doom:   %s\n' \
    "${FIRMWARE_DIR}/doom/build-doom-image/hazard3-doom.h3d"
printf '\nProgram the FPGA from the synth directory with:\n'
printf '  make -f ULX4M_LD_85F.mk program-um\n'
