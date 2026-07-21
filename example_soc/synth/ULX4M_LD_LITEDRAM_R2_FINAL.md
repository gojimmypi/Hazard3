# ULX4M-LD LiteDRAM R2 final DDR3 implementation

Build name: `ULX4M-LD-LITEDRAM-R2-20260716`

This update removes UberDDR3 from the synthesized design and replaces it with:

- LiteDRAM 2024.12
- LiteX 2024.12
- Migen 0.9.2
- `ECP5DDRPHY`
- `pythondata-cpu-vexriscv` 1.0.1.post407, minimal VexRiscv
- MT41K256M16-class geometry: 15 row bits, 10 column bits, 3 bank bits,
  x16 data, 4 Gbit / 512 MiB
- 25 MHz input, 75 MHz LiteDRAM system clock, 150 MHz ECP5 DDR clock
  (`DDR3-300`)

The embedded LiteX BIOS performs DDR3 initialization, read leveling, and a
memory test. The Hazard3 Wishbone port remains disabled until initialization
passes.

ULX4M DM0/DM1 are held low because they are outside their corresponding DQS
I/O groups. Hazard3 writes use complete 128-bit read/modify/write transactions,
so byte, halfword, and 32-bit stores remain correct.

## Runtime IDs

The firmware `v` and `s` commands must report:

```
firmware_build=H3-ULX4M-LD-LiteDRAM-R2-20260716
firmware_id=0x48335232
fpga_id=0x4C445232 ddr_core_id=0x32343132 ddr_adapter_id=0x41444232 build_match=YES
ddr_controller=LiteDRAM-2024.12/ECP5DDRPHY
```

The FPGA IDs are read from the newly built bitstream. A mismatch proves that
an older bitstream or older firmware is still running.

## Build

From `example_soc/synth`:

```
make -B -f ULX4M_LD_85F.mk
```

No makefile replacement is included. The generated LiteDRAM core intentionally
uses the existing `third_party/UberDDR3/rtl/ddr3_top.v` source-list slot so the
user's local build/program targets remain intact.

Rebuild the Hazard3 firmware after applying the update:

```
cd hazard3-fw
HAZARD3_SYS_CLK_HZ=25000000 ./build.sh
```

After programming and loading firmware, run `v` first, then `s`. DDR success is:

```
external_memory_ready=YES
ddr_status marker=VALID init_done=YES init_error=NO pll_locked=YES user_clock_ready=YES ready=YES
```
