# ULX4M-LD v0.0.3 DDR3 corrective diagnostic update

This update replaces the previous MT41K512M16/1-GB geometry change. The
ULX4M-LD v0.0.3 hardware repository identifies the fitted memory as
MT41K256M16TW-107, a 512-MB x16 DDR3 device.

The update:

- restores the 15-bit DDR3 row address bus;
- restores UberDDR3 `ROW_BITS=15` and `SDRAM_CAPACITY=4`;
- removes the erroneous `ddram_a[15]` constraint;
- retains `--um-85k`, `--speed 8`, and the nextpnr PIOB-compatible DDR clock
  and DQS constraints;
- maps UberDDR3's raw debug word to video APB register 7 at `0x4000c01c`;
- extends the UART `s` status command to print the exact calibration state.

Copy the `example_soc` directory over the repository root, preserving paths.
The files are complete replacements, not patch files.

## Rebuild the FPGA image

```bash
cd /mnt/c/workspace/Hazard3/example_soc/synth
rm -f fpga_ulx4m_ld.json fpga_ulx4m_ld.config \
    fpga_ulx4m_ld.bit fpga_ulx4m_ld.svf
make -f ULX4M_LD_85F.mk
```

Program `fpga_ulx4m_ld.bit` through DFU, power-cycle normally, and reload the
Hazard3 ELF through OpenOCD.

## Rebuild the firmware

```bash
cd /mnt/c/workspace/Hazard3/example_soc/synth/hazard3-fw
HAZARD3_SYS_CLK_HZ=25000000 ./build.sh
```

After loading the rebuilt ELF, enter `s`. The new output includes:

```text
ddr3_debug=0x000000xx ddr3_calib_state=0x000000xx (STATE_NAME)
```

The state is UberDDR3 `state_calibrate[4:0]`. That value identifies the next
hardware or PHY change instead of guessing from the LEDs.

Calibration state values:

```text
 0 IDLE
 1 BITSLIP_DQS_TRAIN_1
 2 MPR_READ
 3 COLLECT_DQS
 4 ANALYZE_DQS
 5 CALIBRATE_DQS
 6 BITSLIP_DQS_TRAIN_2
 7 START_WRITE_LEVEL
 8 WAIT_FOR_FEEDBACK
 9 ISSUE_WRITE_1
10 ISSUE_WRITE_2
11 ISSUE_READ
12 READ_DATA
13 ANALYZE_DATA
14 CHECK_STARTING_DATA
15 BITSLIP_DQS_TRAIN_3
17 BURST_WRITE
18 BURST_READ
19 RANDOM_WRITE
20 RANDOM_READ
21 ALTERNATE_WRITE_READ
22 FINISH_READ
23 DONE_CALIBRATE
24 ANALYZE_DATA_LOW_FREQ
```

Do not retry the Doom image upload until `external_memory_ready=YES`.
