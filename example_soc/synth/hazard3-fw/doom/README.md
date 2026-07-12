# Hazard3 doomgeneric SDRAM image and UART loader

Upstream source is `ozkl/doomgeneric`, checked out at
`third_party/doomgeneric` and licensed under GPL-2.0.


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

## Memory map

- `0x00000000-0x0001ffff`: internal-SRAM monitor, traps, and stack
- `0x20000000-0x200fffff`: destructive SDRAM diagnostics
- `0x20100000-0x203fffff`: linked Doom image
- `0x20400000-0x23bfffff`: Doom heap and zone memory
- `0x23c00000-0x23ffffff`: future video reservation

The monitor receives a 64-byte little-endian header followed by a flat binary,
validates all ranges and an IEEE CRC32, clears BSS, executes `fence.i`, and calls
the entry through a versioned monitor service table.

## Build and reload the monitor

```bash
./build.sh
```

Reload `hazard3-test.elf` using VisualGDB. New commands are:

```text
l    receive a packaged Doom image over UART
j    launch the validated Doom image
```

## Build the linked Doom image

```bash
./doom/build-doom-image.sh
```

Output:

```text
doom/build-doom-image/hazard3-doom.h3d
```

The linker does not garbage-collect sections, so the package contains the full
upstream source list, not only the startup test's direct call graph.

## Upload and launch

Close PuTTY first. Install PySerial once if needed:

```bash
python3 -m pip install pyserial
```

Then run, replacing `COM6` with the external UART adapter port:

```bash
python doom/upload-doom-image.py \
    doom/build-doom-image/hazard3-doom.h3d \
    --port COM6 \
    --launch
```

At 115200 baud, a roughly 600 KiB image takes about one minute.

Expected result:

```text
H3L OK elapsed_ms=...
Launching Doom image from SDRAM entry=0x20100000
Doom SDRAM image startup
  monitor ABI: PASS
  320x200 indexed framebuffer allocation: PASS
  Doom zone allocator: PASS bytes=0x00600000
  monitor timer service: PASS
  full Doom engine objects: LINKED
  WAD storage: NOT IMPLEMENTED
Doom SDRAM image startup: PASS
Doom image returned status=0x00000000 ...
```

The image is invalidated after it returns because writable `.data` has changed.
Upload again before relaunching. Commands `a`, `r`, `q`, and `x` also invalidate
a loaded image because they overwrite the image reservation.
