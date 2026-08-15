/*****************************************************************************\
|                        Copyright (C) 2026 gojimmypi                        |
|                     SPDX-License-Identifier: Apache-2.0                    |
\*****************************************************************************/

// APB front-end for the SAO v1.69bis I2C/GPIO bridge.

`default_nettype none

module apb_sao_bridge #(
    parameter [15:0] CLK_DIV_RESET = 16'd250,
    parameter [31:0] TIMEOUT_RESET = 32'd500000
) (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        apbs_psel,
    input  wire        apbs_penable,
    input  wire        apbs_pwrite,
    input  wire [15:0] apbs_paddr,
    input  wire [31:0] apbs_pwdata,
    output reg  [31:0] apbs_prdata,
    output wire        apbs_pready,
    output wire        apbs_pslverr,

    input  wire        sao_sda_i,
    input  wire        sao_scl_i,
    output wire        sao_sda_drive_low,
    output wire        sao_scl_drive_low,

    input  wire        sao_gpio1_i,
    output wire        sao_gpio1_o,
    output wire        sao_gpio1_oe,
    input  wire        sao_gpio2_i,
    output wire        sao_gpio2_o,
    output wire        sao_gpio2_oe
);

localparam [2:0] CMD_WRITE   = 3'd3;
localparam [2:0] CMD_RECOVER = 3'd6;
localparam [2:0] CMD_ABORT   = 3'd7;

localparam [5:0] REG_COMMAND = 6'h00;
localparam [5:0] REG_STATUS  = 6'h01;
localparam [5:0] REG_TXDATA  = 6'h02;
localparam [5:0] REG_RXDATA  = 6'h03;
localparam [5:0] REG_CLKDIV  = 6'h04;
localparam [5:0] REG_TIMEOUT = 6'h05;
localparam [5:0] REG_GPIO    = 6'h06;
localparam [5:0] REG_LINES   = 6'h07;
localparam [5:0] REG_ID      = 6'h08;
localparam [5:0] REG_VERSION = 6'h09;

wire apb_write = apbs_psel && apbs_penable && apbs_pwrite;
wire [5:0] reg_addr = apbs_paddr[7:2];

reg [7:0] tx_data;
reg [15:0] clk_div;
reg [31:0] timeout_cycles;
reg [3:0] gpio_ctrl;
reg cmd_valid;
reg [2:0] cmd;

reg done_sticky;
reg timeout_sticky;
reg rejected_sticky;
reg recovered_sticky;
reg ack_sticky;
reg ack_valid_sticky;

reg sda_meta;
reg sda_sync;
reg scl_meta;
reg scl_sync;
reg gpio1_meta;
reg gpio1_sync;
reg gpio2_meta;
reg gpio2_sync;

wire engine_busy;
wire engine_done;
wire engine_ack;
wire engine_timeout;
wire engine_bus_active;
wire [7:0] engine_rx_data;

assign apbs_pready  = 1'b1;
assign apbs_pslverr = 1'b0;

assign sao_gpio1_o  = gpio_ctrl[0];
assign sao_gpio1_oe = gpio_ctrl[1];
assign sao_gpio2_o  = gpio_ctrl[2];
assign sao_gpio2_oe = gpio_ctrl[3];

sao_i2c_engine i2c_u (
    .clk            (clk),
    .rst_n          (rst_n),
    .cmd_valid      (cmd_valid),
    .cmd            (cmd),
    .tx_data        (tx_data),
    .clk_div        (clk_div),
    .timeout_cycles (timeout_cycles),
    .sda_i          (sda_sync),
    .scl_i          (scl_sync),
    .sda_drive_low  (sao_sda_drive_low),
    .scl_drive_low  (sao_scl_drive_low),
    .busy           (engine_busy),
    .done           (engine_done),
    .ack            (engine_ack),
    .timeout        (engine_timeout),
    .bus_active     (engine_bus_active),
    .rx_data        (engine_rx_data)
);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        sda_meta   <= 1'b1;
        sda_sync   <= 1'b1;
        scl_meta   <= 1'b1;
        scl_sync   <= 1'b1;
        gpio1_meta <= 1'b0;
        gpio1_sync <= 1'b0;
        gpio2_meta <= 1'b0;
        gpio2_sync <= 1'b0;
    end else begin
        sda_meta   <= sao_sda_i;
        sda_sync   <= sda_meta;
        scl_meta   <= sao_scl_i;
        scl_sync   <= scl_meta;
        gpio1_meta <= sao_gpio1_i;
        gpio1_sync <= gpio1_meta;
        gpio2_meta <= sao_gpio2_i;
        gpio2_sync <= gpio2_meta;
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        tx_data          <= 8'd0;
        clk_div          <= CLK_DIV_RESET;
        timeout_cycles   <= TIMEOUT_RESET;
        gpio_ctrl        <= 4'd0;
        cmd_valid        <= 1'b0;
        cmd              <= 3'd0;
        done_sticky      <= 1'b0;
        timeout_sticky   <= 1'b0;
        rejected_sticky  <= 1'b0;
        recovered_sticky <= 1'b0;
        ack_sticky       <= 1'b0;
        ack_valid_sticky <= 1'b0;
    end else begin
        cmd_valid <= 1'b0;

        if (engine_done) begin
            done_sticky    <= 1'b1;
            timeout_sticky <= timeout_sticky | engine_timeout;
            if (cmd == CMD_WRITE) begin
                ack_sticky       <= engine_ack;
                ack_valid_sticky <= 1'b1;
            end
            if (cmd == CMD_RECOVER && !engine_timeout && sda_sync && scl_sync) begin
                recovered_sticky <= 1'b1;
            end
        end

        if (apb_write) begin
            case (reg_addr)
                REG_COMMAND: begin
                    if (!engine_busy || apbs_pwdata[2:0] == CMD_ABORT) begin
                        cmd              <= apbs_pwdata[2:0];
                        cmd_valid        <= 1'b1;
                        done_sticky      <= 1'b0;
                        timeout_sticky   <= 1'b0;
                        rejected_sticky  <= 1'b0;
                        recovered_sticky <= 1'b0;
                        ack_sticky       <= 1'b0;
                        ack_valid_sticky <= 1'b0;
                    end else begin
                        rejected_sticky <= 1'b1;
                    end
                end
                REG_STATUS: begin
                    if (apbs_pwdata[1])  done_sticky      <= 1'b0;
                    if (apbs_pwdata[4])  timeout_sticky   <= 1'b0;
                    if (apbs_pwdata[5])  rejected_sticky  <= 1'b0;
                    if (apbs_pwdata[11]) recovered_sticky <= 1'b0;
                end
                REG_TXDATA: begin
                    tx_data <= apbs_pwdata[7:0];
                end
                REG_CLKDIV: begin
                    clk_div <= apbs_pwdata[15:0] == 16'd0
                        ? 16'd1 : apbs_pwdata[15:0];
                end
                REG_TIMEOUT: begin
                    timeout_cycles <= apbs_pwdata;
                end
                REG_GPIO: begin
                    gpio_ctrl <= apbs_pwdata[3:0];
                end
                default: begin
                end
            endcase
        end
    end
end

always @(*) begin
    case (reg_addr)
        REG_COMMAND: apbs_prdata = 32'd0;
        REG_STATUS:  apbs_prdata = {
            20'd0,
            recovered_sticky,
            gpio2_sync,
            gpio1_sync,
            scl_sync,
            sda_sync,
            engine_bus_active,
            rejected_sticky,
            timeout_sticky,
            ack_valid_sticky && !ack_sticky,
            ack_valid_sticky && ack_sticky,
            done_sticky,
            engine_busy
        };
        REG_TXDATA:  apbs_prdata = {24'd0, tx_data};
        REG_RXDATA:  apbs_prdata = {24'd0, engine_rx_data};
        REG_CLKDIV:  apbs_prdata = {16'd0, clk_div};
        REG_TIMEOUT: apbs_prdata = timeout_cycles;
        REG_GPIO:    apbs_prdata = {
            22'd0, gpio2_sync, gpio1_sync, 4'd0, gpio_ctrl
        };
        REG_LINES:   apbs_prdata = {
            28'd0, gpio2_sync, gpio1_sync, scl_sync, sda_sync
        };
        REG_ID:      apbs_prdata = 32'h53414f31; // ASCII "SAO1"
        REG_VERSION: apbs_prdata = 32'h00020000; // 2.0.0
        default:     apbs_prdata = 32'd0;
    endcase
end

endmodule

`default_nettype wire
