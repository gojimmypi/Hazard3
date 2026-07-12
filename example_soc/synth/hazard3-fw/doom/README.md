# Hazard3 doomgeneric port staging

Upstream Doom source:

- Repository: `ozkl/doomgeneric`
- Expected checkout: `third_party/doomgeneric`
- Upstream license: GNU GPL version 2

Clone the dependency from the `hazard3-fw` directory:

```bash
mkdir -p third_party
git clone https://github.com/ozkl/doomgeneric.git third_party/doomgeneric
```

The Hazard3-specific files in this directory are:

- `doomgeneric_hazard3.c`: implementations of the five doomgeneric platform hooks.
- `hazard3_platform.h`: interface exported by the current firmware.
- `hazard3_newlib.c`: UART-backed newlib system-call layer for a later full link.
- `doom_sources.sh`: upstream source list without a desktop platform backend.
- `build-size-probe.sh`: RV32 compile and object-size report.
- `doom_port_smoke.c`: current on-board memory/timer readiness test.
- `sdram_exec_test.c`: copies and executes an RV32 payload from SDRAM.
- `sdram_exec_payload.S`: position-independent RV32 payload used by that test.

Run the size probe after cloning upstream:

```bash
./doom/build-size-probe.sh
```

The full Doom image is not yet linked into the 128 KiB internal SRAM firmware.
The size report determines whether the next loader should read executable and
read-only sections from SD card, SPI flash, or another persistent source into
SDRAM after the SDRAM controller has been initialized.


## SDRAM executable-code milestone

The size probe shows that Doom cannot fit in the 128 KiB internal SRAM. The
selected memory layout is:

- `0x00000000-0x0001ffff`: internal SRAM monitor, traps, and stack.
- `0x20000000-0x200fffff`: destructive SDRAM diagnostics.
- `0x20100000-0x203fffff`: three MiB Doom executable image reservation.
- `0x20400000-0x23bfffff`: SDRAM heap.
- `0x23c00000-0x23ffffff`: video reservation.

Run UART command `x` before adding a loader. It copies a position-independent
RV32 payload into the Doom image reservation, executes it from SDRAM, confirms
that timer interrupts occur while `mepc` is in SDRAM, and returns to the monitor.
