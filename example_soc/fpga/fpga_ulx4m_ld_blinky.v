/*****************************************************************************\
|                        Copyright (C) 2026 gojimmypi                        |
|                         SPDX-License-Identifier: MIT                       |
\*****************************************************************************/

`default_nettype none

// Standalone ULX4M-LD configuration and clock diagnostic.
//
// This design deliberately excludes Hazard3, all PLLs, DDR3, HDMI, and UART.
// If it is loaded successfully, all eight module LEDs toggle together at 1 Hz
// from the module's 25 MHz oscillator. This isolates FPGA configuration, the
// oscillator, and LED pin constraints from every other subsystem.
module fpga_ulx4m_ld_blinky (
    input  wire       clk_osc,
    output wire [7:0] led
);

wire heartbeat;

blinky #(
    .CLK_HZ   (25_000_000),
    .BLINK_HZ (1)
) heartbeat_u (
    .clk   (clk_osc),
    .blink (heartbeat)
);

assign led = {8{heartbeat}};

endmodule

`default_nettype wire
