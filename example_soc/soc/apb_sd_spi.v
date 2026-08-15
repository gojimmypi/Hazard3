/*****************************************************************************\
|                        Copyright (C) 2026 gojimmypi                        |
|                     SPDX-License-Identifier: Apache-2.0                    |
\*****************************************************************************/

`default_nettype none

// Small software-driven SPI master for the ULX3S micro-SD socket.
//
// APB register map (CPU base 0x4000A000):
//   +0x00 CTRL    bit 0: CS_n (1 = deselected)
//   +0x04 CLKDIV  half-period divider; SCLK = clk / (2 * (CLKDIV + 1))
//   +0x08 DATA    write low byte to start; read low byte for received data
//   +0x0c STATUS  bit 0: BUSY
//
// SPI mode 0, MSB first. The peripheral deliberately has no FIFO or DMA; the
// resident monitor performs block reads and keeps the implementation small.
module apb_sd_spi (
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

    output reg         sd_clk,
    output reg         sd_mosi,
    input  wire        sd_miso,
    output reg         sd_csn
);

localparam [15:0] ADDR_CTRL   = 16'ha000;
localparam [15:0] ADDR_CLKDIV = 16'ha004;
localparam [15:0] ADDR_DATA   = 16'ha008;
localparam [15:0] ADDR_STATUS = 16'ha00c;

// 50 MHz / (2 * (124 + 1)) = 200 kHz, safely below the SD initialization
// ceiling. Firmware switches to a smaller divider after the card is ready.
localparam [15:0] RESET_CLKDIV = 16'd124;

reg [15:0] clkdiv;
reg [15:0] divider_count;
reg [7:0]  tx_shift;
reg [7:0]  rx_shift;
reg [7:0]  rx_data;
reg [2:0]  bit_index;
reg        busy;

wire ctrl_wen = apbs_psel && apbs_penable && apbs_pwrite &&
    apbs_paddr[15:2] == ADDR_CTRL[15:2];
wire clkdiv_wen = apbs_psel && apbs_penable && apbs_pwrite &&
    apbs_paddr[15:2] == ADDR_CLKDIV[15:2];
wire data_wen = apbs_psel && apbs_penable && apbs_pwrite &&
    apbs_paddr[15:2] == ADDR_DATA[15:2];

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        sd_clk        <= 1'b0;
        sd_mosi       <= 1'b1;
        sd_csn        <= 1'b1;
        clkdiv        <= RESET_CLKDIV;
        divider_count <= 16'd0;
        tx_shift      <= 8'hff;
        rx_shift      <= 8'h00;
        rx_data       <= 8'hff;
        bit_index     <= 3'd7;
        busy          <= 1'b0;
    end else begin
        if (ctrl_wen)
            sd_csn <= apbs_pwdata[0];

        if (clkdiv_wen && !busy)
            clkdiv <= apbs_pwdata[15:0];

        if (data_wen && !busy) begin
            tx_shift      <= apbs_pwdata[7:0];
            rx_shift      <= 8'h00;
            bit_index     <= 3'd7;
            divider_count <= clkdiv;
            sd_clk        <= 1'b0;
            sd_mosi       <= apbs_pwdata[7];
            busy          <= 1'b1;
        end else if (busy) begin
            if (divider_count != 16'd0) begin
                divider_count <= divider_count - 1'b1;
            end else begin
                divider_count <= clkdiv;

                if (!sd_clk) begin
                    // Rising edge: sample MISO for SPI mode 0.
                    sd_clk   <= 1'b1;
                    rx_shift <= {rx_shift[6:0], sd_miso};
                end else begin
                    // Falling edge: either present the next MOSI bit or finish.
                    sd_clk <= 1'b0;
                    if (bit_index == 3'd0) begin
                        rx_data <= rx_shift;
                        sd_mosi <= 1'b1;
                        busy    <= 1'b0;
                    end else begin
                        bit_index <= bit_index - 1'b1;
                        tx_shift  <= {tx_shift[6:0], 1'b1};
                        sd_mosi   <= tx_shift[6];
                    end
                end
            end
        end
    end
end

always @(*) begin
    case (apbs_paddr[15:2])
    ADDR_CTRL[15:2]:   apbs_prdata = {31'd0, sd_csn};
    ADDR_CLKDIV[15:2]: apbs_prdata = {16'd0, clkdiv};
    ADDR_DATA[15:2]:   apbs_prdata = {24'd0, rx_data};
    ADDR_STATUS[15:2]: apbs_prdata = {31'd0, busy};
    default:            apbs_prdata = 32'h00000000;
    endcase
end

assign apbs_pready  = 1'b1;
assign apbs_pslverr = 1'b0;

endmodule

`default_nettype wire
