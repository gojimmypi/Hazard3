/*****************************************************************************\
|                        Copyright (C) 2021 Luke Wren                         |
|                     SPDX-License-Identifier: Apache-2.0                     |
\*****************************************************************************/

`default_nettype none

module fpga_ulx3s (
	input  wire       clk_osc,
	output wire [7:0] led,

	output wire       uart_tx,
	input  wire       uart_rx,

	output wire [12:0] sdram_a,
	output wire [1:0]  sdram_ba,
	inout  wire [15:0] sdram_d,
	output wire [1:0]  sdram_dqm,
	output wire        sdram_clk,
	output wire        sdram_cke,
	output wire        sdram_csn,
	output wire        sdram_rasn,
	output wire        sdram_casn,
	output wire        sdram_wen
);

wire clk_sys;
wire pll_sys_locked;
wire rst_n_sys;

pll_25_50 pll_sys (
	.clkin   (clk_osc),
	.clkout0 (clk_sys),
	.locked  (pll_sys_locked)
);

fpga_reset #(
	.SHIFT (3)
) rstgen (
	.clk         (clk_sys),
	.force_rst_n (pll_sys_locked),
	.rst_n       (rst_n_sys)
);

// Forward an inverted copy of the 50 MHz system clock. Commands and data are
// launched on clk_sys rising edges and reach the SDRAM half a cycle before
// its rising clock edge.
ddr_out sdram_clock_u (
	.clk     (clk_sys),
	.rst_n   (rst_n_sys),
	.d_rise  (1'b0),
	.d_fall  (1'b1),
	.e       (1'b1),
	.q       (sdram_clk)
);

example_soc #(
	.DTM_TYPE           ("ECP5"),
	.SRAM_DEPTH         (1 << 15),
	.CLK_MHZ            (50),
	.SDRAM_ENABLE       (1),

	.EXTENSION_M         (1),
	.EXTENSION_A         (1),
	.EXTENSION_C         (0),
	.EXTENSION_ZBA       (0),
	.EXTENSION_ZBB       (0),
	.EXTENSION_ZBC       (0),
	.EXTENSION_ZBS       (0),
	.EXTENSION_ZBKB      (0),
	.EXTENSION_ZIFENCEI  (1),
	.EXTENSION_XH3BEXTM  (0),
	.EXTENSION_XH3PMPM   (0),
	.EXTENSION_XH3POWER  (0),
	.CSR_COUNTER         (1),
	.MUL_FAST            (1),
	.MUL_FASTER          (0),
	.MULH_FAST           (0),
	.MULDIV_UNROLL       (1),
	.FAST_BRANCHCMP      (1),
	.BRANCH_PREDICTOR    (1)
) soc_u (
	.clk     (clk_sys),
	.rst_n   (rst_n_sys),

	// JTAG connections provided internally by ECP5 JTAGG primitive
	.tck     (1'b0),
	.trst_n  (1'b0),
	.tms     (1'b0),
	.tdi     (1'b0),
	.tdo     (/* unused */),

	.uart_tx (uart_tx),
	.uart_rx (uart_rx),

    .gpio_out (led),

	.sdram_a    (sdram_a),
	.sdram_ba   (sdram_ba),
	.sdram_d    (sdram_d),
	.sdram_dqm  (sdram_dqm),
	.sdram_cke  (sdram_cke),
	.sdram_csn  (sdram_csn),
	.sdram_rasn (sdram_rasn),
	.sdram_casn (sdram_casn),
	.sdram_wen  (sdram_wen)
);

endmodule
