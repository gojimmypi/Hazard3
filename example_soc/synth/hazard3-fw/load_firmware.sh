#!/bin/bash

/opt/riscv/bin/riscv32-unknown-elf-gdb \
    --batch \
    --quiet \
    hazard3-test.elf \
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
