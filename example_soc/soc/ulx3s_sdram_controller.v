/*****************************************************************************\
|                       Copyright (C) 2026 gojimmypi                          |
|                     SPDX-License-Identifier: Apache-2.0                     |
\*****************************************************************************/

// Conservative single-access SDR SDRAM controller for the 16-bit SDRAM on
// ULX3S. The controller runs from the 50 MHz system clock. The SDRAM clock is
// generated at the board top level with a half-cycle phase offset so commands
// launched on clk have setup time before the SDRAM rising clock edge.
//
// All accesses use burst length 1 and auto-precharge. This is intentionally a
// bring-up controller: it prioritizes simple, observable behavior over peak
// bandwidth. It supports one outstanding 16-bit request and performs periodic
// refresh automatically.

`default_nettype none

module ulx3s_sdram_controller #(
    parameter CLK_MHZ = 50,
    parameter ROW_WIDTH = 13,
    parameter COL_WIDTH = 10,
    parameter BANK_WIDTH = 2,
    parameter STARTUP_US = 200,
    parameter REFRESH_INTERVAL_US = 7
) (
    input  wire                         clk,
    input  wire                         rst_n,

    input  wire                         req_valid,
    output wire                         req_ready,
    input  wire                         req_write,
    input  wire [BANK_WIDTH+ROW_WIDTH+COL_WIDTH-1:0] req_addr,
    input  wire [15:0]                  req_wdata,
    input  wire [1:0]                   req_wmask,
    output reg                          rsp_valid,
    output reg  [15:0]                  rsp_rdata,
    output reg                          init_done,

    output reg  [ROW_WIDTH-1:0]         sdram_a,
    output reg  [BANK_WIDTH-1:0]        sdram_ba,
    inout  wire [15:0]                  sdram_d,
    output reg  [1:0]                   sdram_dqm,
    output wire                         sdram_cke,
    output reg                          sdram_csn,
    output reg                          sdram_rasn,
    output reg                          sdram_casn,
    output reg                          sdram_wen
);

localparam HADDR_WIDTH = BANK_WIDTH + ROW_WIDTH + COL_WIDTH;
localparam integer STARTUP_CYCLES = CLK_MHZ * STARTUP_US;
localparam integer REFRESH_CYCLES = CLK_MHZ * REFRESH_INTERVAL_US;

localparam [5:0]
    ST_INIT_WAIT          = 6'd0,
    ST_INIT_PRECHARGE     = 6'd1,
    ST_INIT_TRP_1         = 6'd2,
    ST_INIT_TRP_2         = 6'd3,
    ST_INIT_REFRESH_1     = 6'd4,
    ST_INIT_TRFC1_1       = 6'd5,
    ST_INIT_TRFC1_2       = 6'd6,
    ST_INIT_TRFC1_3       = 6'd7,
    ST_INIT_TRFC1_4       = 6'd8,
    ST_INIT_REFRESH_2     = 6'd9,
    ST_INIT_TRFC2_1       = 6'd10,
    ST_INIT_TRFC2_2       = 6'd11,
    ST_INIT_TRFC2_3       = 6'd12,
    ST_INIT_TRFC2_4       = 6'd13,
    ST_INIT_MODE          = 6'd14,
    ST_INIT_TMRD_1        = 6'd15,
    ST_INIT_TMRD_2        = 6'd16,
    ST_IDLE               = 6'd17,
    ST_ACTIVATE           = 6'd18,
    ST_TRCD               = 6'd19,
    ST_READ_COMMAND       = 6'd20,
    ST_READ_WAIT_1        = 6'd21,
    ST_READ_WAIT_2        = 6'd22,
    ST_READ_RECOVERY      = 6'd23,
    ST_WRITE_COMMAND      = 6'd24,
    ST_WRITE_RECOVERY_1   = 6'd25,
    ST_WRITE_RECOVERY_2   = 6'd26,
    ST_WRITE_RECOVERY_3   = 6'd27,
    ST_REFRESH_PRECHARGE  = 6'd28,
    ST_REFRESH_TRP_1      = 6'd29,
    ST_REFRESH_TRP_2      = 6'd30,
    ST_REFRESH_COMMAND    = 6'd31,
    ST_REFRESH_TRFC_1     = 6'd32,
    ST_REFRESH_TRFC_2     = 6'd33,
    ST_REFRESH_TRFC_3     = 6'd34,
    ST_REFRESH_TRFC_4     = 6'd35;

reg [5:0] state;
reg [31:0] startup_counter;
reg [15:0] refresh_counter;
reg [HADDR_WIDTH-1:0] request_addr;
reg request_write;
reg [15:0] request_wdata;
reg [1:0] request_wmask;
reg dq_output_enable;
reg [15:0] dq_output;

wire refresh_due = refresh_counter >= REFRESH_CYCLES - 1;
wire request_accept = req_valid && req_ready;

assign req_ready = init_done && state == ST_IDLE && !refresh_due;
assign sdram_cke = 1'b1;
assign sdram_d = dq_output_enable ? dq_output : 16'hzzzz;

always @ (posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state <= ST_INIT_WAIT;
        startup_counter <= 32'd0;
        refresh_counter <= 16'd0;
        request_addr <= {HADDR_WIDTH{1'b0}};
        request_write <= 1'b0;
        request_wdata <= 16'd0;
        request_wmask <= 2'b00;
        rsp_valid <= 1'b0;
        rsp_rdata <= 16'd0;
        init_done <= 1'b0;
    end else begin
        rsp_valid <= 1'b0;

        if (init_done) begin
            if (state == ST_REFRESH_COMMAND) begin
                refresh_counter <= 16'd0;
            end else if (refresh_counter < REFRESH_CYCLES - 1) begin
                refresh_counter <= refresh_counter + 1'b1;
            end
        end else begin
            refresh_counter <= 16'd0;
        end

        case (state)
        ST_INIT_WAIT: begin
            if (startup_counter >= STARTUP_CYCLES - 1) begin
                state <= ST_INIT_PRECHARGE;
            end else begin
                startup_counter <= startup_counter + 1'b1;
            end
        end

        ST_INIT_PRECHARGE: state <= ST_INIT_TRP_1;
        ST_INIT_TRP_1: state <= ST_INIT_TRP_2;
        ST_INIT_TRP_2: state <= ST_INIT_REFRESH_1;
        ST_INIT_REFRESH_1: state <= ST_INIT_TRFC1_1;
        ST_INIT_TRFC1_1: state <= ST_INIT_TRFC1_2;
        ST_INIT_TRFC1_2: state <= ST_INIT_TRFC1_3;
        ST_INIT_TRFC1_3: state <= ST_INIT_TRFC1_4;
        ST_INIT_TRFC1_4: state <= ST_INIT_REFRESH_2;
        ST_INIT_REFRESH_2: state <= ST_INIT_TRFC2_1;
        ST_INIT_TRFC2_1: state <= ST_INIT_TRFC2_2;
        ST_INIT_TRFC2_2: state <= ST_INIT_TRFC2_3;
        ST_INIT_TRFC2_3: state <= ST_INIT_TRFC2_4;
        ST_INIT_TRFC2_4: state <= ST_INIT_MODE;
        ST_INIT_MODE: state <= ST_INIT_TMRD_1;
        ST_INIT_TMRD_1: state <= ST_INIT_TMRD_2;
        ST_INIT_TMRD_2: begin
            init_done <= 1'b1;
            state <= ST_IDLE;
        end

        ST_IDLE: begin
            if (refresh_due) begin
                state <= ST_REFRESH_PRECHARGE;
            end else if (request_accept) begin
                request_addr <= req_addr;
                request_write <= req_write;
                request_wdata <= req_wdata;
                request_wmask <= req_wmask;
                state <= ST_ACTIVATE;
            end
        end

        ST_ACTIVATE: state <= ST_TRCD;

        ST_TRCD: begin
            if (request_write) begin
                state <= ST_WRITE_COMMAND;
            end else begin
                state <= ST_READ_COMMAND;
            end
        end

        ST_READ_COMMAND: state <= ST_READ_WAIT_1;
        ST_READ_WAIT_1: state <= ST_READ_WAIT_2;

        // CAS latency is two SDRAM clock cycles. The SDRAM rising clock edge
        // occurs on the falling edge of clk, so sampling here on the following
        // rising edge of clk places the sample in the middle of the data eye.
        ST_READ_WAIT_2: begin
            rsp_rdata <= sdram_d;
            rsp_valid <= 1'b1;
            state <= ST_READ_RECOVERY;
        end

        ST_READ_RECOVERY: state <= ST_IDLE;

        ST_WRITE_COMMAND: state <= ST_WRITE_RECOVERY_1;
        ST_WRITE_RECOVERY_1: state <= ST_WRITE_RECOVERY_2;
        ST_WRITE_RECOVERY_2: state <= ST_WRITE_RECOVERY_3;

        ST_WRITE_RECOVERY_3: begin
            rsp_valid <= 1'b1;
            state <= ST_IDLE;
        end

        ST_REFRESH_PRECHARGE: state <= ST_REFRESH_TRP_1;
        ST_REFRESH_TRP_1: state <= ST_REFRESH_TRP_2;
        ST_REFRESH_TRP_2: state <= ST_REFRESH_COMMAND;
        ST_REFRESH_COMMAND: state <= ST_REFRESH_TRFC_1;
        ST_REFRESH_TRFC_1: state <= ST_REFRESH_TRFC_2;
        ST_REFRESH_TRFC_2: state <= ST_REFRESH_TRFC_3;
        ST_REFRESH_TRFC_3: state <= ST_REFRESH_TRFC_4;
        ST_REFRESH_TRFC_4: state <= ST_IDLE;

        default: state <= ST_INIT_WAIT;
        endcase
    end
end

always @ (*) begin
    // NOP is the safe default command.
    sdram_csn = 1'b0;
    sdram_rasn = 1'b1;
    sdram_casn = 1'b1;
    sdram_wen = 1'b1;
    sdram_a = {ROW_WIDTH{1'b0}};
    sdram_ba = {BANK_WIDTH{1'b0}};
    sdram_dqm = 2'b00;
    dq_output_enable = 1'b0;
    dq_output = request_wdata;

    case (state)
    ST_INIT_PRECHARGE,
    ST_REFRESH_PRECHARGE: begin
        // PRECHARGE ALL: A10 high.
        sdram_rasn = 1'b0;
        sdram_wen = 1'b0;
        sdram_a[10] = 1'b1;
    end

    ST_INIT_REFRESH_1,
    ST_INIT_REFRESH_2,
    ST_REFRESH_COMMAND: begin
        // AUTO REFRESH.
        sdram_rasn = 1'b0;
        sdram_casn = 1'b0;
    end

    ST_INIT_MODE: begin
        // Burst length 1, sequential burst, CAS latency 2, single-location
        // write burst. The resulting mode-register value is 13'h220.
        sdram_rasn = 1'b0;
        sdram_casn = 1'b0;
        sdram_wen = 1'b0;
        sdram_a = {{(ROW_WIDTH-10){1'b0}}, 10'h220};
    end

    ST_ACTIVATE: begin
        sdram_rasn = 1'b0;
        sdram_ba = request_addr[HADDR_WIDTH-1 -: BANK_WIDTH];
        sdram_a = request_addr[COL_WIDTH +: ROW_WIDTH];
    end

    ST_READ_COMMAND: begin
        sdram_casn = 1'b0;
        sdram_ba = request_addr[HADDR_WIDTH-1 -: BANK_WIDTH];
        sdram_a = {{(ROW_WIDTH-COL_WIDTH-1){1'b0}}, 1'b1,
            request_addr[COL_WIDTH-1:0]};
        sdram_dqm = 2'b00;
    end

    ST_WRITE_COMMAND: begin
        sdram_casn = 1'b0;
        sdram_wen = 1'b0;
        sdram_ba = request_addr[HADDR_WIDTH-1 -: BANK_WIDTH];
        sdram_a = {{(ROW_WIDTH-COL_WIDTH-1){1'b0}}, 1'b1,
            request_addr[COL_WIDTH-1:0]};
        sdram_dqm = ~request_wmask;
        dq_output_enable = 1'b1;
    end

    default: begin
    end
    endcase
end

endmodule
