/*****************************************************************************\
|                        Copyright (C) 2026 gojimmypi                        |
|                         SPDX-License-Identifier: MIT                       |
\*****************************************************************************/

`default_nettype none

// Generate a dedicated 50 MHz video pixel clock and 250 MHz DDR TMDS
// serializer clock from the ULX3S 25 MHz oscillator. The divider values match
// the working 1024x600 ULX3S HDMI experiment derived from Bruno Levy's
// learn-fpga example.
module pll_25_50_250 (
	input  wire clkin,
	output wire clk_pix,
	output wire clk_tmds_x5,
	output wire locked
);

(* FREQUENCY_PIN_CLKI="25" *)
(* FREQUENCY_PIN_CLKOP="250" *)
(* FREQUENCY_PIN_CLKOS="50" *)
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
	.CLKFB_DIV        (10),
	.FEEDBK_PATH      ("CLKOP"),

	.CLKOP_ENABLE     ("ENABLED"),
	.CLKOP_DIV        (2),
	.CLKOP_CPHASE     (1),
	.CLKOP_FPHASE     (0),

	.CLKOS_ENABLE     ("ENABLED"),
	.CLKOS_DIV        (10),
	.CLKOS_CPHASE     (1),
	.CLKOS_FPHASE     (0)
) pll_i (
	.RST              (1'b0),
	.STDBY            (1'b0),
	.CLKI             (clkin),
	.CLKOP            (clk_tmds_x5),
	.CLKFB            (clk_tmds_x5),
	.CLKOS            (clk_pix),
	.CLKINTFB         (),
	.PHASESEL0        (1'b0),
	.PHASESEL1        (1'b0),
	.PHASEDIR         (1'b1),
	.PHASESTEP        (1'b1),
	.PHASELOADREG     (1'b1),
	.PLLWAKESYNC      (1'b0),
	.ENCLKOP          (1'b1),
	.LOCK             (locked)
);

endmodule

`default_nettype wire
