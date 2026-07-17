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

	output wire [3:0]  gpdi_dp,

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

// Keep the proven Hazard3/SDRAM clock tree unchanged. HDMI uses a second PLL,
// so initial video bring-up cannot disturb CPU, JTAG, UART or SDRAM timing.
wire clk_video_pix;
wire clk_tmds_x5;
wire pll_video_locked;
wire rst_n_video_pix;
wire rst_n_tmds_x5;

pll_25_50_250 pll_video (
	.clkin        (clk_osc),
	.clk_pix      (clk_video_pix),
	.clk_tmds_x5  (clk_tmds_x5),
	.locked       (pll_video_locked)
);

fpga_reset #(
	.SHIFT (3)
) rstgen_video_pix (
	.clk         (clk_video_pix),
	.force_rst_n (pll_video_locked),
	.rst_n       (rst_n_video_pix)
);

fpga_reset #(
	.SHIFT (3)
) rstgen_tmds (
	.clk         (clk_tmds_x5),
	.force_rst_n (pll_video_locked),
	.rst_n       (rst_n_tmds_x5)
);

`ifdef 0
ulx3s_hdmi_test_pattern hdmi_test_pattern_u (
	.clk_pix       (clk_video_pix),
	.rst_n_pix     (rst_n_video_pix),
	.clk_tmds_x5   (clk_tmds_x5),
	.rst_n_tmds_x5 (rst_n_tmds_x5),
	.gpdi_dp       (gpdi_dp)
);
`endif

wire        video_sdram_req_valid;
wire        video_sdram_req_ready;
wire [24:0] video_sdram_req_addr;
wire        video_sdram_rsp_valid;
wire [15:0] video_sdram_rsp_rdata;
wire        video_sdram_init_done;

wire        video_apb_psel;
wire        video_apb_penable;
wire        video_apb_pwrite;
wire [15:0] video_apb_paddr;
wire [31:0] video_apb_pwdata;
reg  [31:0] video_apb_prdata;
wire [31:0] video_apb_prdata_framebuffer;
wire        video_apb_pready;
wire        video_apb_pslverr;

// The shared SoC exposes both the ULX3S SDR SDRAM and ULX4M-LD LiteDRAM ports.
// This wrapper explicitly disables LiteDRAM and terminates every unused DDR3
// port so the ULX3S build never relies on parameter defaults or open inputs.
wire [14:0] unused_ddram_a;
wire [2:0]  unused_ddram_ba;
wire        unused_ddram_cas_n;
wire        unused_ddram_cke;
wire        unused_ddram_clk_n;
wire        unused_ddram_clk_p;
wire        unused_ddram_cs_n;
wire [1:0]  unused_ddram_dm;
wire [15:0] unused_ddram_dq;
wire [1:0]  unused_ddram_dqs_n;
wire [1:0]  unused_ddram_dqs_p;
wire        unused_ddram_odt;
wire        unused_ddram_ras_n;
wire        unused_ddram_reset_n;
wire        unused_ddram_we_n;
wire        unused_ddr3_calib_complete;
wire [31:0] unused_ddr3_debug_status;

// Runtime IDs use the same APB slots as ULX4M-LD so one monitor firmware can
// verify either board without compile-time board selection.
localparam [31:0] FPGA_BUILD_ID          = 32'h554c5035; // ASCII "ULP5"
localparam [31:0] MEMORY_CORE_BUILD_ID   = 32'h53445235; // ASCII "SDR5"
localparam [31:0] MEMORY_ADAPTER_BUILD_ID = 32'h41485335; // ASCII "AHS5"
wire [31:0] memory_status = {
    16'h5344,                 // ASCII "SD"
    11'd0,
    video_sdram_init_done,    // ready
    rst_n_sys,                // user clock/reset ready
    pll_sys_locked,
    1'b0,                     // no initialization error
    video_sdram_init_done
};

always @(*) begin
    case (video_apb_paddr[5:2])
    4'h7: video_apb_prdata = FPGA_BUILD_ID;
    4'h8: video_apb_prdata = memory_status;
    4'h9: video_apb_prdata = MEMORY_CORE_BUILD_ID;
    4'ha: video_apb_prdata = MEMORY_ADAPTER_BUILD_ID;
    default: video_apb_prdata = video_apb_prdata_framebuffer;
    endcase
