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

```bash
make -B -f ULX4M_LD_85F.mk bit
```

Load the volatile bitstream through DFU:

```bash
dfu-util -l
make -f ULX4M_LD_85F.mk dfu
```

D7 is a one-hertz hardware heartbeat driven directly from the 25 MHz board
oscillator. Before DDR3 calibration completes, D6 and D5 show the video and DDR
PLL locks and D4-D0 show UberDDR3 `state_calibrate[4:0]`. After calibration,
D6-D0 return to Hazard3 GPIO while D7 remains the hardware heartbeat. Rebuild
the monitor for the 25 MHz system clock:

```bash
HAZARD3_SYS_CLK_HZ=25000000 ./build.sh
```

Then load `hazard3-test.elf` and run the existing SDRAM quick qualification
before uploading Doom or a WAD.

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
3. Rebuild the monitor for the 25 MHz UART divider, then connect OpenOCD and load it.
4. Run the monitor SDRAM quick test and a larger destructive test.
5. Confirm HDMI0 displays the monitor framebuffer.
6. Upload the existing Doom image and IWAD.

This is a first hardware-integration target. It has not yet been calibrated or
place-and-routed on the physical ULX4M-LD in this environment.
