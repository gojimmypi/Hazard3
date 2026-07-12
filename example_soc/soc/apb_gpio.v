/*****************************************************************************\
|                        Copyright (C) 2026 gojimmypi                        |
|                     SPDX-License-Identifier: Apache-2.0                    |
\*****************************************************************************/

`default_nettype none

module apb_gpio (
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

    output reg  [7:0]  gpio_out
);

localparam [15:0] ADDR_GPIO_OUT = 16'h8000;

wire gpio_addr_hit = apbs_paddr[15:2] == ADDR_GPIO_OUT[15:2];

wire gpio_wen = apbs_psel && apbs_penable && apbs_pwrite && gpio_addr_hit;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        gpio_out <= 8'h00;
    else if (gpio_wen)
        gpio_out <= apbs_pwdata[7:0];
end

assign apbs_prdata = gpio_addr_hit ? {24'h000000, gpio_out} : 32'h00000000;
assign apbs_pready = 1'b1;
assign apbs_pslverr = 1'b0;

endmodule