end

ulx3s_hdmi_framebuffer hdmi_framebuffer_u (
	.clk_sys          (clk_sys),
	.rst_n_sys        (rst_n_sys),
	.clk_pix          (clk_video_pix),
	.rst_n_pix        (rst_n_video_pix),
	.clk_tmds_x5      (clk_tmds_x5),
	.rst_n_tmds_x5    (rst_n_tmds_x5),

	.sdram_req_valid  (video_sdram_req_valid),
	.sdram_req_ready  (video_sdram_req_ready),
	.sdram_req_addr   (video_sdram_req_addr),
	.sdram_rsp_valid  (video_sdram_rsp_valid),
	.sdram_rsp_rdata  (video_sdram_rsp_rdata),
	.sdram_init_done  (video_sdram_init_done),

	.apbs_psel        (video_apb_psel),
	.apbs_penable     (video_apb_penable),
	.apbs_pwrite      (video_apb_pwrite),
	.apbs_paddr       (video_apb_paddr),
	.apbs_pwdata      (video_apb_pwdata),
	.apbs_prdata      (video_apb_prdata_framebuffer),
	.apbs_pready      (video_apb_pready),
	.apbs_pslverr     (video_apb_pslverr),

	.gpdi_dp          (gpdi_dp)
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
	.LITEDRAM_ENABLE    (0),
	.SDRAM_COL_WIDTH    (10),

	.EXTENSION_M         (1),
	.EXTENSION_A         (0),
	.EXTENSION_C         (1),
	.EXTENSION_ZBA       (1),
	.EXTENSION_ZBB       (1),
	.EXTENSION_ZBC       (0),
	.EXTENSION_ZBS       (1),
	.EXTENSION_ZBKB      (0),
	.EXTENSION_ZIFENCEI  (1),
	.EXTENSION_XH3BEXTM  (0),
	.EXTENSION_XH3PMPM   (0),
	.EXTENSION_XH3POWER  (0),
	.CSR_COUNTER         (1),
	.MUL_FAST            (1),
	.MUL_FASTER          (1),
	.MULH_FAST           (1),
	.MULDIV_UNROLL       (4),
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
	.sdram_wen  (sdram_wen),

	.litedram_ref_clk    (1'b0),
	.ddram_a             (unused_ddram_a),
	.ddram_ba            (unused_ddram_ba),
	.ddram_cas_n         (unused_ddram_cas_n),
	.ddram_cke           (unused_ddram_cke),
	.ddram_clk_n         (unused_ddram_clk_n),
	.ddram_clk_p         (unused_ddram_clk_p),
	.ddram_cs_n          (unused_ddram_cs_n),
	.ddram_dm            (unused_ddram_dm),
	.ddram_dq            (unused_ddram_dq),
	.ddram_dqs_n         (unused_ddram_dqs_n),
	.ddram_dqs_p         (unused_ddram_dqs_p),
	.ddram_odt           (unused_ddram_odt),
	.ddram_ras_n         (unused_ddram_ras_n),
	.ddram_reset_n       (unused_ddram_reset_n),
	.ddram_we_n          (unused_ddram_we_n),
	.ddr3_calib_complete (unused_ddr3_calib_complete),
	.ddr3_debug_status   (unused_ddr3_debug_status),

	.video_sdram_req_valid (video_sdram_req_valid),
	.video_sdram_req_ready (video_sdram_req_ready),
	.video_sdram_req_addr  (video_sdram_req_addr),
	.video_sdram_rsp_valid (video_sdram_rsp_valid),
	.video_sdram_rsp_rdata (video_sdram_rsp_rdata),
	.video_sdram_init_done (video_sdram_init_done),

	.video_apb_psel        (video_apb_psel),
	.video_apb_penable     (video_apb_penable),
	.video_apb_pwrite      (video_apb_pwrite),
	.video_apb_paddr       (video_apb_paddr),
	.video_apb_pwdata      (video_apb_pwdata),
	.video_apb_prdata      (video_apb_prdata),
	.video_apb_pready      (video_apb_pready),
	.video_apb_pslverr     (video_apb_pslverr)
);

endmodule
