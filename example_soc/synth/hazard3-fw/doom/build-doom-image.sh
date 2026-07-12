#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIRMWARE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
DOOMGENERIC_DIR="${DOOMGENERIC_DIR:-${FIRMWARE_DIR}/third_party/doomgeneric/doomgeneric}"
TOOLCHAIN_PREFIX="${TOOLCHAIN_PREFIX:-/opt/riscv/bin/riscv32-unknown-elf-}"
CC="${TOOLCHAIN_PREFIX}gcc"
OBJCOPY="${TOOLCHAIN_PREFIX}objcopy"
NM="${TOOLCHAIN_PREFIX}nm"
SIZE="${TOOLCHAIN_PREFIX}size"
BUILD_DIR="${SCRIPT_DIR}/build-doom-image"
OUTPUT_ELF="${BUILD_DIR}/hazard3-doom.elf"
OUTPUT_BIN="${BUILD_DIR}/hazard3-doom.bin"
OUTPUT_IMAGE="${BUILD_DIR}/hazard3-doom.h3d"

if [[ ! -f "${DOOMGENERIC_DIR}/doomgeneric.c" ]]; then
    printf '%s\n' "Missing ozkl/doomgeneric source at:" "  ${DOOMGENERIC_DIR}" "" \
        "Clone it with:" "  mkdir -p ${FIRMWARE_DIR}/third_party" \
        "  git clone https://github.com/ozkl/doomgeneric.git ${FIRMWARE_DIR}/third_party/doomgeneric" >&2
    exit 1
fi

for tool in "${CC}" "${OBJCOPY}" "${NM}" "${SIZE}" python3; do
    command -v "${tool}" >/dev/null 2>&1 || { echo "Missing required tool: ${tool}" >&2; exit 1; }
done

source "${SCRIPT_DIR}/doom_sources.sh"
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"

COMMON_FLAGS=(
    -march=rv32ima_zicsr_zifencei -mabi=ilp32 -mcmodel=medany -mno-relax
    -Os -g3 -ffunction-sections -fdata-sections -fno-common -fno-pic -fno-pie
    -msmall-data-limit=0 -D_DEFAULT_SOURCE -DNORMALUNIX -DLINUX -DSNDSERV
    -DDOOMGENERIC_RESX=320 -DDOOMGENERIC_RESY=200 -DCMAP256
    -I"${DOOMGENERIC_DIR}" -I"${SCRIPT_DIR}"
)
UPSTREAM_WARNING_FLAGS=(
    -Wall -Wextra -Wno-unused-parameter -Wno-unused-variable
    -Wno-unused-const-variable -Wno-sign-compare -Wno-missing-field-initializers
    -Wno-implicit-fallthrough -Wno-enum-conversion -Wno-type-limits -Wno-format
)
PORT_WARNING_FLAGS=(-Wall -Wextra -Werror)
objects=()

for source in "${DOOMGENERIC_SOURCES[@]}"; do
    object="${BUILD_DIR}/${source%.c}.o"
    echo "[CC upstream] ${source}"
    "${CC}" "${COMMON_FLAGS[@]}" "${UPSTREAM_WARNING_FLAGS[@]}" \
        -c "${DOOMGENERIC_DIR}/${source}" -o "${object}"
    objects+=("${object}")
done

for source in doomgeneric_hazard3.c hazard3_newlib.c hazard3_platform_image.c doom_image_main.c; do
    object="${BUILD_DIR}/${source%.c}.o"
    echo "[CC port] ${source}"
    "${CC}" "${COMMON_FLAGS[@]}" "${PORT_WARNING_FLAGS[@]}" \
        -c "${SCRIPT_DIR}/${source}" -o "${object}"
    objects+=("${object}")
done

entry_object="${BUILD_DIR}/doom_image_entry.o"
echo "[AS] doom_image_entry.S"
"${CC}" "${COMMON_FLAGS[@]}" -c "${SCRIPT_DIR}/doom_image_entry.S" -o "${entry_object}"
objects+=("${entry_object}")

echo "[LD] ${OUTPUT_ELF}"
"${CC}" -march=rv32ima_zicsr_zifencei -mabi=ilp32 -mcmodel=medany -mno-relax \
    -nostartfiles -no-pie -Wl,--no-relax -Wl,-T,"${SCRIPT_DIR}/doom_image_link.ld" \
    -Wl,-Map,"${BUILD_DIR}/hazard3-doom.map" -Wl,--cref -o "${OUTPUT_ELF}" \
    "${objects[@]}" -Wl,--start-group -lc -lm -lgcc -lnosys -Wl,--end-group

echo "[OBJCOPY] ${OUTPUT_BIN}"
"${OBJCOPY}" -O binary "${OUTPUT_ELF}" "${OUTPUT_BIN}"
echo "[PACKAGE] ${OUTPUT_IMAGE}"
python3 "${SCRIPT_DIR}/package-doom-image.py" --elf "${OUTPUT_ELF}" \
    --binary "${OUTPUT_BIN}" --output "${OUTPUT_IMAGE}" --nm "${NM}"
echo
echo "Linked Doom image size:"
"${SIZE}" "${OUTPUT_ELF}"
echo
echo "UART package ready: ${OUTPUT_IMAGE}"
