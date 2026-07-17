# Hazard3 Doom shared ULX3S/ULX4M build support R5A

This add-on makes ULX3S gating explicit and supplies the ULX3S build path that
was not included in the original Performance-R5 ZIP. It does not modify the
ULX4M-LD files currently being built.

## Supported boards

- ULX4M-LD v0.0.3, LFE5UM-85F-8BG381C, LiteDRAM DDR3.
- ULX3S 85F, external 64 MiB SDR SDRAM.

The ULX3S 12K is not a target for this Doom configuration. The 128 KiB boot
SRAM, 64 KiB unified cache, two 320x200x8 block-RAM framebuffers, palette RAM,
and the rest of the SoC exceed the 12K device's EBR resources.

## Board gating

The shared `example_soc` retains both memory interfaces. The board wrappers
select exactly one implementation:

| Target | SDRAM_ENABLE | LITEDRAM_ENABLE | SDRAM_COL_WIDTH | Memory source |
|---|---:|---:|---:|---|
| ULX3S 85F | 1 | 0 | 10 | `ahb_sdram.v` / `ulx3s_sdram_controller.v` |
| ULX4M-LD | 1 | 1 | unused | `ahb_litedram.v` / generated LiteDRAM core |

`fpga_ulx3s.v` now explicitly sets these values and connects all unused DDR3
ports. It no longer relies on the default value of `LITEDRAM_ENABLE` or on an
open LiteDRAM reference-clock input.

The monitor firmware and H3D are board-neutral at runtime. They identify the
active bitstream using the video APB build-ID registers and accept either the
ULX3S or ULX4M-LD ID set. Both boards must run the 50 MHz, 64 MiB software
profile for the same ELF and H3D to be shared.

## Build ULX4M-LD

From `example_soc/synth`:

```bash
./build-ulx4m-ld-doom.sh
```

Equivalent commands:

```bash
make -B -f ULX4M_LD_85F.mk

cd hazard3-fw
HAZARD3_MEMORY_PROFILE=64m \
HAZARD3_SYS_CLK_HZ=50000000 \
    ./build.sh
HAZARD3_MEMORY_PROFILE=64m ./doom/build-doom-image.sh
```

Program using the established ULX4M DFU command:

```bash
./openFPGALoader.exe --dfu \
    --vid 0x1d50 --pid 0x614b --altsetting 0 \
    fpga_ulx4m_ld.bit
```

## Build ULX3S 85F

From `example_soc/synth`:

```bash
./build-ulx3s-doom.sh
```

Equivalent commands:

```bash
make -B -f ULX3S.mk

cd hazard3-fw
HAZARD3_MEMORY_PROFILE=64m \
HAZARD3_SYS_CLK_HZ=50000000 \
    ./build.sh
HAZARD3_MEMORY_PROFILE=64m ./doom/build-doom-image.sh
```

The generated software files are the same shared files used on ULX4M-LD:

- `hazard3-fw/hazard3-test.elf`
- `hazard3-fw/doom/build-doom-image/hazard3-doom.h3d`

Only the FPGA bitstream is board-specific:

- ULX3S: `fpga_ulx3s.bit`
- ULX4M-LD: `fpga_ulx4m_ld.bit`

## Required timing gate

Both makefiles currently pass `--timing-allow-fail`. A generated bitstream is
not by itself evidence that the 50 MHz CPU target met timing. Before hardware
acceptance, inspect `pnr.log` and require the system-clock report to say `PASS`
at 50 MHz. Also require the 50 MHz video pixel clock to pass.

Do not accept a Performance-R5 bitstream when either required clock says
`FAIL`, even if `ecppack` generated a `.bit` file.

## Runtime acceptance

On either board, load the shared monitor and run `v`.

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

Then require:

1. `q` reports complete memory qualification `PASS`.
2. Doom reports `presentation path: direct APB-to-EBR`.
3. Doom runs the attract sequence or gameplay for at least 60 seconds.
4. `Ctrl-X` returns to the monitor and `j` restarts without another upload.
5. UART capture overflows remain zero.
