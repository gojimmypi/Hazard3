/*****************************************************************************\
|                        Copyright (C) 2026 gojimmypi                        |
|                     SPDX-License-Identifier: Apache-2.0                    |
\*****************************************************************************/

// Arbitration wrapper for the Hazard3 APB SAO bridge and the optional ESP32
// UART sideband master. Ownership only changes while the Hazard3 I2C engine
// is idle and has no transaction between START and STOP.

`default_nettype none

module sao_shared_controller #(
    parameter [15:0] CLK_DIV_RESET = 16'd250,
    parameter [31:0] TIMEOUT_RESET = 32'd500000,
    parameter integer CLK_HZ = 50000000,
    parameter integer ESP_UART_BAUD = 115200,
    parameter integer ESP_UART_ENABLE = 0
) (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        apbs_psel,
    input  wire        apbs_penable,
    input  wire        apbs_pwrite,
    input  wire [15:0] apbs_paddr,
    input  wire [31:0] apbs_pwdata,
    output wire [31:0] apbs_prdata,
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
    output wire        sao_gpio2_oe,

    input  wire        esp_uart_rx,
    output wire        esp_uart_tx,
    output wire        esp_uart_tx_oe
);

wire h3_sda_drive_low;
wire h3_scl_drive_low;
wire h3_i2c_busy;
wire h3_bus_active;
wire h3_i2c_enable;

wire esp_bus_request;
wire esp_bus_grant;
wire esp_sda_drive_low;
wire esp_scl_drive_low;
wire esp_uart_tx_internal;
wire esp_uart_tx_oe_internal;

reg esp_owner;

// Once an ESP32 request is pending, prevent Hazard3 from starting a new I2C
// transaction as soon as its current START..STOP transaction is complete.
// Hazard3 remains enabled while busy or bus-active so an in-flight sequence
// can finish cleanly rather than being cut off between bytes.
assign h3_i2c_enable = !esp_owner &&
    !(esp_bus_request && !h3_i2c_busy && !h3_bus_active);

assign esp_bus_grant = esp_owner;
assign sao_sda_drive_low = esp_owner ? esp_sda_drive_low : h3_sda_drive_low;
assign sao_scl_drive_low = esp_owner ? esp_scl_drive_low : h3_scl_drive_low;
assign esp_uart_tx = ESP_UART_ENABLE ? esp_uart_tx_internal : 1'b1;
assign esp_uart_tx_oe = ESP_UART_ENABLE ? esp_uart_tx_oe_internal : 1'b0;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        esp_owner <= 1'b0;
    end else if (!esp_owner) begin
        if (esp_bus_request && !h3_i2c_busy && !h3_bus_active) begin
            esp_owner <= 1'b1;
        end
    end else if (!esp_bus_request) begin
        esp_owner <= 1'b0;
    end
end

apb_sao_bridge #(
    .CLK_DIV_RESET (CLK_DIV_RESET),
    .TIMEOUT_RESET (TIMEOUT_RESET)
) h3_u (
    .clk               (clk),
    .rst_n             (rst_n),

    .apbs_psel         (apbs_psel),
    .apbs_penable      (apbs_penable),
    .apbs_pwrite       (apbs_pwrite),
    .apbs_paddr        (apbs_paddr),
    .apbs_pwdata       (apbs_pwdata),
    .apbs_prdata       (apbs_prdata),
    .apbs_pready       (apbs_pready),
    .apbs_pslverr      (apbs_pslverr),

    .sao_sda_i         (sao_sda_i),
    .sao_scl_i         (sao_scl_i),
    .sao_sda_drive_low (h3_sda_drive_low),
    .sao_scl_drive_low (h3_scl_drive_low),

    .sao_gpio1_i       (sao_gpio1_i),
    .sao_gpio1_o       (sao_gpio1_o),
    .sao_gpio1_oe      (sao_gpio1_oe),
    .sao_gpio2_i       (sao_gpio2_i),
    .sao_gpio2_o       (sao_gpio2_o),
    .sao_gpio2_oe      (sao_gpio2_oe),

    .i2c_enable        (h3_i2c_enable),
    .i2c_busy          (h3_i2c_busy),
    .i2c_bus_active    (h3_bus_active),
    .esp_owner         (esp_owner),
    .esp_request       (esp_bus_request)
);

generate
if (ESP_UART_ENABLE != 0) begin: gen_esp_uart
    sao_esp32_uart_bridge #(
        .CLK_HZ (CLK_HZ),
        .BAUD   (ESP_UART_BAUD)
    ) esp_u (
        .clk               (clk),
        .rst_n             (rst_n),
        .uart_rx           (esp_uart_rx),
        .uart_tx           (esp_uart_tx_internal),
        .uart_tx_oe        (esp_uart_tx_oe_internal),
        .bus_request       (esp_bus_request),
        .bus_grant         (esp_bus_grant),
        .sao_sda_i         (sao_sda_i),
        .sao_scl_i         (sao_scl_i),
        .sao_sda_drive_low (esp_sda_drive_low),
        .sao_scl_drive_low (esp_scl_drive_low)
    );
end else begin: gen_no_esp_uart
    assign esp_bus_request  = 1'b0;
    assign esp_sda_drive_low = 1'b0;
    assign esp_scl_drive_low = 1'b0;
    assign esp_uart_tx_internal = 1'b1;
    assign esp_uart_tx_oe_internal = 1'b0;
end
endgenerate

endmodule

`default_nettype wire
