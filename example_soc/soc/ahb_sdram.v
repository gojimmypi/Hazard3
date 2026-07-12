/*****************************************************************************\
|                       Copyright (C) 2026 gojimmypi                          |
|                     SPDX-License-Identifier: Apache-2.0                     |
\*****************************************************************************/

// AHB-Lite adapter for the ULX3S 16-bit SDR SDRAM controller. A 32-bit AHB
// read is assembled from two 16-bit SDRAM reads. Writes use SDRAM DQM byte
// masks, so byte, halfword and word accesses are supported without a
// read-modify-write cycle.

`default_nettype none

module ahb_sdram #(
    parameter W_ADDR = 32,
    parameter W_DATA = 32,
    parameter CLK_MHZ = 50
) (
    input  wire              clk,
    input  wire              rst_n,

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

    output wire [12:0]       sdram_a,
    output wire [1:0]        sdram_ba,
    inout  wire [15:0]       sdram_d,
    output wire [1:0]        sdram_dqm,
    output wire              sdram_cke,
    output wire              sdram_csn,
    output wire              sdram_rasn,
    output wire              sdram_casn,
    output wire              sdram_wen
);

localparam [2:0]
    ST_IDLE          = 3'd0,
    ST_WRITE_CAPTURE = 3'd1,
    ST_WRITE_REQUEST = 3'd2,
    ST_WRITE_WAIT    = 3'd3,
    ST_READ_REQUEST  = 3'd4,
    ST_READ_WAIT     = 3'd5;

reg [2:0] state;
reg [24:0] operation_addr;
reg [15:0] operation_wdata;
reg [1:0] operation_wmask;
reg [24:0] second_addr;
reg [15:0] second_wdata;
reg [1:0] second_wmask;
reg second_pending;
reg read_second_half;
reg [15:0] read_low_half;
reg [31:0] read_data;
reg [1:0] saved_addr_low;
reg [2:0] saved_hsize;

wire controller_req_valid = state == ST_WRITE_REQUEST ||
    state == ST_READ_REQUEST;
wire controller_req_write = state == ST_WRITE_REQUEST;
wire controller_req_ready;
wire controller_rsp_valid;
wire [15:0] controller_rsp_rdata;
wire controller_init_done;
wire transfer_accept = state == ST_IDLE && ahbls_hready && ahbls_htrans[1];

assign ahbls_hready_resp = state == ST_IDLE;
assign ahbls_hresp = 1'b0;
assign ahbls_hrdata = read_data;

ulx3s_sdram_controller #(
    .CLK_MHZ (CLK_MHZ)
) controller_u (
    .clk         (clk),
    .rst_n       (rst_n),

    .req_valid   (controller_req_valid),
    .req_ready   (controller_req_ready),
    .req_write   (controller_req_write),
    .req_addr    (operation_addr),
    .req_wdata   (operation_wdata),
    .req_wmask   (operation_wmask),
    .rsp_valid   (controller_rsp_valid),
    .rsp_rdata   (controller_rsp_rdata),
    .init_done   (controller_init_done),

    .sdram_a     (sdram_a),
    .sdram_ba    (sdram_ba),
    .sdram_d     (sdram_d),
    .sdram_dqm   (sdram_dqm),
    .sdram_cke   (sdram_cke),
    .sdram_csn   (sdram_csn),
    .sdram_rasn  (sdram_rasn),
    .sdram_casn  (sdram_casn),
    .sdram_wen   (sdram_wen)
);

always @ (posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state <= ST_IDLE;
        operation_addr <= 25'd0;
        operation_wdata <= 16'd0;
        operation_wmask <= 2'b00;
        second_addr <= 25'd0;
        second_wdata <= 16'd0;
        second_wmask <= 2'b00;
        second_pending <= 1'b0;
        read_second_half <= 1'b0;
        read_low_half <= 16'd0;
        read_data <= 32'd0;
        saved_addr_low <= 2'b00;
        saved_hsize <= 3'b000;
    end else begin
        case (state)
        ST_IDLE: begin
            if (transfer_accept) begin
                saved_addr_low <= ahbls_haddr[1:0];
                saved_hsize <= ahbls_hsize;

                if (ahbls_hwrite) begin
                    operation_addr <= ahbls_haddr[25:1];
                    state <= ST_WRITE_CAPTURE;
                end else begin
                    // Always fetch the complete naturally aligned 32-bit word.
                    // The Hazard3 AHB master selects the requested byte or
                    // halfword lane from this returned word.
                    operation_addr <= {ahbls_haddr[25:2], 1'b0};
                    operation_wdata <= 16'd0;
                    operation_wmask <= 2'b00;
                    read_second_half <= 1'b0;
                    state <= ST_READ_REQUEST;
                end
            end
        end

        ST_WRITE_CAPTURE: begin
            case (saved_hsize)
            3'b000: begin
                operation_wdata <= saved_addr_low[1] ?
                    ahbls_hwdata[31:16] : ahbls_hwdata[15:0];
                operation_wmask <= saved_addr_low[0] ? 2'b10 : 2'b01;
                second_pending <= 1'b0;
            end

            3'b001: begin
                operation_wdata <= saved_addr_low[1] ?
                    ahbls_hwdata[31:16] : ahbls_hwdata[15:0];
                operation_wmask <= 2'b11;
                second_pending <= 1'b0;
            end

            default: begin
                operation_addr <= {operation_addr[24:1], 1'b0};
                operation_wdata <= ahbls_hwdata[15:0];
                operation_wmask <= 2'b11;
                second_addr <= {operation_addr[24:1], 1'b0} + 1'b1;
                second_wdata <= ahbls_hwdata[31:16];
                second_wmask <= 2'b11;
                second_pending <= 1'b1;
            end
            endcase

            state <= ST_WRITE_REQUEST;
        end

        ST_WRITE_REQUEST: begin
            if (controller_req_ready) begin
                state <= ST_WRITE_WAIT;
            end
        end

        ST_WRITE_WAIT: begin
            if (controller_rsp_valid) begin
                if (second_pending) begin
                    operation_addr <= second_addr;
                    operation_wdata <= second_wdata;
                    operation_wmask <= second_wmask;
                    second_pending <= 1'b0;
                    state <= ST_WRITE_REQUEST;
                end else begin
                    state <= ST_IDLE;
                end
            end
        end

        ST_READ_REQUEST: begin
            if (controller_req_ready) begin
                state <= ST_READ_WAIT;
            end
        end

        ST_READ_WAIT: begin
            if (controller_rsp_valid) begin
                if (!read_second_half) begin
                    read_low_half <= controller_rsp_rdata;
                    operation_addr <= operation_addr + 1'b1;
                    read_second_half <= 1'b1;
                    state <= ST_READ_REQUEST;
                end else begin
                    read_data <= {controller_rsp_rdata, read_low_half};
                    state <= ST_IDLE;
                end
            end
        end

        default: state <= ST_IDLE;
        endcase
    end
end

// These AHB attributes are intentionally unused by this first-stage,
// single-beat diagnostic controller.
wire unused = &{1'b0, ahbls_hburst, ahbls_hprot, ahbls_hmastlock,
    controller_init_done};

endmodule
