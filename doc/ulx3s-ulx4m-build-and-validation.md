# ULX3S and ULX4M-LD build and validation

This document describes the supported Hazard3-Doom board builds, their shared
software profile, and the minimum acceptance checks for generated artifacts.
Reusable board hardware remains in the pinned Hazard3 dependency; complete
Doom release orchestration belongs to Hazard3-Doom.

## Supported targets

| Target | FPGA | nextpnr selector | External memory | Software profile | Hazard3 clock |
| --- | --- | --- | --- | --- | ---: |
| ULX3S 85F | LFE5U-85F-6BG381C | `--85k` | 64 MiB SDR SDRAM | `64m` | 50 MHz |
| ULX4M-LD v0.0.3 | LFE5UM-85F-8BG381C | `--um-85k --speed 8` | LiteDRAM DDR3 | `64m` | 50 MHz |

The ULX3S 12K is not supported by this hardware configuration. The 128 KiB
boot SRAM, 64 KiB unified cache, double 320x200 indexed framebuffer, palette
RAM, and remaining SoC logic exceed its EBR capacity.

The FPGA selector and packed bitstream ID must match the installed device:

| Target | Bitstream IDCODE |
| --- | --- |
| ULX3S 85F | `0x41113043` |
| ULX4M-LD v0.0.3 | `0x01113043` |

Do not use the `--um-85k` or `--um5g-85k` selectors for the ULX3S LFE5U
device. Those selectors identify different ECP5 variants.

## Board-level memory selection

The shared Hazard3 `example_soc` supports both external-memory implementations.
Each board top selects exactly one:

| Target | `SDRAM_ENABLE` | `LITEDRAM_ENABLE` | `SDRAM_COL_WIDTH` | Selected implementation |
| --- | ---: | ---: | ---: | --- |
| ULX3S 85F | 1 | 0 | 10 | `ahb_sdram.v` and `ulx3s_sdram_controller.v` |
| ULX4M-LD | 1 | 1 | unused | `ahb_litedram.v` and the generated LiteDRAM core |

`SDRAM_ENABLE` enables the external-memory target in the shared SoC.
`LITEDRAM_ENABLE` selects LiteDRAM in place of the SDR SDRAM controller.

The board tops set these parameters explicitly and terminate unused memory
ports. They do not rely on the default value of `LITEDRAM_ENABLE` or an open
LiteDRAM reference-clock input.

## Shared software profile

Both targets use the same 50 MHz, 64 MiB monitor ELF and Doom H3D image. The
software reads the FPGA and memory build identifiers at runtime to distinguish
the active bitstream. Only the FPGA bitstream is board-specific.

The monitor, Doom image, and WAD uploader must all use the same memory profile.

## Video presentation

Doom retains its native 320x200 8-bit indexed working screen and defaults to
high detail with view size 10. For the normal presentation path, software
writes a completed frame directly through the video APB aperture into the
inactive ECP5 block-RAM framebuffer. A presentation command queues the bank
swap at vertical blank.

The video hardware maps all 320 source pixels across the 1024-pixel active
width and repeats each of the 200 source rows three times for 600 output rows.
This avoids the per-frame software copy to external memory and the subsequent
external-memory-to-block-RAM DMA. The earlier staging and DMA path remains
available as a compatibility and monitor-diagnostic fallback. Software selects
the direct path when video status bit 9 is present.

## Complete builds

Initialize the pinned dependencies before the first build:

```bash
./scripts/setup-submodules.sh
```

Run the complete builds from the Hazard3-Doom repository root:

```bash
./scripts/build-ulx3s-doom.sh
./scripts/build-ulx4m-ld-doom.sh
```

The wrappers synthesize the hardware in `third_party/Hazard3`, run nextpnr with
the integration project's heap placer and fixed seed, and then build the shared
monitor and Doom image.

Expected outputs:

```text
build/ulx3s/fpga_ulx3s.bit
build/ulx4m-ld/fpga_ulx4m_ld.bit
build/hazard3-test.elf
build/doom-image/hazard3-doom.h3d
```

Set `HAZARD3_ROOT` to test a different Hazard3 checkout without changing the
submodule pointer.

## Timing policy

The Hazard3-Doom wrappers reject timing failure by default. For diagnostic
bring-up only, a developer may explicitly allow a failing result:

```bash
ALLOW_TIMING_FAILURE=1 ./scripts/build-ulx3s-doom.sh
ALLOW_TIMING_FAILURE=1 ./scripts/build-ulx4m-ld-doom.sh
```

Artifacts built with that override are not release candidates. Before hardware
acceptance, require every constrained clock to pass, including the 50 MHz
Hazard3 system clock and the video clocks. Keep the nextpnr log with the build
record. By default, that log is
`third_party/Hazard3/example_soc/synth/pnr.log`.

The generic Hazard3 Makefiles may permit timing failure during bring-up. Their
ability to emit a bitstream does not replace the strict wrapper check.

## Runtime identification

Run monitor command `v` after loading the monitor.

ULX4M-LD must report:

```text
firmware_id=0x48335235
fpga_id=0x4C445035
ddr_core_id=0x32343132
ddr_adapter_id=0x41444C35
build_match=YES
memory_controller=LiteDRAM-2024.12/ECP5DDRPHY
```

ULX3S must report:

```text
firmware_id=0x48335235
fpga_id=0x554C5035
ddr_core_id=0x53445235
ddr_adapter_id=0x41485335
build_match=YES
memory_controller=ULX3S-SDR-SDRAM
```

At Doom image startup, require:

```text
doom_image_id=0x44335235
presentation path: direct APB-to-EBR
performance mode: 50 MHz CPU, direct EBR present, high detail, view size 10
startup mode: Doom title/demo attract loop
```

## Runtime acceptance

For each supported board:

1. Confirm monitor command `v` reports the expected identifiers and
   `build_match=YES`.
2. Confirm command `q` completes external-memory qualification with `PASS`.
3. Confirm the Doom image identifier and all expected startup messages.
4. Run the attract sequence or gameplay for at least 60 seconds.
5. Press `Ctrl-X`, confirm UART capture overflows remain zero, and verify that
   command `j` restarts Doom without another upload.
6. Record the bitstream, monitor, Doom image, submodule commits, nextpnr seed,
   tool versions, and timing report together.
