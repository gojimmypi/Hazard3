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

Run the size probe after cloning upstream:

```bash
./doom/build-size-probe.sh
```

The full Doom image is not yet linked into the 128 KiB internal SRAM firmware.
The size report determines whether the next loader should read executable and
read-only sections from SD card, SPI flash, or another persistent source into
SDRAM after the SDRAM controller has been initialized.
