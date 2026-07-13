/*****************************************************************************\
|                        Copyright (C) 2026 gojimmypi                        |
|                         SPDX-License-Identifier: MIT                       |
\*****************************************************************************/

`default_nettype none

// SDRAM-backed 320x200 RGB332 framebuffer scanout for the ULX3S GPDI port.
//
// The Elecrow panel is driven at its native 1024x600 resolution. Each source
// pixel is repeated three times horizontally and each source line is repeated
// three times vertically, producing a 960x600 image with 32-pixel black bars
// on the left and right.
//
// SDRAM is read in the 50 MHz system-clock domain through a dedicated,
// read-only request port on the existing SDRAM controller. Two 320-pixel line
// buffers cross into the independent 50 MHz pixel-clock domain. The reader
// gives video requests priority over CPU requests only while filling a line.
module ulx3s_hdmi_framebuffer (
    input  wire        clk_sys,
    input  wire        rst_n_sys,
    input  wire        clk_pix,
    input  wire        rst_n_pix,
    input  wire        clk_tmds_x5,
    input  wire        rst_n_tmds_x5,

    output wire        sdram_req_valid,
    input  wire        sdram_req_ready,
    output wire [24:0] sdram_req_addr,
    input  wire        sdram_rsp_valid,
    input  wire [15:0] sdram_rsp_rdata,
    input  wire        sdram_init_done,

    output wire [3:0]  gpdi_dp
);

localparam H_ACTIVE = 1024;
localparam H_FRONT  = 48;
localparam H_SYNC   = 96;
localparam H_BACK   = 144;
localparam H_TOTAL  = H_ACTIVE + H_FRONT + H_SYNC + H_BACK;

localparam V_ACTIVE = 600;
localparam V_FRONT  = 3;
localparam V_SYNC   = 10;
localparam V_BACK   = 11;
localparam V_TOTAL  = V_ACTIVE + V_FRONT + V_SYNC + V_BACK;

localparam SOURCE_WIDTH = 320;
localparam SOURCE_HEIGHT = 200;
localparam SOURCE_WORDS_PER_LINE = SOURCE_WIDTH / 2;
localparam IMAGE_X_START = (H_ACTIVE - SOURCE_WIDTH * 3) / 2;
localparam IMAGE_X_END = IMAGE_X_START + SOURCE_WIDTH * 3;

// 0x23c00000 is byte offset 0x03c00000 within the 64 MiB SDRAM window.
// The native SDRAM request address is a 16-bit halfword address.
localparam [24:0] FRAMEBUFFER_HALFWORD_BASE = 25'h1e00000;

(* ram_style = "block" *) reg [15:0] line_buffer0 [0:SOURCE_WORDS_PER_LINE-1];
(* ram_style = "block" *) reg [15:0] line_buffer1 [0:SOURCE_WORDS_PER_LINE-1];

// ----------------------------------------------------------------------------
// System-clock-domain SDRAM line reader

localparam [1:0]
    READER_WAIT_INIT = 2'd0,
    READER_REQUEST   = 2'd1,
    READER_RESPONSE  = 2'd2,
    READER_WAIT_LINE = 2'd3;

reg [1:0] reader_state;
reg [7:0] fill_line;
reg       fill_buffer;
reg [7:0] fill_word;
reg [24:0] reader_address;

reg ready_toggle_sys;
reg [7:0] ready_line_sys;
reg ready_buffer_sys;

(* async_reg = "true" *) reg request_toggle_sync0;
(* async_reg = "true" *) reg request_toggle_sync1;
reg request_toggle_seen_sys;
reg [7:0] request_line_sync0;
reg [7:0] request_line_sync1;

// Pixel-domain request signals remain stable until the next completed line is
// accepted, so synchronizing each bus bit alongside the toggle is safe.
reg request_toggle_pix;
reg [7:0] request_line_pix;

function [24:0] framebuffer_line_address;
    input [7:0] line_number;
    reg [24:0] line_offset;
    begin
        // 160 halfwords per source line: line * (128 + 32).
        line_offset = ({17'd0, line_number} << 7)
            + ({17'd0, line_number} << 5);
        framebuffer_line_address = FRAMEBUFFER_HALFWORD_BASE + line_offset;
    end
endfunction

assign sdram_req_valid = reader_state == READER_REQUEST;
assign sdram_req_addr = reader_address;

always @ (posedge clk_sys or negedge rst_n_sys) begin
    if (!rst_n_sys) begin
        request_toggle_sync0 <= 1'b0;
        request_toggle_sync1 <= 1'b0;
        request_line_sync0 <= 8'd0;
        request_line_sync1 <= 8'd0;
    end else begin
        request_toggle_sync0 <= request_toggle_pix;
        request_toggle_sync1 <= request_toggle_sync0;
        request_line_sync0 <= request_line_pix;
        request_line_sync1 <= request_line_sync0;
    end
end

always @ (posedge clk_sys or negedge rst_n_sys) begin
    if (!rst_n_sys) begin
        reader_state <= READER_WAIT_INIT;
        fill_line <= 8'd0;
        fill_buffer <= 1'b0;
        fill_word <= 8'd0;
        reader_address <= FRAMEBUFFER_HALFWORD_BASE;
        ready_toggle_sys <= 1'b0;
        ready_line_sys <= 8'd0;
        ready_buffer_sys <= 1'b0;
        request_toggle_seen_sys <= 1'b0;
    end else begin
        case (reader_state)
        READER_WAIT_INIT: begin
            if (sdram_init_done) begin
                fill_line <= 8'd0;
                fill_buffer <= 1'b0;
                fill_word <= 8'd0;
                reader_address <= FRAMEBUFFER_HALFWORD_BASE;
                reader_state <= READER_REQUEST;
            end
        end

        READER_REQUEST: begin
            if (sdram_req_ready)
                reader_state <= READER_RESPONSE;
        end

        READER_RESPONSE: begin
            if (sdram_rsp_valid) begin
                if (fill_buffer)
                    line_buffer1[fill_word] <= sdram_rsp_rdata;
                else
                    line_buffer0[fill_word] <= sdram_rsp_rdata;

                if (fill_word == SOURCE_WORDS_PER_LINE - 1) begin
                    ready_line_sys <= fill_line;
                    ready_buffer_sys <= fill_buffer;
                    ready_toggle_sys <= !ready_toggle_sys;
                    fill_buffer <= !fill_buffer;
                    reader_state <= READER_WAIT_LINE;
                end else begin
                    fill_word <= fill_word + 1'b1;
                    reader_address <= reader_address + 1'b1;
                    reader_state <= READER_REQUEST;
                end
            end
        end

        READER_WAIT_LINE: begin
            if (request_toggle_sync1 != request_toggle_seen_sys) begin
                request_toggle_seen_sys <= request_toggle_sync1;
                fill_line <= request_line_sync1;
                fill_word <= 8'd0;
                reader_address <= framebuffer_line_address(request_line_sync1);
                reader_state <= READER_REQUEST;
            end
        end

        default: reader_state <= READER_WAIT_INIT;
        endcase
    end
end

// ----------------------------------------------------------------------------
// Pixel-clock-domain timing, line selection and 3x scaling

reg [10:0] pixel_x;
reg [9:0] pixel_y;
reg [8:0] source_x;
reg [7:0] source_line;
reg [1:0] horizontal_repeat;
reg [1:0] vertical_repeat;
reg pixel_toggle;

(* async_reg = "true" *) reg ready_toggle_sync0;
(* async_reg = "true" *) reg ready_toggle_sync1;
reg ready_toggle_seen_pix;
reg [7:0] ready_line_sync0;
reg [7:0] ready_line_sync1;
reg ready_buffer_sync0;
reg ready_buffer_sync1;

reg active_buffer;
reg [7:0] active_line;
reg active_line_valid;

wire active_video_now = pixel_x < H_ACTIVE && pixel_y < V_ACTIVE;
wire hsync_now = pixel_x >= H_ACTIVE + H_FRONT
    && pixel_x < H_ACTIVE + H_FRONT + H_SYNC;
wire vsync_now = pixel_y >= V_ACTIVE + V_FRONT
    && pixel_y < V_ACTIVE + V_FRONT + V_SYNC;
wire image_region_now = pixel_x >= IMAGE_X_START
    && pixel_x < IMAGE_X_END && pixel_y < V_ACTIVE;
wire line_start = pixel_x == 0;
wire source_group_start = line_start && vertical_repeat == 0;
wire ready_pending = ready_toggle_sync1 != ready_toggle_seen_pix;
wire ready_matches_current = ready_line_sync1 == source_line;

wire [8:0] ready_to_current_distance = source_line >= ready_line_sync1
    ? {1'b0, source_line} - {1'b0, ready_line_sync1}
    : {1'b0, source_line} + 9'd200 - {1'b0, ready_line_sync1};
wire ready_is_stale = ready_to_current_distance != 0
    && ready_to_current_distance < 9'd100;

always @ (posedge clk_pix or negedge rst_n_pix) begin
    if (!rst_n_pix) begin
        ready_toggle_sync0 <= 1'b0;
        ready_toggle_sync1 <= 1'b0;
        ready_line_sync0 <= 8'd0;
        ready_line_sync1 <= 8'd0;
        ready_buffer_sync0 <= 1'b0;
        ready_buffer_sync1 <= 1'b0;
    end else begin
        ready_toggle_sync0 <= ready_toggle_sys;
        ready_toggle_sync1 <= ready_toggle_sync0;
        ready_line_sync0 <= ready_line_sys;
        ready_line_sync1 <= ready_line_sync0;
        ready_buffer_sync0 <= ready_buffer_sys;
        ready_buffer_sync1 <= ready_buffer_sync0;
    end
end

always @ (posedge clk_pix or negedge rst_n_pix) begin
    if (!rst_n_pix) begin
        pixel_x <= 11'd0;
        pixel_y <= 10'd0;
        source_x <= 9'd0;
        source_line <= 8'd0;
        horizontal_repeat <= 2'd0;
        vertical_repeat <= 2'd0;
        pixel_toggle <= 1'b0;
        ready_toggle_seen_pix <= 1'b0;
        request_toggle_pix <= 1'b0;
        request_line_pix <= 8'd0;
        active_buffer <= 1'b0;
        active_line <= 8'd0;
        active_line_valid <= 1'b0;
    end else begin
        pixel_toggle <= !pixel_toggle;

        if (line_start) begin
            if (ready_pending && ready_matches_current) begin
                ready_toggle_seen_pix <= ready_toggle_sync1;
                active_buffer <= ready_buffer_sync1;
                active_line <= ready_line_sync1;
                active_line_valid <= 1'b1;
                request_line_pix <= ready_line_sync1 == SOURCE_HEIGHT - 1
                    ? 8'd0 : ready_line_sync1 + 1'b1;
                request_toggle_pix <= !request_toggle_pix;
            end else if (ready_pending && ready_is_stale) begin
                // A late line is acknowledged without displaying it so the
                // reader can continue and catch up to the current raster.
                ready_toggle_seen_pix <= ready_toggle_sync1;
                request_line_pix <= ready_line_sync1 == SOURCE_HEIGHT - 1
                    ? 8'd0 : ready_line_sync1 + 1'b1;
                request_toggle_pix <= !request_toggle_pix;
            end

            if (source_group_start &&
                !(ready_pending && ready_matches_current) &&
                !(active_line_valid && active_line == source_line)) begin
                active_line_valid <= 1'b0;
            end
        end

        if (pixel_x == H_TOTAL - 1) begin
            pixel_x <= 11'd0;
            source_x <= 9'd0;
            horizontal_repeat <= 2'd0;

            if (pixel_y == V_TOTAL - 1) begin
                pixel_y <= 10'd0;
                source_line <= 8'd0;
                vertical_repeat <= 2'd0;
            end else begin
                pixel_y <= pixel_y + 1'b1;
                if (pixel_y < V_ACTIVE - 1) begin
                    if (vertical_repeat == 2) begin
                        vertical_repeat <= 2'd0;
                        source_line <= source_line == SOURCE_HEIGHT - 1
                            ? 8'd0 : source_line + 1'b1;
                    end else begin
                        vertical_repeat <= vertical_repeat + 1'b1;
                    end
                end
            end
        end else begin
            pixel_x <= pixel_x + 1'b1;
            if (pixel_x >= IMAGE_X_START && pixel_x < IMAGE_X_END - 1) begin
                if (horizontal_repeat == 2) begin
                    horizontal_repeat <= 2'd0;
                    source_x <= source_x + 1'b1;
                end else begin
                    horizontal_repeat <= horizontal_repeat + 1'b1;
                end
            end
        end
    end
end

// ----------------------------------------------------------------------------
// Dual-clock line-buffer read and RGB332 expansion

reg [15:0] line_word0_q;
reg [15:0] line_word1_q;
reg source_byte_select_q;
reg active_buffer_q;
reg image_region_q;
reg line_valid_q;
reg active_video_q;
reg hsync_q;
reg vsync_q;
reg fallback_phase_q;

always @ (posedge clk_pix) begin
    line_word0_q <= line_buffer0[source_x[8:1]];
    line_word1_q <= line_buffer1[source_x[8:1]];
    source_byte_select_q <= source_x[0];
    active_buffer_q <= active_buffer;
    image_region_q <= image_region_now;
    line_valid_q <= active_line_valid && active_line == source_line;
    active_video_q <= active_video_now;
    hsync_q <= hsync_now;
    vsync_q <= vsync_now;
    fallback_phase_q <= pixel_x[5] ^ pixel_y[5];
end

wire [15:0] selected_line_word = active_buffer_q ? line_word1_q : line_word0_q;
wire [7:0] framebuffer_pixel = source_byte_select_q
    ? selected_line_word[15:8] : selected_line_word[7:0];

wire [7:0] framebuffer_red = {
    framebuffer_pixel[7:5], framebuffer_pixel[7:5], framebuffer_pixel[7:6]
};
wire [7:0] framebuffer_green = {
    framebuffer_pixel[4:2], framebuffer_pixel[4:2], framebuffer_pixel[4:3]
};
wire [7:0] framebuffer_blue = {
    framebuffer_pixel[1:0], framebuffer_pixel[1:0],
    framebuffer_pixel[1:0], framebuffer_pixel[1:0]
};

reg [7:0] red;
reg [7:0] green;
reg [7:0] blue;

always @ (*) begin
    red = 8'h00;
    green = 8'h00;
    blue = 8'h00;

    if (active_video_q && image_region_q) begin
        if (line_valid_q) begin
            red = framebuffer_red;
            green = framebuffer_green;
            blue = framebuffer_blue;
        end else if (fallback_phase_q) begin
            red = 8'hff;
            blue = 8'hff;
        end else begin
            red = 8'h40;
            blue = 8'h40;
        end
    end
end

wire [9:0] tmds_red;
wire [9:0] tmds_green;
wire [9:0] tmds_blue;

tmds_encode encode_red_u (
    .clk   (clk_pix),
    .rst_n (rst_n_pix),
    .c     (2'b00),
    .d     (red),
    .den   (active_video_q),
    .q     (tmds_red)
);

tmds_encode encode_green_u (
    .clk   (clk_pix),
    .rst_n (rst_n_pix),
    .c     (2'b00),
    .d     (green),
    .den   (active_video_q),
    .q     (tmds_green)
);

tmds_encode encode_blue_u (
    .clk   (clk_pix),
    .rst_n (rst_n_pix),
    .c     ({vsync_q, hsync_q}),
    .d     (blue),
    .den   (active_video_q),
    .q     (tmds_blue)
);

// Transfer a once-per-pixel toggle into the 5x serializer domain. Both clocks
// come from the same PLL, and the synchronizer delays capture until the TMDS
// symbols have settled.
(* async_reg = "true" *) reg [2:0] pixel_toggle_sync;

always @ (posedge clk_tmds_x5 or negedge rst_n_tmds_x5) begin
    if (!rst_n_tmds_x5)
        pixel_toggle_sync <= 3'b000;
    else
        pixel_toggle_sync <= {pixel_toggle_sync[1:0], pixel_toggle};
end

wire load_symbol = pixel_toggle_sync[2] ^ pixel_toggle_sync[1];

ulx3s_tmds_ddr_serialiser serialise_blue_u (
    .clk_tmds_x5 (clk_tmds_x5),
    .rst_n        (rst_n_tmds_x5),
    .load_symbol  (load_symbol),
    .symbol       (tmds_blue),
    .serial_out   (gpdi_dp[0])
);

ulx3s_tmds_ddr_serialiser serialise_green_u (
    .clk_tmds_x5 (clk_tmds_x5),
    .rst_n        (rst_n_tmds_x5),
    .load_symbol  (load_symbol),
    .symbol       (tmds_green),
    .serial_out   (gpdi_dp[1])
);

ulx3s_tmds_ddr_serialiser serialise_red_u (
    .clk_tmds_x5 (clk_tmds_x5),
    .rst_n        (rst_n_tmds_x5),
    .load_symbol  (load_symbol),
    .symbol       (tmds_red),
    .serial_out   (gpdi_dp[2])
);

ulx3s_tmds_ddr_serialiser serialise_clock_u (
    .clk_tmds_x5 (clk_tmds_x5),
    .rst_n        (rst_n_tmds_x5),
    .load_symbol  (load_symbol),
    .symbol       (10'b00000_11111),
    .serial_out   (gpdi_dp[3])
);

endmodule

`default_nettype wire
