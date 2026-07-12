# Hazard3 doomgeneric SDRAM image,UART loader and memory-backed IWAD

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
- `0x20400000-0x22bfffff`: Doom heap and zone memory
- `0x22c00000-0x23bfffff`: validated read-only IWAD, up to 16 MiB
- `0x23c00000-0x23ffffff`: future video reservation

The image and IWAD use separate UART protocols. Each transfer sends a fixed
64-byte little-endian header, waits for a monitor data-ready marker, then sends
the payload. The monitor validates range fields and an IEEE CRC32. The IWAD
loader additionally checks the `IWAD` identifier, directory bounds, and every
lump's file range before marking the WAD usable.

## Build and reload the monitor

```bash
./build.sh
```

Reload `hazard3-test.elf` using VisualGDB. Loader commands are:

```text
l    receive a packaged Doom image over UART
w    receive an IWAD into the reserved SDRAM region
j    launch the validated Doom image and IWAD
```

## Build the linked Doom image

The monitor ABI changed for the WAD service fields, so rebuild the image:

```bash
./doom/build-doom-image.sh
```

Output:

```text
doom/build-doom-image/hazard3-doom.h3d
```

## Upload sequence

Close PuTTY or any other program that owns the external UART port.

```bash
python3 -m pip install pyserial
```

First upload the Doom executable without launching it:

```bash
python doom/upload-doom-image.py \
    doom/build-doom-image/hazard3-doom.h3d \
    --port COM6 \
    --launch
```

Or in PowerShell:

```powershell
py .\doom\upload-doom-image.py `
    .\doom\build-doom-image\hazard3-doom.h3d `
    --port COM7
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

Then upload a WAD file and launch. Doom Shareware normally uses
the filename `doom1.wad`:

```powershell
py .\doom\upload-wad.py `
    C:\path\to\doom1.wad `
    --port COM7 `
    --launch
```



The uploader derives the Doom-visible name from the input filename. Use
`--name doom1.wad` when the local file has a different name.

Expected transfer markers are:

```text
H3L READY
H3L DATA
H3L OK
H3W READY
H3W DATA
H3W OK
```

Expected Doom progress includes WAD discovery, Doom's normal startup messages,
the first completed headless frame, several additional game ticks, and:

```text
Doom WAD/game-loop milestone: PASS
```

The executable image is invalidated after it returns because writable `.data`
has changed. The validated IWAD remains loaded, so another run requires only a
new image upload followed by command `j`. Commands `a`, `r`, and `q` invalidate
both image and IWAD because they overwrite those SDRAM regions. Command `x`
invalidates only the executable image.

Video, controls, and sound remain stubbed for this milestone. The next update
connects Doom's 320x200 indexed output to the reserved video region and then to
the ULX3S GPDI pipeline.
