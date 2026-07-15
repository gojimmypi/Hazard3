/*****************************************************************************\
|                        Copyright (C) 2026 gojimmypi                        |
|                         SPDX-License-Identifier: MIT                       |
\*****************************************************************************/

`default_nettype none

// Generate the clocks required by the low-frequency native-Verilog ULX4M-LD
// DDR3 target.
//
// The controller and Hazard3 system clock run at 25 MHz. The two 100 MHz
// outputs drive the fixed 4:1 ECP5 DDR3 PHY; the second 100 MHz output is phase
// shifted by 90 degrees. This keeps DLL_OFF operation below UberDDR3's
// documented 125 MHz limit.
//
// Divider calculation:
//
//     PFD = 25 MHz / 1
//     primary output = PFD * 4 = 100 MHz
//     VCO = 100 MHz * 6 = 600 MHz
//     controller output = 600 MHz / 24 = 25 MHz
//
// For a divide-by-six 100 MHz output, a 90-degree shift is 1.5 VCO cycles:
// one whole CPHASE step plus four eighth-cycle FPHASE steps.
module pll_25_25_100_90 (
    input  wire clkin,
    output wire clk_controller,
    output wire clk_ddr,
    output wire clk_ddr_90,
    output wire locked
);

(* FREQUENCY_PIN_CLKI="25" *)
(* FREQUENCY_PIN_CLKOP="100" *)
(* FREQUENCY_PIN_CLKOS="100" *)
(* FREQUENCY_PIN_CLKOS2="25" *)
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
    .CLKFB_DIV        (4),
    .FEEDBK_PATH      ("CLKOP"),

    .CLKOP_ENABLE     ("ENABLED"),
    .CLKOP_DIV        (6),
    .CLKOP_CPHASE     (2),
    .CLKOP_FPHASE     (0),

    .CLKOS_ENABLE     ("ENABLED"),
    .CLKOS_DIV        (6),
    .CLKOS_CPHASE     (3),
    .CLKOS_FPHASE     (4),

    .CLKOS2_ENABLE    ("ENABLED"),
    .CLKOS2_DIV       (24),
    .CLKOS2_CPHASE    (2),
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
