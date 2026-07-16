# Hazard3 Doom on ULX4M-LD using native Verilog

This target is parallel to the working ULX3S target. It uses Yosys,
nextpnr-ecp5, ecppack, Hazard3 RTL, and a checked-in native-Verilog DDR3
controller. It does not use LiteX, Migen, or generated LiteDRAM HDL.

## Hardware target

```text
ULX4M-LD PCB revision: v0.0.2
FPGA: LFE5UM-85F-8BG381C
DDR3: MT41K256M16, 512 MiB physical
Carrier HDMI connector: CM4-IO-BASE-A HDMI0
```

Only the low 64 MiB of DDR3 is exposed to software. The existing ULX3S Doom
image, heap, IWAD, video, and diagnostic-alias addresses therefore remain
unchanged.

## Native-Verilog DDR3 dependency

The target uses the ECP5 implementation from UberDDR3, pinned to commit:

```text
4a51b9671347130759c9980d6756918f084e2124
```

From `example_soc/synth`, populate the five required RTL files:

```bash
make -f ULX4M_LD_85F.mk fetch-uberddr3
```

The fetched source is GNU GPL version 3 or later. Review the upstream license
before distributing a combined source tree or bitstream.

## Build

Build the exact `LFE5UM-85F-8BG381C` variant:

```bash
make -B -f ULX4M_LD_85F.mk bit-um
```

The build log must contain all three selections:

```text
nextpnr-ecp5 ... --um-85k ... --speed 8 ...
ecppack ... --idcode 0x01113043 ...
Part: LFE5UM-85F-8CABGA381
```

Enter DFU with either ULX4M `SW1` slider ON, then program the named bitstream
through the proven Windows openFPGALoader path from WSL:

```bash
make -f ULX4M_LD_85F.mk program-um
```

Power off after programming, return both `SW1` sliders to OFF, and power the
module normally.

To build the FPGA, 25 MHz monitor, and matching 64 MiB Doom image in one step:

```bash
./build-ulx4m-ld-doom.sh
```

D7 is a one-hertz hardware heartbeat driven directly from the 25 MHz board
oscillator. Before DDR3 calibration completes, D6 and D5 show the video and DDR
PLL locks and D4-D0 show UberDDR3 `state_calibrate[4:0]`. After calibration,
D6-D0 return to Hazard3 GPIO while D7 remains the hardware heartbeat. Rebuild
the monitor for the 25 MHz system clock:

```bash
HAZARD3_MEMORY_PROFILE=64m HAZARD3_SYS_CLK_HZ=25000000 ./build.sh
```

Then load `hazard3-test.elf`. The monitor now waits up to five seconds for
DDR3 calibration before touching external memory. If calibration does not
complete, the UART monitor remains responsive and refuses external-memory and
Doom commands rather than hanging on its boot test. Run the complete
qualification before uploading Doom or a WAD.

## UART

The module FTDI routing is:

```text
FPGA uart_rx: N4, data from FTDI to FPGA
FPGA uart_tx: N3, data from FPGA to FTDI
115200 8N1 at the 25 MHz Hazard3 system clock
```

## Initial qualification order

1. Confirm D7 blinks and both PLL lock indicators appear during DDR3 initialization.
2. Wait for UberDDR3 state 23 and the transition to Hazard3 GPIO on D6-D0.
3. Load the 25 MHz monitor and confirm `External memory initialization: READY`.
4. Confirm the automatic 64 KiB boot test passes.
5. Run `q` for the complete address, pattern, and pseudorandom qualification.
6. Run `k`, `d`, and `x` for heap, Doom-platform, and execute-from-DDR tests.
7. Confirm HDMI0 displays the automatic monitor framebuffer test pattern.
8. Upload the linked Doom image and IWAD, then launch with `j`.

The standalone all-LED configuration diagnostic is hardware-verified on the
installed `LFE5UM-85F-8BG381C`. The full DDR3, monitor, HDMI, and Doom path still
requires the qualification sequence above before this target should be called
fully supported.
