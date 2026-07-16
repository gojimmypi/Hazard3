/*****************************************************************************\
|                        Copyright (C) 2026 gojimmypi                        |
|                         SPDX-License-Identifier: MIT                       |
\*****************************************************************************/

// AHB-Lite and video adapter for the native-Verilog UberDDR3 controller.
//
// UberDDR3 exposes one 128-bit Wishbone transfer for each DDR3 BL8 burst on a
// 16-bit memory. The adapter maps the existing 64 MiB Hazard3 SDRAM window to
// the low 64 MiB of the ULX4M-LD DDR3 and selects the requested 32-bit AHB word
// or 16-bit video halfword from each 128-bit burst.

`default_nettype none

module ahb_uberddr3 #(
    parameter W_ADDR = 32,
    parameter W_DATA = 32
) (
    input  wire              clk,
    input  wire              rst_n,
    input  wire              ddr3_clk,
    input  wire              ddr3_clk_90,

    output wire              ahbls_hready_resp,
    input  wire              ahbls_hready,
    output wire              ahbls_hresp,
    input  wire [W_ADDR-1:0] ahbls_haddr,
    input  wire              ahbls_hwrite,
    input  wire [1:0]        ahbls_htrans,
    input  wire [2:0]        ahbls_hsize,
    input  wire [2:0]        ahbls_hburst,
    input  wire [3:0]        ahbls_hprot,
    input  wire              ahbls_hmastlock,
    input  wire [W_DATA-1:0] ahbls_hwdata,
    output wire [W_DATA-1:0] ahbls_hrdata,

    input  wire              video_req_valid,
    output wire              video_req_ready,
    input  wire [24:0]       video_req_addr,
    output reg               video_rsp_valid,
    output reg  [15:0]       video_rsp_rdata,
    output wire              video_init_done,

    output wire [14:0]       ddram_a,
    output wire [2:0]        ddram_ba,
    output wire              ddram_cas_n,
    output wire              ddram_cke,
    output wire              ddram_clk_n,
    output wire              ddram_clk_p,
    output wire              ddram_cs_n,
    output wire [1:0]        ddram_dm,
    inout  wire [15:0]       ddram_dq,
    inout  wire [1:0]        ddram_dqs_n,
    inout  wire [1:0]        ddram_dqs_p,
    output wire              ddram_odt,
    output wire              ddram_ras_n,
    output wire              ddram_reset_n,
    output wire              ddram_we_n,

    output wire              calib_complete,
    output wire [31:0]       debug_status
);

localparam [2:0]
    ST_IDLE          = 3'd0,
    ST_WRITE_CAPTURE = 3'd1,
    ST_WB_REQUEST    = 3'd2,
    ST_WB_WAIT       = 3'd3;

reg [2:0] state;
reg       request_owner_video;
reg       request_write;
reg [25:0] request_line_addr;
reg [1:0] request_word_index;
reg [2:0] request_halfword_index;
reg [3:0] request_byte_offset;
reg [2:0] request_hsize;
reg [127:0] request_wdata;
reg [15:0] request_sel;
reg [31:0] read_data;
reg last_grant_video;
reg rmw_active;

wire ahb_request_present = ahbls_htrans[1];

// Alternate grants when the CPU and framebuffer request memory together. If
// only one client is requesting, grant that client immediately.
wire grant_video = state == ST_IDLE && calib_complete && video_req_valid &&
    (!ahb_request_present || !last_grant_video);
wire accept_ahb = state == ST_IDLE && calib_complete && ahbls_hready &&
    ahb_request_present && !grant_video;
wire accept_video = grant_video;

assign ahbls_hready_resp = state == ST_IDLE && calib_complete && !grant_video;
assign ahbls_hresp = 1'b0;
assign ahbls_hrdata = read_data;

assign video_req_ready = accept_video;
assign video_init_done = calib_complete;

wire wb_stall;
wire wb_ack;
wire wb_err;
wire [127:0] wb_rdata;
wire [3:0] wb_aux_out;
wire controller_uart_tx;
wire [1:0] controller_ddram_dm;

// Expand the saved byte-select bits into a 128-bit merge mask. ULX4M places
// both physical DM pins outside their corresponding DQS groups, so all CPU
// stores are converted to full-burst writes and the physical DM pins stay low.
wire [127:0] request_byte_mask = {
    {8{request_sel[15]}}, {8{request_sel[14]}},
    {8{request_sel[13]}}, {8{request_sel[12]}},
    {8{request_sel[11]}}, {8{request_sel[10]}},
    {8{request_sel[9]}},  {8{request_sel[8]}},
    {8{request_sel[7]}},  {8{request_sel[6]}},
    {8{request_sel[5]}},  {8{request_sel[4]}},
    {8{request_sel[3]}},  {8{request_sel[2]}},
    {8{request_sel[1]}},  {8{request_sel[0]}}
};

wire wb_request_active = state == ST_WB_REQUEST;

// MT41K256M16 geometry is 15 row bits, 10 column bits and 3 bank bits.
// UberDDR3 removes the three BL8 beat-address bits, yielding a 25-bit burst
// address. Only the low 22 burst-address bits are used here, preserving the
// existing 64 MiB Hazard3 memory map and its 0x24000000 diagnostic alias.
//
// The ECP5 PHY is a fixed 4:1 interface. Run the controller at 25 MHz and DDR3
// at 100 MHz so DLL_OFF remains within UberDDR3's documented <125 MHz mode.
ddr3_top #(
    .CONTROLLER_CLK_PERIOD (40_000),
    .DDR3_CLK_PERIOD       (10_000),
    .ROW_BITS              (15),
    .COL_BITS              (10),
    .BA_BITS               (3),
    .BYTE_LANES            (2),
    .AUX_WIDTH             (4),
    .WB2_ADDR_BITS         (7),
    .WB2_DATA_BITS         (32),
    .DUAL_RANK_DIMM        (0),
    .SPEED_BIN             (0),
    .SDRAM_CAPACITY        (4),
    .TRCD                  (13_750),
    .TRP                   (13_750),
    .TRAS                  (35_000),
    .MICRON_SIM            (0),
    .ODELAY_SUPPORTED      (0),
    .SECOND_WISHBONE       (0),
    .DLL_OFF               (1),
    .WB_ERROR              (0),
    .BIST_MODE             (0),
    .BIST_TEST_DATAMASK    (0),
    .ECC_ENABLE            (0),
    .DIC                   (2'b00),
    .RTT_NOM               (3'b011),
    .SELF_REFRESH          (2'b00)
) ddr3_controller_u (
    .i_controller_clk      (clk),
    .i_ddr3_clk            (ddr3_clk),
    .i_ref_clk             (1'b0),
    .i_ddr3_clk_90         (ddr3_clk_90),
    .i_rst_n               (rst_n),

    .i_wb_cyc              (1'b1),
    .i_wb_stb              (wb_request_active),
    .i_wb_we               (request_write),
    .i_wb_addr             (request_line_addr),
    .i_wb_data             (request_wdata),
    .i_wb_sel              (request_sel),
    .i_aux                 (4'd0),
    .o_wb_stall            (wb_stall),
    .o_wb_ack              (wb_ack),
    .o_wb_err              (wb_err),
    .o_wb_data             (wb_rdata),
    .o_aux                 (wb_aux_out),

    .i_wb2_cyc             (1'b0),
    .i_wb2_stb             (1'b0),
    .i_wb2_we              (1'b0),
    .i_wb2_addr            (7'd0),
    .i_wb2_data            (32'd0),
    .i_wb2_sel             (4'd0),
    .o_wb2_stall           (),
    .o_wb2_ack             (),
    .o_wb2_data            (),

    .o_ddr3_clk_p          (ddram_clk_p),
    .o_ddr3_clk_n          (ddram_clk_n),
    .o_ddr3_reset_n        (ddram_reset_n),
    .o_ddr3_cke            (ddram_cke),
    .o_ddr3_cs_n           (ddram_cs_n),
    .o_ddr3_ras_n          (ddram_ras_n),
    .o_ddr3_cas_n          (ddram_cas_n),
    .o_ddr3_we_n           (ddram_we_n),
    .o_ddr3_addr           (ddram_a),
    .o_ddr3_ba_addr        (ddram_ba),
    .io_ddr3_dq            (ddram_dq),
    .io_ddr3_dqs           (ddram_dqs_p),
    .io_ddr3_dqs_n         (ddram_dqs_n),
    .o_ddr3_dm             (controller_ddram_dm),
    .o_ddr3_odt            (ddram_odt),

    .o_calib_complete      (calib_complete),
    .o_debug1              (debug_status),
    .i_user_self_refresh   (1'b0),
    .uart_tx               (controller_uart_tx)
);

// The ULX4M PCB does not place DM0/DM1 in their byte lanes' DQS groups.
// Holding DM low makes every DDR3 write an unmasked full-burst write.
assign ddram_dm = 2'b00;

always @ (posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state <= ST_IDLE;
        request_owner_video <= 1'b0;
        request_write <= 1'b0;
        request_line_addr <= 26'd0;
        request_word_index <= 2'd0;
        request_halfword_index <= 3'd0;
        request_byte_offset <= 4'd0;
        request_hsize <= 3'd0;
        request_wdata <= 128'd0;
        request_sel <= 16'd0;
        read_data <= 32'd0;
        video_rsp_valid <= 1'b0;
        video_rsp_rdata <= 16'd0;
        last_grant_video <= 1'b1;
        rmw_active <= 1'b0;
    end else begin
        video_rsp_valid <= 1'b0;

        case (state)
        ST_IDLE: begin
            if (accept_video) begin
                request_owner_video <= 1'b1;
                request_write <= 1'b0;
                request_line_addr <= {4'b0000, video_req_addr[24:3]};
                request_halfword_index <= video_req_addr[2:0];
                request_wdata <= 128'd0;
                request_sel <= 16'd0;
                last_grant_video <= 1'b1;
                rmw_active <= 1'b0;
                state <= ST_WB_REQUEST;
            end else if (accept_ahb) begin
                request_owner_video <= 1'b0;
                request_write <= ahbls_hwrite;
                request_line_addr <= {4'b0000, ahbls_haddr[25:4]};
                request_word_index <= ahbls_haddr[3:2];
                request_byte_offset <= ahbls_haddr[3:0];
                request_hsize <= ahbls_hsize;
                request_wdata <= 128'd0;
                request_sel <= 16'd0;
                last_grant_video <= 1'b0;
                rmw_active <= 1'b0;

                if (ahbls_hwrite) begin
                    state <= ST_WRITE_CAPTURE;
                end else begin
                    state <= ST_WB_REQUEST;
                end
            end
        end

        ST_WRITE_CAPTURE: begin
            // AHB write data follows the accepted address/control phase by one
            // cycle. Position the complete 32-bit bus word in its DDR3 burst
            // lane, then use byte selects for byte, halfword or word writes.
            case (request_word_index)
            2'd0: request_wdata <= {96'd0, ahbls_hwdata};
            2'd1: request_wdata <= {64'd0, ahbls_hwdata, 32'd0};
            2'd2: request_wdata <= {32'd0, ahbls_hwdata, 64'd0};
            default: request_wdata <= {ahbls_hwdata, 96'd0};
            endcase

            case (request_hsize)
            3'b000: request_sel <= 16'h0001 << request_byte_offset;
            3'b001: request_sel <= 16'h0003 <<
                {request_byte_offset[3:1], 1'b0};
            default: request_sel <= 16'h000f <<
                {request_byte_offset[3:2], 2'b00};
            endcase

            // Read the complete 128-bit burst first. Once it returns, merge the
            // selected AHB bytes and issue a second, fully unmasked DDR3 write.
            request_write <= 1'b0;
            rmw_active <= 1'b1;
            state <= ST_WB_REQUEST;
        end

        ST_WB_REQUEST: begin
            if (!wb_stall) begin
                state <= ST_WB_WAIT;
            end
        end

        ST_WB_WAIT: begin
            if (wb_ack) begin
                if (rmw_active && !request_write) begin
                    request_wdata <=
                        (wb_rdata & ~request_byte_mask) |
                        (request_wdata & request_byte_mask);
                    request_sel <= 16'hffff;
                    request_write <= 1'b1;
                    state <= ST_WB_REQUEST;
                end else begin
                    if (request_owner_video) begin
                        case (request_halfword_index)
                        3'd0: video_rsp_rdata <= wb_rdata[15:0];
                        3'd1: video_rsp_rdata <= wb_rdata[31:16];
                        3'd2: video_rsp_rdata <= wb_rdata[47:32];
                        3'd3: video_rsp_rdata <= wb_rdata[63:48];
                        3'd4: video_rsp_rdata <= wb_rdata[79:64];
                        3'd5: video_rsp_rdata <= wb_rdata[95:80];
                        3'd6: video_rsp_rdata <= wb_rdata[111:96];
                        default: video_rsp_rdata <= wb_rdata[127:112];
                        endcase
                        video_rsp_valid <= 1'b1;
                    end else if (!request_write) begin
                        case (request_word_index)
                        2'd0: read_data <= wb_rdata[31:0];
                        2'd1: read_data <= wb_rdata[63:32];
                        2'd2: read_data <= wb_rdata[95:64];
                        default: read_data <= wb_rdata[127:96];
                        endcase
                    end
                    rmw_active <= 1'b0;
                    state <= ST_IDLE;
                end
            end
        end

        default: state <= ST_IDLE;
        endcase
    end
end

// The cache presents one AHB beat at a time to this adapter. Burst attributes
// are informational because each beat is converted independently.
wire unused = &{1'b0, ahbls_hburst, ahbls_hprot, ahbls_hmastlock,
    wb_err, wb_aux_out, controller_uart_tx, controller_ddram_dm};

endmodule

`default_nettype wire
