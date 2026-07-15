/*****************************************************************************\
|                        Copyright (C) 2026 gojimmypi                        |
|                         SPDX-License-Identifier: MIT                       |
\*****************************************************************************/

`default_nettype none

// Generate the clocks required by the native-Verilog ULX4M-LD DDR3 target.
//
// The 50 MHz output is both the Hazard3 system clock and the UberDDR3
// controller clock. The two 200 MHz outputs drive the 4:1 ECP5 DDR3 PHY; the
// second 200 MHz output is phase shifted by 90 degrees.
//
// Divider calculation:
//
//     PFD = 25 MHz / 1
//     primary output = PFD * 8 = 200 MHz
//     VCO = 200 MHz * 3 = 600 MHz
//     controller output = 600 MHz / 12 = 50 MHz
//
// For a divide-by-three 200 MHz output, a 90-degree shift is 0.75 VCO cycles.
// ECP5 represents that as FPHASE=6, where eight fractional phase steps equal
// one VCO cycle.
module pll_25_50_200_90 (
    input  wire clkin,
    output wire clk_controller,
    output wire clk_ddr,
    output wire clk_ddr_90,
    output wire locked
);

(* FREQUENCY_PIN_CLKI="25" *)
(* FREQUENCY_PIN_CLKOP="200" *)
(* FREQUENCY_PIN_CLKOS="200" *)
(* FREQUENCY_PIN_CLKOS2="50" *)
(* ICP_CURRENT="12" *)
(* LPF_RESISTOR="8" *)
(* MFG_ENABLE_FILTEROPAMP="1" *)
(* MFG_GMCREF_SEL="2" *)
EHXPLLL #(
    .PLLRST_ENA       ("DISABLED"),
    .INTFB_WAKE       ("DISABLED"),
    .STDBY_ENABLE     ("DISABLED"),
    .DPHASE_SOURCE    ("DISABLED"),
    .OUTDIVIDER_MUXA  ("DIVA"),
    .OUTDIVIDER_MUXB  ("DIVB"),
    .OUTDIVIDER_MUXC  ("DIVC"),
    .OUTDIVIDER_MUXD  ("DIVD"),

    .CLKI_DIV         (1),
    .CLKFB_DIV        (8),
    .FEEDBK_PATH      ("CLKOP"),

    .CLKOP_ENABLE     ("ENABLED"),
    .CLKOP_DIV        (3),
    .CLKOP_CPHASE     (1),
    .CLKOP_FPHASE     (0),

    .CLKOS_ENABLE     ("ENABLED"),
    .CLKOS_DIV        (3),
    .CLKOS_CPHASE     (1),
    .CLKOS_FPHASE     (6),

    .CLKOS2_ENABLE    ("ENABLED"),
    .CLKOS2_DIV       (12),
    .CLKOS2_CPHASE    (1),
    .CLKOS2_FPHASE    (0)
) pll_i (
    .RST              (1'b0),
    .STDBY            (1'b0),
    .CLKI             (clkin),
    .CLKOP            (clk_ddr),
    .CLKFB            (clk_ddr),
    .CLKOS            (clk_ddr_90),
    .CLKOS2           (clk_controller),
    .CLKINTFB         (),
    .PHASESEL0        (1'b0),
    .PHASESEL1        (1'b0),
    .PHASEDIR         (1'b1),
    .PHASESTEP        (1'b1),
    .PHASELOADREG     (1'b1),
    .PLLWAKESYNC      (1'b0),
    .ENCLKOP          (1'b0),
    .LOCK             (locked)
);

endmodule

`default_nettype wire
