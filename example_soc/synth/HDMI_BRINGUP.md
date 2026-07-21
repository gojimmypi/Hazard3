# Hazard3 ULX3S playable-performance HDMI bring-up

The HDMI output remains the proven 1024x600 DVI-compatible GPDI mode for the
Elecrow 7-inch panel. This update changes the framebuffer architecture to remove
continuous SDRAM scanout and software palette conversion.

## Data path

```text
Doom renderer
    320x200 indexed screen in internal SRAM at 0x00010000
        |
        | one unrolled 64,000-byte CPU copy
        v
uncached SDRAM staging buffer 0 or 1
        |
        | hardware presentation DMA, 32,000 halfword reads
        v
inactive full-frame ECP5 block-RAM buffer
        |
        | swap during vertical blank
        v
active block-RAM frame -> palette block RAM -> RGB332 -> TMDS
```

The display repeats each 320x200 source pixel 3x horizontally and vertically,
producing 960x600 with 32-pixel black borders at the left and right.

## Other performance changes

- 64 KiB, two-way unified write-back cache for normal SDRAM accesses
- 32-byte cache lines
- uncached 64 MiB diagnostic alias at `0x24000000` and uncached four-MiB video aperture
- open-page SDRAM controller
- round-robin arbitration between CPU/cache traffic and frame-presentation DMA
- RV32IMC plus Zba/Zbb/Zbs
- faster multiplier and four-bit-per-cycle divide
- Doom `-O3`, low detail, and view size 8
- monitor LED animation moved entirely into the 10 ms timer ISR

The diagnostic alias maps `0x24000000-0x27ffffff` onto the same physical
64 MiB SDRAM as `0x20000000-0x23ffffff`. Destructive qualification uses the
alias so cache state cannot hide physical SDRAM failures. Doom continues to use
the original physical addresses.

## Build

This update modifies the `scripts` submodule build helper so the placer can be
selected per board. The default remains `sa`; `ULX3S.mk` selects `heap` to avoid
the multi-hour simulated-annealing runs seen during framebuffer development.

```bash
cd /mnt/c/workspace/Hazard3/example_soc/synth
make -f ULX3S.mk clean
make -f ULX3S.mk bit
```

Check all three generated clocks and block-RAM utilization:

```bash
grep -E "Max frequency|FAIL|Warning|DP16KD" pnr.log
```

The expected clocks are:

```text
clk_sys        50 MHz
clk_video_pix  50 MHz
clk_tmds_x5   250 MHz
```

`--timing-allow-fail` remains enabled for diagnostic builds. A generated `.bit`
file is not evidence of timing closure; report the complete maximum-frequency
section before increasing the system clock.

Then rebuild the ABI-3 monitor and Doom image:

```bash
cd /mnt/c/workspace/Hazard3/example_soc/synth/hazard3-fw
./build.sh
./doom/build-doom-image.sh
```

Program `fpga_ulx3s.bit` and reload `hazard3-test.elf`. Reprogramming clears the
Doom image and IWAD from SDRAM.

## Static acceptance test

At boot, the monitor writes the RGB332 color-bar/grid image to staging buffer 0,
requests a hardware copy, and waits for a vertical-blank swap. UART output should
include:

```text
HDMI: 1024x600, block-RAM double buffer, indexed/RGB332
Internal screen: 0x00010000-0x0001F9FF (320x200 indexed)
HDMI framebuffer test pattern:
  block-RAM present: PASS
```

The `f` command rewrites and presents the test image. The image should remain
stable because the live display frame resides in block RAM after presentation.

LED0 through LED6 should continue their chase and LED7 should continue its
heartbeat during monitor operation, uploads, and Doom. If they stop, capture the
UART status output so timer interrupt progress can be checked.

## Doom acceptance test

Expected markers:

```text
Doom platform: cached indexed renderer + block-RAM HDMI initialized
Doom renderer: first indexed block-RAM frame queued
Doom interactive HDMI loop: READY
```

Press Ctrl-X after at least 20 seconds of movement. Preserve the reported frame,
copy-cycle, and presentation-cycle counters. Those measurements distinguish Doom
render time from the remaining 64 KiB staging copy and hardware DMA time.
