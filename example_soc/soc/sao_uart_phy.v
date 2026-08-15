/*****************************************************************************\
|                        Copyright (C) 2026 gojimmypi                        |
|                     SPDX-License-Identifier: Apache-2.0                    |
\*****************************************************************************/

// Minimal 8N1 UART byte interface used by the ESP32 SAO sideband link.

`default_nettype none

module sao_uart_phy #(
    parameter integer CLK_HZ = 50000000,
    parameter integer BAUD   = 115200
) (
    input  wire       clk,
    input  wire       rst_n,

    input  wire       rx_i,
    output reg        tx_o,

    output reg        rx_valid,
    output reg  [7:0] rx_data,

    input  wire       tx_valid,
    input  wire [7:0] tx_data,
    output wire       tx_ready
);

localparam integer CLKS_PER_BIT = CLK_HZ / BAUD;
localparam integer HALF_BIT     = CLKS_PER_BIT / 2;
localparam integer CTR_WIDTH    = $clog2(CLKS_PER_BIT + 1);
localparam [CTR_WIDTH-1:0] BIT_RELOAD  = CLKS_PER_BIT - 1;
localparam [CTR_WIDTH-1:0] HALF_RELOAD = HALF_BIT;

localparam [1:0] RX_IDLE  = 2'd0;
localparam [1:0] RX_START = 2'd1;
localparam [1:0] RX_DATA  = 2'd2;
localparam [1:0] RX_STOP  = 2'd3;

reg rx_meta;
reg rx_sync;
reg [1:0] rx_state;
reg [CTR_WIDTH-1:0] rx_ctr;
reg [2:0] rx_bit;
reg [7:0] rx_shift;

reg tx_busy;
reg [CTR_WIDTH-1:0] tx_ctr;
reg [3:0] tx_bit;
reg [9:0] tx_shift;

assign tx_ready = !tx_busy;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        rx_meta <= 1'b1;
        rx_sync <= 1'b1;
    end else begin
        rx_meta <= rx_i;
        rx_sync <= rx_meta;
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        rx_valid <= 1'b0;
        rx_data  <= 8'd0;
        rx_state <= RX_IDLE;
        rx_ctr   <= {CTR_WIDTH{1'b0}};
        rx_bit   <= 3'd0;
        rx_shift <= 8'd0;
    end else begin
        rx_valid <= 1'b0;

        case (rx_state)
            RX_IDLE: begin
                if (!rx_sync) begin
                    rx_ctr   <= HALF_RELOAD;
                    rx_state <= RX_START;
                end
            end

            RX_START: begin
                if (|rx_ctr) begin
                    rx_ctr <= rx_ctr - 1'b1;
                end else if (!rx_sync) begin
                    rx_ctr   <= BIT_RELOAD;
                    rx_bit   <= 3'd0;
                    rx_shift <= 8'd0;
                    rx_state <= RX_DATA;
                end else begin
                    rx_state <= RX_IDLE;
                end
            end

            RX_DATA: begin
                if (|rx_ctr) begin
                    rx_ctr <= rx_ctr - 1'b1;
                end else begin
                    rx_shift[rx_bit] <= rx_sync;
                    rx_ctr <= BIT_RELOAD;
                    if (rx_bit == 3'd7) begin
                        rx_state <= RX_STOP;
                    end else begin
                        rx_bit <= rx_bit + 1'b1;
                    end
                end
            end

            RX_STOP: begin
                if (|rx_ctr) begin
                    rx_ctr <= rx_ctr - 1'b1;
                end else begin
                    if (rx_sync) begin
                        rx_data  <= rx_shift;
                        rx_valid <= 1'b1;
                    end
                    rx_state <= RX_IDLE;
                end
            end

            default: rx_state <= RX_IDLE;
        endcase
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        tx_o     <= 1'b1;
        tx_busy  <= 1'b0;
        tx_ctr   <= {CTR_WIDTH{1'b0}};
        tx_bit   <= 4'd0;
        tx_shift <= 10'h3ff;
    end else if (!tx_busy) begin
        tx_o <= 1'b1;
        if (tx_valid) begin
            tx_shift <= {1'b1, tx_data, 1'b0};
            tx_o     <= 1'b0;
            tx_ctr   <= BIT_RELOAD;
            tx_bit   <= 4'd0;
            tx_busy  <= 1'b1;
        end
    end else if (|tx_ctr) begin
        tx_ctr <= tx_ctr - 1'b1;
    end else if (tx_bit == 4'd9) begin
        tx_o    <= 1'b1;
        tx_busy <= 1'b0;
    end else begin
        tx_shift <= {1'b1, tx_shift[9:1]};
        tx_o     <= tx_shift[1];
        tx_ctr   <= BIT_RELOAD;
        tx_bit   <= tx_bit + 1'b1;
    end
end

endmodule

`default_nettype wire
