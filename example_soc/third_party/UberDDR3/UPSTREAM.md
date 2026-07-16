# UberDDR3 source dependency

The ULX4M-LD target uses the native-Verilog ECP5 implementation from
`AngeloJacobo/UberDDR3`.

Pinned upstream commit:

```text
4a51b9671347130759c9980d6756918f084e2124
```

Populate the required source files once from the `example_soc` directory:

```bash
./third_party/UberDDR3/fetch_sources.sh
```

The script copies only these upstream files:

```text
LICENSE
rtl/ddr3_top.v
rtl/ddr3_controller.v
rtl/ecp5_phy/ddr3_phy_ecp5.v
rtl/ecp5_phy/iserdes_soft.v
rtl/ecp5_phy/oserdes_soft.v
```

Files that already match are left untouched, so repeating the fetch does not
change their timestamps.

It prepends `` `define LATTICE_ECP5_PHY `` to the local copy of
`rtl/ddr3_top.v`, selecting the ECP5 PHY rather than the Xilinx PHY. It also
forwards `DDR3_CLK_PERIOD`, `ODELAY_SUPPORTED`, and `DUAL_RANK_DIMM` into the
ECP5 PHY instance; those parameter forwards are absent from the pinned upstream
top-level file.

UberDDR3 is licensed under GNU GPL version 3 or later. Review that license
before distributing a bitstream or a combined source tree containing it.
