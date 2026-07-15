# Hazard3 doomgeneric SDRAM image, UART loaders, cached SDRAM, indexed HDMI, and UART controls

Upstream source is `ozkl/doomgeneric`, checked out at
`third_party/doomgeneric` and licensed under GPL-2.0.

Clone the dependency from the `hazard3-fw` directory:

```bash
mkdir -p third_party
git clone https://github.com/ozkl/doomgeneric.git third_party/doomgeneric
```

Find a Doom WAD file, such as the `doom_dos.ZIP/DOOM1.WAD` in the [DOOM v1.9 (Shareware Episode, 1995)](https://archive.org/details/doom_20230531) zip download.

No other downloaded files are needed here, only the WAD file.

The Hazard3-specific files in this directory are:

- `doomgeneric_hazard3.c`: implementations of the doomgeneric platform hooks,
  including UART keyboard input and indexed HDMI frame presentation.
- `doomgeneric_hazard3.h`: Hazard3 doomgeneric platform declarations.
- `hazard3_platform.h`: interface exported by the current firmware.
- `hazard3_monitor_services.h`: monitor ABI service table shared with the
  linked Doom image.
- `hazard3_newlib.c`: UART-backed newlib system-call layer and memory-backed
  read-only IWAD file implementation.
- `doom_sources.sh`: upstream source list without a desktop platform backend.
- `doom_build_flags.sh`: shared, GCC 12.2-safe RV32 compile settings.
- `build-size-probe.sh`: RV32 compile and object-size report.
- `build-doom-image.sh`: full linked Doom image build and H3L packaging.
- `doom_image_format.h`: packaged Doom image header format.
- `hazard3_memory_map.h`: shared ULX3S 64 MiB and ULX4M-LS 32 MiB map.
- `doom_image_loader.c`: monitor-side H3L executable-image receiver.
- `doom_image_main.c`: linked Doom image entry point.
- `doom_wad_format.h`: packaged IWAD header format.
- `doom_wad_loader.c` and `doom_wad_loader.h`: monitor-side H3W IWAD receiver
  and validation.
- `upload-doom-image.py`: host-side H3L image uploader.
- `upload-wad.py`: host-side H3W IWAD uploader.
- `doom_port_smoke.c`: on-board memory/timer readiness test.
- `sdram_exec_test.c`: copies and executes an RV32 payload from SDRAM.
- `sdram_exec_payload.S`: position-independent RV32 payload used by that test.

Run the size probe after cloning upstream:

```bash
./doom/build-size-probe.sh
```

## Performance architecture

This version removes the largest measured costs from the first working HDMI
milestone:

- Doom code, WAD data, and heap use a 64 KiB, two-way, write-back SDRAM cache
  with 32-byte lines.
- The SDRAM controller keeps matching rows open between accesses.
- Doom renders its native 320x200 8-bit indexed screen directly into the upper
  64 KiB of the FPGA internal SRAM at `0x00010000`.
- `DG_DrawFrame()` performs one unrolled 64,000-byte copy into an uncached SDRAM
  staging buffer. It no longer performs 64,000 software palette conversions.
- Hardware copies the completed staging frame into the inactive full-frame ECP5
  block-RAM buffer, then swaps block-RAM buffers during vertical blank.
- A hardware palette RAM converts each Doom index to RGB332 during scanout.
- Doom defaults to low-detail rendering with view size 8. The Doom Options menu
  can select high detail and a larger view when image quality is preferred over
  maximum frame rate.
- The FPGA enables the selected Hazard3 performance features, including faster
  multiply, four-bit-per-cycle divide, and branch prediction.
- GCC 12.2.0 builds the monitor and Doom image with the known-working
  `rv32ima_zicsr_zifencei` and `-Os` combination. Do not restore the earlier
  `-O3` plus Zba/Zbb/Zbs experiment; it causes internal compiler errors in
  multiple upstream Doom source files with this toolchain.
- The LED0-6 chase and LED7 heartbeat run in the machine-timer interrupt, so all
  eight LEDs continue updating while Doom owns the foreground loop.

Actual frame rate depends on place-and-route timing and the workload on screen.
Use the counters printed after Ctrl-X to measure the board rather than assuming
a target frame rate.

## Memory map

Both builds keep the internal 128 KiB SRAM map:

- `0x00000000-0x0000ffff`: monitor, traps, and monitor/Doom stack
- `0x00010000-0x0001f9ff`: Doom 320x200 indexed working screen
- `0x0001fa00-0x0001ffff`: unused internal SRAM

The default `64m` profile is the proven ULX3S map:

- `0x20000000-0x23ffffff`: physical 64 MiB SDRAM
- `0x24000000-0x27ffffff`: uncached diagnostic alias
- `0x20100000-0x203fffff`: cached linked Doom image
- `0x20400000-0x22bfffff`: cached Doom heap and zone memory
- `0x22c00000-0x23bfffff`: cached IWAD reservation, 16 MiB
- `0x23c00000-0x23ffffff`: uncached video reservation

The `32m` profile is for an ULX4M-LS v0.0.2 with a sufficiently large FPGA:

- `0x20000000-0x21ffffff`: physical 32 MiB SDRAM
- `0x24000000-0x25ffffff`: uncached diagnostic alias
- `0x20100000-0x203fffff`: cached linked Doom image
- `0x20400000-0x20ffffff`: cached Doom heap, 12 MiB
- `0x21000000-0x21bfffff`: cached IWAD reservation, 12 MiB
- `0x21c00000-0x21ffffff`: uncached video reservation

Within either video reservation, framebuffer 0 begins at the reservation base
and framebuffer 1 begins 64 KiB later. The HDMI controller registers remain at
`0x4000c000`.

The diagnostic alias mirrors physical SDRAM while bypassing the write-back
cache. The monitor uses it for destructive qualification; Doom uses the
physical cached map. The image and IWAD protocols validate fixed-size headers,
ranges, and IEEE CRC32 values before accepting a transfer.

## Build the FPGA

The monitor service ABI is version 3. Rebuild the FPGA, monitor, and Doom image;
an ABI-3 Doom image will reject an older monitor.

From `example_soc/synth`, build the proven ULX3S target:

```bash
make -f ULX3S.mk clean
make -f ULX3S.mk bit
```

For an ULX4M-LS v0.0.2 populated with an 85F FPGA:

```bash
make -f ULX4M_LS_85F.mk clean
make -f ULX4M_LS_85F.mk bit
```

See `../ULX4M_PORT.md` for the 12F capacity limit, the 32 MiB software profile,
and the separate ULX4M-LD DDR3 integration work.

The ULX3S build selects nextpnr's heap placer. The shared
`scripts/synth_ecp5.mk` change preserves simulated annealing as the default for
other boards.

Inspect `pnr.log` before programming:

```bash
grep -E "Max frequency|FAIL|Warning|DP16KD" pnr.log
```

`ULX3S.mk` still passes `--timing-allow-fail`, so the existence of a bitstream
does not prove timing closure. Do not treat a clock marked `FAIL` as validated.

Program the bitstream matching the selected board. Reprogramming the FPGA
clears SDRAM, so the Doom image and IWAD must both be uploaded again.

## Build and reload the monitor

From `example_soc/synth/hazard3-fw`, use the profile matching the FPGA:

```bash
# ULX3S, default 64 MiB profile
./build.sh

# ULX4M-LS, 32 MiB profile
HAZARD3_MEMORY_PROFILE=32m ./build.sh
```

Output:

```text
hazard3-test.elf
```

The preferred load-and-run path is the standalone GDB loader. Keep OpenOCD
running, ensure VisualGDB is disconnected, and use either:

```bash
./load-and-run.sh
```

or from PowerShell:

```powershell
.\load-and-run.cmd
```

The standalone loader connects, halts, loads `hazard3-test.elf`, sets the entry
point, resumes the CPU, and disconnects. It avoids VisualGDB stack-inspection
timeouts that can send SIGINT and leave the monitor halted.

VisualGDB can still be used for debugging, but the target must be resumed and
detached before UART uploads. Confirm that the LED animations are running and
that the UART monitor responds before starting an uploader.

Loader commands are:

```text
l    receive a packaged Doom image over UART
w    receive an IWAD into the reserved SDRAM region
j    launch the validated Doom image and IWAD
```

## Build the linked Doom image

Rebuild the linked image whenever the monitor ABI or Doom platform code changes.
Use the same profile as the monitor:

```bash
# ULX3S
./doom/build-doom-image.sh

# ULX4M-LS
HAZARD3_MEMORY_PROFILE=32m ./doom/build-doom-image.sh
```

The Doom image build uses the shared `doom/doom_build_flags.sh` settings.

Output:

```text
doom/build-doom-image/hazard3-doom.h3d
```

## Upload sequence

Close PuTTY or any other program that owns the external UART port.

Install pyserial once, when needed:

```bash
python3 -m pip install pyserial
```

First upload the Doom executable without launching it:

```bash
python doom/upload-doom-image.py \
    doom/build-doom-image/hazard3-doom.h3d \
    --port COM7
```

Or in PowerShell:

```powershell
py .\doom\upload-doom-image.py `
    .\doom\build-doom-image\hazard3-doom.h3d `
    --port COM7
```

At 115200 baud, a roughly 600 KiB image takes about one minute.

Then upload a legally obtained IWAD and launch. Doom Shareware normally uses
the filename `doom1.wad`:

```powershell
py .\doom\upload-wad.py `
    C:\path\to\doom1.wad `
    --port COM7 `
    --launch
```

For the ULX4M-LS 32 MiB profile, add `--memory-profile 32m`. The default is
`64m` for ULX3S. The selected uploader profile must match the monitor build.

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

Expected startup and performance-path markers include:

```text
Doom SDRAM image startup
  monitor ABI: PASS
Doom platform: cached indexed renderer + block-RAM HDMI initialized
Doom renderer: first indexed block-RAM frame queued
  performance mode: on-chip screen, 64 KiB cache, low detail, view size 8
Doom interactive HDMI loop: READY
```

The executable image is invalidated after it returns because writable `.data`
has changed. The validated IWAD remains loaded, so another run requires only a
new image upload followed by command `j`.

Commands `a`, `r`, and `q` invalidate both the image and IWAD because they
overwrite those SDRAM regions. Command `x` invalidates only the executable
image.

For later runs without resetting or reprogramming the board, upload only the
rebuilt image, reopen PuTTY, and enter:

```text
j
```

## HDMI presentation details

The Elecrow panel remains at 1024x600. Doom itself remains a native 320x200
indexed renderer. The FPGA repeats every source pixel and line three times,
producing a centered 960x600 image with 32-pixel black side borders.

Two complete 320x200 frames and two matching 256-entry palette banks are stored
in ECP5 block RAM. SDRAM is read only during a requested frame presentation,
rather than continuously for every display refresh. The inactive block-RAM
frame is filled first and becomes visible only during vertical blank, avoiding
the tearing of the earlier single-buffer RGB332 implementation.

For a sharper image, open Doom's Options menu and select High Detail. Increasing
Screen Size enlarges the gameplay viewport. These settings increase renderer
work and can reduce frame rate.

The optional standalone FPGA-generated HDMI test pattern remains available in
`fpga_ulx3s.v` as the disabled `hdmi_test_pattern_u` instance. Keep that code
for display and TMDS bring-up.

## UART interactive controls

After the Doom image reports `Doom interactive HDMI loop: READY`, the external
UART becomes the keyboard input source.

Main-menu controls:

```text
Escape      open menu or go back
W / S       move selection up/down
A / D       adjust left/right
Enter       select or toggle
```

Gameplay controls:

```text
W / S       move forward/backward
A / D       turn left/right
Z / C       strafe left/right
F or Space  fire
E           use/open
M or Tab    automap
P           pause
1-7         select weapon
Enter       menu selection
Escape      menu/back
Ctrl-X      exit Doom and return to the monitor
```

Hold movement keys to use terminal key repeat. Arrow-key escape sequences are
not decoded; use WASD.

Sound remains stubbed in this milestone.

## Performance counters

Ctrl-X prints measured counters:

```text
interactive_frames=... elapsed_ms=... total_frames=...
last_copy_cycles=... last_present_cycles=...
copy_cycles_total=... present_cycles_total=...
```

At a 50 MHz system clock, divide a cycle count by 50,000 to obtain milliseconds.
The `interactive_frames` and `elapsed_ms` values provide the sustained frame
rate for the exact scene tested.
