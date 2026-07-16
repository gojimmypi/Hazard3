# LiteDRAM generated core

This directory contains the generated LiteDRAM 2024.12 / LiteX 2024.12
ECP5DDRPHY core used by the ULX4M-LD target.

The core receives the board's 25 MHz oscillator and generates a 75 MHz
LiteDRAM user clock and 150 MHz DDR clock. Hazard3 runs independently at
50 MHz and crosses to the generated Wishbone port through `soc/ahb_litedram.v`.

`generated/LITEDRAM_VERSIONS.txt` records the exact runtime build IDs and
clock configuration.
