# Hazard3 Doom Performance R5 for ULX3S and ULX4M-LD

Performance-R5 keeps Doom's original 320x200 indexed framebuffer. It restores
Doom high-detail rendering, fills the entire 1024x600 HDMI panel in hardware,
and removes the expensive external-memory copy/DMA sequence from each frame.

This is the intended performance/resolution tradeoff for a 50 MHz Hazard3:
render the original 320x200 game at full Doom detail, then scale it in FPGA
logic. Rendering Doom internally at 640x400 would process four times as many
pixels and would be substantially slower.

## Main changes

- ULX4M-LD Hazard3 clock: 25 MHz -> 50 MHz.
- ULX3S remains at its proven 50 MHz clock.
- Shared Doom/monitor ELF and H3D code for the 64 MiB memory profile.
- Shared direct APB-to-ECP5-block-RAM framebuffer upload.
- No per-frame Doom write into external SDRAM/DDR3.
- No per-frame external-memory-to-block-RAM video DMA.
- Fractional horizontal scaling: 320 source pixels fill all 1024 panel pixels.
- Exact vertical scaling: 200 source lines fill all 600 panel lines.
- Default Doom view: high detail, screen size 10.
- Compiler optimization: conservative `-O2`.
- ULX4M-LD memory implementation renamed and organized as LiteDRAM.
- UberDDR3 is not synthesized, referenced, or required.

The original external-memory video DMA remains only as a compatibility and
monitor-diagnostic fallback. Doom selects the direct path when status bit 9 is
present.

## Runtime versions

Shared monitor:

    firmware_build=H3-DoomPerformance-R5-20260716
    firmware_id=0x48335235

ULX4M-LD bitstream:

    fpga_id=0x4C445035
    ddr_core_id=0x32343132
    ddr_adapter_id=0x41444C35
    memory_controller=LiteDRAM-2024.12/ECP5DDRPHY

ULX3S bitstream:

    fpga_id=0x554C5035
    ddr_core_id=0x53445235
    ddr_adapter_id=0x41485335
    memory_controller=ULX3S-SDR-SDRAM

Shared Doom image:

    doom_image_build=H3-Doom-Performance-R5-20260716
    doom_image_id=0x44335235

## ULX4M-LD build

From `example_soc/synth`:

    make -B -f ULX4M_LD_85F.mk

From `example_soc/synth/hazard3-fw`:

    HAZARD3_MEMORY_PROFILE=64m \
    HAZARD3_SYS_CLK_HZ=50000000 \
        ./build.sh

    HAZARD3_MEMORY_PROFILE=64m ./doom/build-doom-image.sh

Program `fpga_ulx4m_ld.bit`, load the new `hazard3-test.elf`, and upload the new
`hazard3-doom.h3d` and IWAD.

## ULX3S build

From `example_soc/synth`:

    make -B -f ULX3S.mk

The same 50 MHz, 64 MiB monitor ELF and Doom H3D generated above are shared
between ULX3S and ULX4M-LD. The FPGA bitstream remains board-specific.

## Expected Doom startup

    presentation path: direct APB-to-EBR
    performance mode: 50 MHz CPU, direct EBR present, high detail, view size 10
    startup mode: Doom title/demo attract loop

The Options screen can still select low detail, full-screen view size 11, or a
smaller view. High detail and size 10 are the new defaults.

## Validation

After programming and loading:

1. Run `v`; the active board should report `build_match=YES`.
2. Run `q`; external memory should pass.
3. Upload and launch Doom.
4. Let the attract demo or gameplay run for at least 60 seconds.
5. Press Ctrl-X and record the performance counters printed on return.

For the direct path, Doom's external-memory DMA count is zero. `last_copy_cycles`
now measures the direct APB-to-EBR frame upload; `last_present_cycles` includes
the wait for the next vertical-blank swap.

## Local validation performed for this package

- C syntax checked with GCC using `-std=c11 -Wall -Wextra -Werror`.
- Verilog syntax checked with Pyverilog for both board top levels, the shared
  framebuffer, the LiteDRAM adapter, and the shared SoC integration.
- No Yosys, nextpnr-ecp5, or RISC-V GCC installation was available in the
  packaging environment, so the complete FPGA and firmware builds must run in
  the project's established WSL toolchain.
