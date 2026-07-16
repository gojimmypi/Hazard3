#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GDB="${GDB:-/opt/riscv/bin/riscv32-unknown-elf-gdb}"
ELF="${1:-${SCRIPT_DIR}/hazard3-test.elf}"

if [[ ! -x "${GDB}" ]]; then
    echo "Missing RISC-V GDB executable: ${GDB}" >&2
    exit 1
fi

if [[ ! -f "${ELF}" ]]; then
    echo "Missing firmware ELF: ${ELF}" >&2
    echo "Run ../build-ulx4m-ld-doom.sh from example_soc/synth first." >&2
    exit 1
fi

"${GDB}" \
    --batch \
    --quiet \
    "${ELF}" \
    -ex 'set confirm off' \
    -ex 'set pagination off' \
    -ex 'set remotetimeout 120' \
    -ex 'target extended-remote localhost:3333' \
    -ex 'monitor halt' \
    -ex 'load' \
    -ex 'compare-sections' \
    -ex 'set $pc = _start' \
    -ex 'monitor resume' \
    -ex 'disconnect'
