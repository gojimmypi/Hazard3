/*****************************************************************************\
|                        Copyright (C) 2026 gojimmypi                        |
|                         SPDX-License-Identifier: MIT                       |
\*****************************************************************************/

`default_nettype none

// Double-buffered 320x200 framebuffer output shared by ULX3S and ULX4M.
//
// The fast path writes a completed Doom frame directly into the inactive ECP5
// block-RAM bank through two APB registers, then swaps banks during vertical
// blank. This removes the earlier 64 KiB SDRAM staging copy and the subsequent
// SDRAM-to-block-RAM DMA from every Doom frame. The original SDRAM DMA path is
// retained for monitor diagnostics and backward compatibility.
//
// The Elecrow panel is driven at 1024x600. A 5/16 horizontal phase accumulator
// maps all 320 source pixels across all 1024 output pixels, while each source
// line is repeated three times vertically. The panel is therefore fully filled
// without the former 32-pixel side borders.
//
// Frame data may be either RGB332 or native Doom palette indices. Indexed mode
// uses one independently stored 256-entry RGB332 palette for each SDRAM staging
// buffer, so palette changes become visible atomically with the matching frame.
module ulx3s_hdmi_framebuffer #(
    parameter [24:0] FRAMEBUFFER0_HALFWORD_BASE = 25'h1e00000,
    parameter [24:0] FRAMEBUFFER1_HALFWORD_BASE = 25'h1e08000
) (
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

    input  wire        apbs_psel,
    input  wire        apbs_penable,
    input  wire        apbs_pwrite,
    input  wire [15:0] apbs_paddr,
    input  wire [31:0] apbs_pwdata,
    output reg  [31:0] apbs_prdata,
    output wire        apbs_pready,
    output wire        apbs_pslverr,

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
localparam SOURCE_WORDS_PER_FRAME = SOURCE_WIDTH * SOURCE_HEIGHT / 2;
localparam H_SCALE_NUMERATOR = SOURCE_WIDTH / 64;
localparam H_SCALE_DENOMINATOR = H_ACTIVE / 64;

// Native SDRAM requests use halfword addresses. The board wrapper selects
// staging-buffer offsets for its 64 MiB or 32 MiB external-memory profile.

localparam [3:0]
    REG_STATUS        = 4'h0,
    REG_CONTROL       = 4'h1,
    REG_PALETTE_INDEX = 4'h2,
    REG_PALETTE_DATA  = 4'h3,
    REG_FRAME_COUNT    = 4'h4,
    REG_DMA_CYCLES     = 4'h5,
    REG_PRESENT_COUNT  = 4'h6,
    REG_DIRECT_ADDRESS = 4'hb,
    REG_DIRECT_DATA    = 4'hc;

localparam CONTROL_INDEXED = 0;
localparam CONTROL_BUFFER  = 1;
localparam CONTROL_PRESENT = 2;
localparam CONTROL_DIRECT  = 3;

wire [3:0] apb_word_address = apbs_paddr[5:2];
wire direct_data_access = apbs_psel && apbs_penable && apbs_pwrite
    && apb_word_address == REG_DIRECT_DATA;
reg direct_write_high_half;
assign apbs_pready = !direct_data_access || direct_write_high_half;
assign apbs_pslverr = 1'b0;
wire apb_write = apbs_psel && apbs_penable && apbs_pwrite && apbs_pready;

// ----------------------------------------------------------------------------
// Full-frame ECP5 block RAM and palette RAM

wire        frame_write_enable;
wire [15:0] frame_write_address;
wire [15:0] frame_write_data;
wire [15:0] frame_read_address;
wire [15:0] frame_read_data;

reg [15:0] direct_write_address;
reg [31:0] direct_write_data;
wire direct_low_write = direct_data_access && !direct_write_high_half;
wire direct_high_write = direct_data_access && direct_write_high_half;
wire direct_frame_write = direct_low_write || direct_high_write;

ulx3s_frame_ram frame_ram_u (
    .write_clk     (clk_sys),
    .write_enable  (frame_write_enable),
    .write_address (frame_write_address),
    .write_data    (frame_write_data),
    .read_clk      (clk_pix),
    .read_address  (frame_read_address),
    .read_data     (frame_read_data)
);

reg  [8:0] palette_address_sys;
wire       palette_write_enable = apb_write && apb_word_address == REG_PALETTE_DATA;
wire [7:0] palette_read_data;
wire [8:0] palette_read_address;

ulx3s_palette_ram palette_ram_u (
    .write_clk     (clk_sys),
    .write_enable  (palette_write_enable),
    .write_address (palette_address_sys),
    .write_data    (apbs_pwdata[7:0]),
    .read_clk      (clk_pix),
    .read_address  (palette_read_address),
    .read_data     (palette_read_data)
);

// ----------------------------------------------------------------------------
// System-clock-domain presentation DMA and APB registers

localparam [2:0]
    DMA_WAIT_INIT = 3'd0,
    DMA_IDLE      = 3'd1,
    DMA_REQUEST   = 3'd2,
    DMA_RESPONSE  = 3'd3,
    DMA_WAIT_SWAP = 3'd4;

reg [2:0] dma_state;
reg [14:0] dma_word;
reg dma_source_buffer;
reg dma_target_buffer;
reg dma_indexed;
reg [31:0] dma_cycle_counter;
reg [31:0] last_dma_cycles;
reg [31:0] present_count_sys;
reg control_indexed_sys;
reg control_buffer_sys;

reg swap_toggle_sys;
reg swap_buffer_sys;
reg swap_source_sys;
reg swap_indexed_sys;

(* async_reg = "true" *) reg swap_ack_sync0;
(* async_reg = "true" *) reg swap_ack_sync1;
(* async_reg = "true" *) reg active_internal_sync0;
(* async_reg = "true" *) reg active_internal_sync1;
(* async_reg = "true" *) reg current_source_sync0;
(* async_reg = "true" *) reg current_source_sync1;
(* async_reg = "true" *) reg current_indexed_sync0;
(* async_reg = "true" *) reg current_indexed_sync1;
(* async_reg = "true" *) reg frame_valid_sync0;
(* async_reg = "true" *) reg frame_valid_sync1;
(* async_reg = "true" *) reg vblank_sync0;
(* async_reg = "true" *) reg vblank_sync1;
reg [31:0] frame_count_sync0;
reg [31:0] frame_count_sync1;

reg swap_ack_pix;
reg active_internal_buffer_pix;
reg current_source_buffer_pix;
reg current_indexed_pix;
reg frame_valid_pix;
wire vblank_pix;
reg [31:0] frame_count_pix;

wire present_pending = dma_state != DMA_IDLE;
wire dma_copy_busy = dma_state == DMA_REQUEST || dma_state == DMA_RESPONSE;
wire swap_pending = dma_state == DMA_WAIT_SWAP;
wire present_command = apb_write && apb_word_address == REG_CONTROL
    && apbs_pwdata[CONTROL_PRESENT];
wire present_can_start = dma_state == DMA_IDLE && sdram_init_done;

wire [24:0] selected_framebuffer_base = dma_source_buffer
    ? FRAMEBUFFER1_HALFWORD_BASE : FRAMEBUFFER0_HALFWORD_BASE;
assign sdram_req_valid = dma_state == DMA_REQUEST;
assign sdram_req_addr = selected_framebuffer_base + dma_word;

wire dma_frame_write = dma_state == DMA_RESPONSE && sdram_rsp_valid;
assign frame_write_enable = direct_frame_write || dma_frame_write;
assign frame_write_address = direct_frame_write
    ? (direct_high_write ? direct_write_address + 1'b1
        : direct_write_address)
    : {dma_target_buffer, dma_word};
assign frame_write_data = direct_frame_write
    ? (direct_high_write ? direct_write_data[31:16] : apbs_pwdata[15:0])
    : sdram_rsp_rdata;

always @ (posedge clk_sys or negedge rst_n_sys) begin
    if (!rst_n_sys) begin
        swap_ack_sync0 <= 1'b0;
        swap_ack_sync1 <= 1'b0;
        active_internal_sync0 <= 1'b0;
        active_internal_sync1 <= 1'b0;
        current_source_sync0 <= 1'b0;
        current_source_sync1 <= 1'b0;
        current_indexed_sync0 <= 1'b0;
        current_indexed_sync1 <= 1'b0;
        frame_valid_sync0 <= 1'b0;
        frame_valid_sync1 <= 1'b0;
        vblank_sync0 <= 1'b0;
        vblank_sync1 <= 1'b0;
        frame_count_sync0 <= 32'd0;
        frame_count_sync1 <= 32'd0;
    end else begin
        swap_ack_sync0 <= swap_ack_pix;
        swap_ack_sync1 <= swap_ack_sync0;
        active_internal_sync0 <= active_internal_buffer_pix;
        active_internal_sync1 <= active_internal_sync0;
        current_source_sync0 <= current_source_buffer_pix;
        current_source_sync1 <= current_source_sync0;
        current_indexed_sync0 <= current_indexed_pix;
        current_indexed_sync1 <= current_indexed_sync0;
        frame_valid_sync0 <= frame_valid_pix;
        frame_valid_sync1 <= frame_valid_sync0;
        vblank_sync0 <= vblank_pix;
        vblank_sync1 <= vblank_sync0;
        frame_count_sync0 <= frame_count_pix;
        frame_count_sync1 <= frame_count_sync0;
    end
end

always @ (posedge clk_sys or negedge rst_n_sys) begin
    if (!rst_n_sys) begin
        palette_address_sys <= 9'd0;
        direct_write_address <= 16'd0;
        direct_write_data <= 32'd0;
        direct_write_high_half <= 1'b0;
        control_indexed_sys <= 1'b0;
        control_buffer_sys <= 1'b0;
        dma_state <= DMA_WAIT_INIT;
        dma_word <= 15'd0;
        dma_source_buffer <= 1'b0;
        dma_target_buffer <= 1'b1;
        dma_indexed <= 1'b0;
        dma_cycle_counter <= 32'd0;
        last_dma_cycles <= 32'd0;
        present_count_sys <= 32'd0;
        swap_toggle_sys <= 1'b0;
        swap_buffer_sys <= 1'b0;
        swap_source_sys <= 1'b0;
        swap_indexed_sys <= 1'b0;
    end else begin
        if (direct_low_write) begin
            direct_write_data <= apbs_pwdata;
            direct_write_high_half <= 1'b1;
        end else if (direct_high_write) begin
            direct_write_address <= direct_write_address + 2'd2;
            direct_write_high_half <= 1'b0;
        end

        if (apb_write && apb_word_address == REG_DIRECT_ADDRESS)
            direct_write_address <= apbs_pwdata[15:0];

        if (apb_write && apb_word_address == REG_PALETTE_INDEX)
            palette_address_sys <= apbs_pwdata[8:0];
        else if (palette_write_enable)
            palette_address_sys <= {palette_address_sys[8], palette_address_sys[7:0] + 1'b1};

        if (apb_write && apb_word_address == REG_CONTROL) begin
            control_indexed_sys <= apbs_pwdata[CONTROL_INDEXED];
            control_buffer_sys <= apbs_pwdata[CONTROL_BUFFER];
        end

        if (dma_state != DMA_IDLE && dma_state != DMA_WAIT_INIT)
            dma_cycle_counter <= dma_cycle_counter + 1'b1;

        case (dma_state)
        DMA_WAIT_INIT: begin
            if (sdram_init_done)
                dma_state <= DMA_IDLE;
        end

        DMA_IDLE: begin
            if (present_command && present_can_start) begin
                dma_source_buffer <= apbs_pwdata[CONTROL_BUFFER];
                dma_indexed <= apbs_pwdata[CONTROL_INDEXED];
                dma_cycle_counter <= 32'd0;
                present_count_sys <= present_count_sys + 1'b1;

                if (apbs_pwdata[CONTROL_DIRECT]) begin
                    // Software has already filled the selected internal bank.
                    last_dma_cycles <= 32'd0;
                    swap_buffer_sys <= apbs_pwdata[CONTROL_BUFFER];
                    swap_source_sys <= apbs_pwdata[CONTROL_BUFFER];
                    swap_indexed_sys <= apbs_pwdata[CONTROL_INDEXED];
                    swap_toggle_sys <= !swap_toggle_sys;
                    dma_state <= DMA_WAIT_SWAP;
                end else begin
                    dma_word <= 15'd0;
                    dma_target_buffer <= !active_internal_sync1;
                    dma_state <= DMA_REQUEST;
                end
            end
        end

        DMA_REQUEST: begin
            if (sdram_req_ready)
                dma_state <= DMA_RESPONSE;
        end

        DMA_RESPONSE: begin
            if (sdram_rsp_valid) begin
                if (dma_word == SOURCE_WORDS_PER_FRAME - 1) begin
                    last_dma_cycles <= dma_cycle_counter + 1'b1;
                    swap_buffer_sys <= dma_target_buffer;
                    swap_source_sys <= dma_source_buffer;
                    swap_indexed_sys <= dma_indexed;
                    swap_toggle_sys <= !swap_toggle_sys;
                    dma_state <= DMA_WAIT_SWAP;
                end else begin
                    dma_word <= dma_word + 1'b1;
                    dma_state <= DMA_REQUEST;
                end
            end
        end

        DMA_WAIT_SWAP: begin
            if (swap_ack_sync1 == swap_toggle_sys)
                dma_state <= DMA_IDLE;
        end

        default: dma_state <= DMA_WAIT_INIT;
        endcase
    end
end

always @ (*) begin
    apbs_prdata = 32'd0;
    case (apb_word_address)
    REG_STATUS: begin
        apbs_prdata[0] = current_source_sync1;
        apbs_prdata[1] = present_pending;
        apbs_prdata[2] = current_indexed_sync1;
        apbs_prdata[3] = vblank_sync1;
        apbs_prdata[4] = sdram_init_done;
        apbs_prdata[5] = frame_valid_sync1;
        apbs_prdata[6] = active_internal_sync1;
        apbs_prdata[7] = dma_copy_busy;
        apbs_prdata[8] = swap_pending;
        apbs_prdata[9] = 1'b1; // Direct block-RAM write path supported.
        apbs_prdata[10] = direct_write_high_half;
    end
    REG_CONTROL: begin
        apbs_prdata[CONTROL_INDEXED] = control_indexed_sys;
        apbs_prdata[CONTROL_BUFFER] = control_buffer_sys;
    end
    REG_PALETTE_INDEX: apbs_prdata[8:0] = palette_address_sys;
    REG_FRAME_COUNT: apbs_prdata = frame_count_sync1;
    REG_DMA_CYCLES: apbs_prdata = last_dma_cycles;
    REG_PRESENT_COUNT: apbs_prdata = present_count_sys;
    REG_DIRECT_ADDRESS: apbs_prdata[15:0] = direct_write_address;
    default: apbs_prdata = 32'd0;
    endcase
end

// ----------------------------------------------------------------------------
// Pixel-clock-domain timing and vertical-blank frame swap

reg [10:0] pixel_x;
reg [9:0] pixel_y;
reg [8:0] source_x;
reg [7:0] source_y;
reg [4:0] horizontal_phase;
reg [1:0] vertical_repeat;
reg pixel_toggle;

(* async_reg = "true" *) reg swap_toggle_sync0;
(* async_reg = "true" *) reg swap_toggle_sync1;
reg swap_toggle_seen_pix;
reg swap_buffer_sync0;
reg swap_buffer_sync1;
reg swap_source_sync0;
reg swap_source_sync1;
reg swap_indexed_sync0;
reg swap_indexed_sync1;

wire active_video_now = pixel_x < H_ACTIVE && pixel_y < V_ACTIVE;
wire hsync_now = pixel_x >= H_ACTIVE + H_FRONT
    && pixel_x < H_ACTIVE + H_FRONT + H_SYNC;
wire vsync_now = pixel_y >= V_ACTIVE + V_FRONT
    && pixel_y < V_ACTIVE + V_FRONT + V_SYNC;
wire image_region_now = active_video_now;
wire vblank_start = pixel_x == 0 && pixel_y == V_ACTIVE;
assign vblank_pix = pixel_y >= V_ACTIVE;

wire [14:0] source_line_word_base = ({7'd0, source_y} << 7)
    + ({7'd0, source_y} << 5);
wire [14:0] source_word_address = source_line_word_base
    + {6'd0, source_x[8:1]};
assign frame_read_address = {active_internal_buffer_pix, source_word_address};

always @ (posedge clk_pix or negedge rst_n_pix) begin
    if (!rst_n_pix) begin
        swap_toggle_sync0 <= 1'b0;
        swap_toggle_sync1 <= 1'b0;
        swap_buffer_sync0 <= 1'b0;
        swap_buffer_sync1 <= 1'b0;
        swap_source_sync0 <= 1'b0;
        swap_source_sync1 <= 1'b0;
        swap_indexed_sync0 <= 1'b0;
        swap_indexed_sync1 <= 1'b0;
    end else begin
        swap_toggle_sync0 <= swap_toggle_sys;
        swap_toggle_sync1 <= swap_toggle_sync0;
        swap_buffer_sync0 <= swap_buffer_sys;
        swap_buffer_sync1 <= swap_buffer_sync0;
        swap_source_sync0 <= swap_source_sys;
        swap_source_sync1 <= swap_source_sync0;
        swap_indexed_sync0 <= swap_indexed_sys;
        swap_indexed_sync1 <= swap_indexed_sync0;
    end
end

always @ (posedge clk_pix or negedge rst_n_pix) begin
    if (!rst_n_pix) begin
        pixel_x <= 11'd0;
        pixel_y <= 10'd0;
        source_x <= 9'd0;
        source_y <= 8'd0;
        horizontal_phase <= 5'd0;
        vertical_repeat <= 2'd0;
        pixel_toggle <= 1'b0;
        swap_toggle_seen_pix <= 1'b0;
        swap_ack_pix <= 1'b0;
        active_internal_buffer_pix <= 1'b0;
        current_source_buffer_pix <= 1'b0;
        current_indexed_pix <= 1'b0;
        frame_valid_pix <= 1'b0;
        frame_count_pix <= 32'd0;
    end else begin
        pixel_toggle <= !pixel_toggle;

        if (vblank_start && swap_toggle_sync1 != swap_toggle_seen_pix) begin
            active_internal_buffer_pix <= swap_buffer_sync1;
            current_source_buffer_pix <= swap_source_sync1;
            current_indexed_pix <= swap_indexed_sync1;
            frame_valid_pix <= 1'b1;
            swap_toggle_seen_pix <= swap_toggle_sync1;
            swap_ack_pix <= swap_toggle_sync1;
        end

        if (pixel_x == H_TOTAL - 1) begin
            pixel_x <= 11'd0;
            source_x <= 9'd0;
            horizontal_phase <= 5'd0;

            if (pixel_y == V_TOTAL - 1) begin
                pixel_y <= 10'd0;
                source_y <= 8'd0;
                vertical_repeat <= 2'd0;
                frame_count_pix <= frame_count_pix + 1'b1;
            end else begin
                pixel_y <= pixel_y + 1'b1;
                if (pixel_y < V_ACTIVE - 1) begin
                    if (vertical_repeat == 2) begin
                        vertical_repeat <= 2'd0;
                        source_y <= source_y == SOURCE_HEIGHT - 1
                            ? 8'd0 : source_y + 1'b1;
                    end else begin
                        vertical_repeat <= vertical_repeat + 1'b1;
                    end
                end
            end
        end else begin
            pixel_x <= pixel_x + 1'b1;
            if (pixel_x < H_ACTIVE - 1) begin
                if (horizontal_phase + H_SCALE_NUMERATOR >=
                    H_SCALE_DENOMINATOR) begin
                    horizontal_phase <= horizontal_phase +
                        H_SCALE_NUMERATOR - H_SCALE_DENOMINATOR;
                    source_x <= source_x + 1'b1;
                end else begin
                    horizontal_phase <= horizontal_phase +
                        H_SCALE_NUMERATOR;
                end
            end
        end
    end
end

// ----------------------------------------------------------------------------
// Block-RAM read pipeline, indexed palette lookup, and RGB332 expansion

reg source_byte_select_stage1;
reg image_region_stage1;
reg frame_valid_stage1;
reg active_video_stage1;
reg hsync_stage1;
reg vsync_stage1;
reg indexed_stage1;
reg source_buffer_stage1;

wire [7:0] frame_pixel_stage1 = source_byte_select_stage1
    ? frame_read_data[15:8] : frame_read_data[7:0];
assign palette_read_address = {source_buffer_stage1, frame_pixel_stage1};

reg [7:0] frame_pixel_stage2;
reg image_region_stage2;
reg frame_valid_stage2;
reg active_video_stage2;
reg hsync_stage2;
reg vsync_stage2;
reg indexed_stage2;

always @ (posedge clk_pix or negedge rst_n_pix) begin
    if (!rst_n_pix) begin
        source_byte_select_stage1 <= 1'b0;
        image_region_stage1 <= 1'b0;
        frame_valid_stage1 <= 1'b0;
        active_video_stage1 <= 1'b0;
        hsync_stage1 <= 1'b0;
        vsync_stage1 <= 1'b0;
        indexed_stage1 <= 1'b0;
        source_buffer_stage1 <= 1'b0;
        frame_pixel_stage2 <= 8'd0;
        image_region_stage2 <= 1'b0;
        frame_valid_stage2 <= 1'b0;
        active_video_stage2 <= 1'b0;
        hsync_stage2 <= 1'b0;
        vsync_stage2 <= 1'b0;
        indexed_stage2 <= 1'b0;
    end else begin
        source_byte_select_stage1 <= source_x[0];
        image_region_stage1 <= image_region_now;
        frame_valid_stage1 <= frame_valid_pix;
        active_video_stage1 <= active_video_now;
        hsync_stage1 <= hsync_now;
        vsync_stage1 <= vsync_now;
        indexed_stage1 <= current_indexed_pix;
        source_buffer_stage1 <= current_source_buffer_pix;

        frame_pixel_stage2 <= frame_pixel_stage1;
        image_region_stage2 <= image_region_stage1;
        frame_valid_stage2 <= frame_valid_stage1;
        active_video_stage2 <= active_video_stage1;
        hsync_stage2 <= hsync_stage1;
        vsync_stage2 <= vsync_stage1;
        indexed_stage2 <= indexed_stage1;
    end
end

wire [7:0] display_pixel = indexed_stage2
    ? palette_read_data : frame_pixel_stage2;
wire [7:0] framebuffer_red = {
    display_pixel[7:5], display_pixel[7:5], display_pixel[7:6]
};
wire [7:0] framebuffer_green = {
    display_pixel[4:2], display_pixel[4:2], display_pixel[4:3]
};
wire [7:0] framebuffer_blue = {
    display_pixel[1:0], display_pixel[1:0], display_pixel[1:0], display_pixel[1:0]
};

reg [7:0] red;
reg [7:0] green;
reg [7:0] blue;

always @ (*) begin
    red = 8'h00;
    green = 8'h00;
    blue = 8'h00;

    if (active_video_stage2 && image_region_stage2 && frame_valid_stage2) begin
        red = framebuffer_red;
        green = framebuffer_green;
        blue = framebuffer_blue;
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
    .den   (active_video_stage2),
    .q     (tmds_red)
);

tmds_encode encode_green_u (
    .clk   (clk_pix),
    .rst_n (rst_n_pix),
    .c     (2'b00),
    .d     (green),
    .den   (active_video_stage2),
    .q     (tmds_green)
);

tmds_encode encode_blue_u (
    .clk   (clk_pix),
    .rst_n (rst_n_pix),
    .c     ({vsync_stage2, hsync_stage2}),
    .d     (blue),
    .den   (active_video_stage2),
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

ulx3s_tmds_ddr_serialiser serialise_red_u (
    .clk_tmds_x5 (clk_tmds_x5),
    .rst_n        (rst_n_tmds_x5),
    .load_symbol  (load_symbol),
    .symbol       (tmds_red),
    .serial_out   (gpdi_dp[2])
);

ulx3s_tmds_ddr_serialiser serialise_green_u (
    .clk_tmds_x5 (clk_tmds_x5),
    .rst_n        (rst_n_tmds_x5),
    .load_symbol  (load_symbol),
    .symbol       (tmds_green),
    .serial_out   (gpdi_dp[1])
);

ulx3s_tmds_ddr_serialiser serialise_blue_u (
    .clk_tmds_x5 (clk_tmds_x5),
    .rst_n        (rst_n_tmds_x5),
    .load_symbol  (load_symbol),
    .symbol       (tmds_blue),
    .serial_out   (gpdi_dp[0])
);

// LSB-first serialization of 10'b0000011111 generates a 50% duty-cycle TMDS
// clock at the 50 MHz pixel rate.
ulx3s_tmds_ddr_serialiser serialise_clock_u (
    .clk_tmds_x5 (clk_tmds_x5),
    .rst_n        (rst_n_tmds_x5),
    .load_symbol  (load_symbol),
    .symbol       (10'b0000011111),
    .serial_out   (gpdi_dp[3])
);

endmodule

// Two 320x200x8 displayed frames are stored as 64,000 16-bit words. Each
// DP16KD is configured as 1024x18; 64 banks therefore provide 65,536 words.
module ulx3s_frame_ram (
    input  wire        write_clk,
    input  wire        write_enable,
    input  wire [15:0] write_address,
    input  wire [15:0] write_data,
    input  wire        read_clk,
    input  wire [15:0] read_address,
    output reg  [15:0] read_data
);

wire [16*64-1:0] bank_read_data;
reg [5:0] read_bank_q;
integer mux_index;

always @ (posedge read_clk)
    read_bank_q <= read_address[15:10];

always @ (*) begin
    read_data = 16'd0;
    for (mux_index = 0; mux_index < 64; mux_index = mux_index + 1) begin
        if (read_bank_q == mux_index)
            read_data = bank_read_data[mux_index*16 +: 16];
    end
end

generate
genvar frame_bank;
for (frame_bank = 0; frame_bank < 64; frame_bank = frame_bank + 1) begin: frame_ram_bank
    localparam [5:0] BANK_NUMBER = frame_bank;
    wire bank_write_enable = write_enable
        && write_address[15:10] == BANK_NUMBER;

    ulx3s_dp16kd_1024x16 bank_u (
        .write_clk     (write_clk),
        .write_enable  (bank_write_enable),
        .write_address (write_address[9:0]),
        .write_data    (write_data),
        .read_clk      (read_clk),
        .read_address  (read_address[9:0]),
        .read_data     (bank_read_data[frame_bank*16 +: 16])
    );
end
endgenerate

endmodule

module ulx3s_palette_ram (
    input  wire       write_clk,
    input  wire       write_enable,
    input  wire [8:0] write_address,
    input  wire [7:0] write_data,
    input  wire       read_clk,
    input  wire [8:0] read_address,
    output wire [7:0] read_data
);

wire [8:0] read_data9;

DP16KD #(
    .DATA_WIDTH_A (9),
    .DATA_WIDTH_B (9),
    .REGMODE_A    ("NOREG"),
    .REGMODE_B    ("NOREG"),
    .WRITEMODE_A  ("NORMAL"),
    .WRITEMODE_B  ("NORMAL"),
    .RESETMODE    ("SYNC"),
    .CSDECODE_A   ("0b000"),
    .CSDECODE_B   ("0b000")
) palette_ebr_u (
    .DIA17 (1'b0), .DIA16 (1'b0), .DIA15 (1'b0), .DIA14 (1'b0),
    .DIA13 (1'b0), .DIA12 (1'b0), .DIA11 (1'b0), .DIA10 (1'b0),
    .DIA9  (1'b0), .DIA8  (1'b0), .DIA7  (write_data[7]),
    .DIA6  (write_data[6]), .DIA5 (write_data[5]), .DIA4 (write_data[4]),
    .DIA3  (write_data[3]), .DIA2 (write_data[2]), .DIA1 (write_data[1]),
    .DIA0  (write_data[0]),
    .ADA13 (1'b0), .ADA12 (1'b0), .ADA11 (write_address[8]),
    .ADA10 (write_address[7]), .ADA9 (write_address[6]),
    .ADA8  (write_address[5]), .ADA7 (write_address[4]),
    .ADA6  (write_address[3]), .ADA5 (write_address[2]),
    .ADA4  (write_address[1]), .ADA3 (write_address[0]),
    .ADA2  (1'b0), .ADA1 (1'b0), .ADA0 (1'b0),
    .CEA   (1'b1), .OCEA (1'b1), .CLKA (write_clk), .WEA (write_enable),
    .CSA2  (1'b0), .CSA1 (1'b0), .CSA0 (1'b0), .RSTA (1'b0),

    .DIB17 (1'b0), .DIB16 (1'b0), .DIB15 (1'b0), .DIB14 (1'b0),
    .DIB13 (1'b0), .DIB12 (1'b0), .DIB11 (1'b0), .DIB10 (1'b0),
    .DIB9  (1'b0), .DIB8  (1'b0), .DIB7 (1'b0), .DIB6 (1'b0),
    .DIB5  (1'b0), .DIB4 (1'b0), .DIB3 (1'b0), .DIB2 (1'b0),
    .DIB1  (1'b0), .DIB0 (1'b0),
    .ADB13 (1'b0), .ADB12 (1'b0), .ADB11 (read_address[8]),
    .ADB10 (read_address[7]), .ADB9 (read_address[6]),
    .ADB8  (read_address[5]), .ADB7 (read_address[4]),
    .ADB6  (read_address[3]), .ADB5 (read_address[2]),
    .ADB4  (read_address[1]), .ADB3 (read_address[0]),
    .ADB2  (1'b0), .ADB1 (1'b0), .ADB0 (1'b0),
    .CEB   (1'b1), .OCEB (1'b1), .CLKB (read_clk), .WEB (1'b0),
    .CSB2  (1'b0), .CSB1 (1'b0), .CSB0 (1'b0), .RSTB (1'b0),

    .DOA17 (), .DOA16 (), .DOA15 (), .DOA14 (), .DOA13 (), .DOA12 (),
    .DOA11 (), .DOA10 (), .DOA9 (), .DOA8 (), .DOA7 (), .DOA6 (),
    .DOA5 (), .DOA4 (), .DOA3 (), .DOA2 (), .DOA1 (), .DOA0 (),
    .DOB17 (), .DOB16 (), .DOB15 (), .DOB14 (), .DOB13 (), .DOB12 (),
    .DOB11 (), .DOB10 (), .DOB9 (), .DOB8 (read_data9[8]),
    .DOB7 (read_data9[7]), .DOB6 (read_data9[6]), .DOB5 (read_data9[5]),
    .DOB4 (read_data9[4]), .DOB3 (read_data9[3]), .DOB2 (read_data9[2]),
    .DOB1 (read_data9[1]), .DOB0 (read_data9[0])
);

assign read_data = read_data9[7:0];

endmodule

module ulx3s_dp16kd_1024x16 (
    input  wire        write_clk,
    input  wire        write_enable,
    input  wire [9:0]  write_address,
    input  wire [15:0] write_data,
    input  wire        read_clk,
    input  wire [9:0]  read_address,
    output wire [15:0] read_data
);

DP16KD #(
    .DATA_WIDTH_A (18),
    .DATA_WIDTH_B (18),
    .REGMODE_A    ("NOREG"),
    .REGMODE_B    ("NOREG"),
    .WRITEMODE_A  ("NORMAL"),
    .WRITEMODE_B  ("NORMAL"),
    .RESETMODE    ("SYNC"),
    .CSDECODE_A   ("0b000"),
    .CSDECODE_B   ("0b000")
) frame_ebr_u (
    .DIA17 (1'b0), .DIA16 (1'b0), .DIA15 (write_data[15]),
    .DIA14 (write_data[14]), .DIA13 (write_data[13]),
    .DIA12 (write_data[12]), .DIA11 (write_data[11]),
    .DIA10 (write_data[10]), .DIA9 (write_data[9]),
    .DIA8  (write_data[8]), .DIA7 (write_data[7]),
    .DIA6  (write_data[6]), .DIA5 (write_data[5]),
    .DIA4  (write_data[4]), .DIA3 (write_data[3]),
    .DIA2  (write_data[2]), .DIA1 (write_data[1]),
    .DIA0  (write_data[0]),
    .ADA13 (write_address[9]), .ADA12 (write_address[8]),
    .ADA11 (write_address[7]), .ADA10 (write_address[6]),
    .ADA9  (write_address[5]), .ADA8 (write_address[4]),
    .ADA7  (write_address[3]), .ADA6 (write_address[2]),
    .ADA5  (write_address[1]), .ADA4 (write_address[0]),
    .ADA3  (1'b0), .ADA2 (1'b0), .ADA1 (1'b1), .ADA0 (1'b1),
    .CEA   (1'b1), .OCEA (1'b1), .CLKA (write_clk), .WEA (write_enable),
    .CSA2  (1'b0), .CSA1 (1'b0), .CSA0 (1'b0), .RSTA (1'b0),

    .DIB17 (1'b0), .DIB16 (1'b0), .DIB15 (1'b0), .DIB14 (1'b0),
    .DIB13 (1'b0), .DIB12 (1'b0), .DIB11 (1'b0), .DIB10 (1'b0),
    .DIB9  (1'b0), .DIB8 (1'b0), .DIB7 (1'b0), .DIB6 (1'b0),
    .DIB5  (1'b0), .DIB4 (1'b0), .DIB3 (1'b0), .DIB2 (1'b0),
    .DIB1  (1'b0), .DIB0 (1'b0),
    .ADB13 (read_address[9]), .ADB12 (read_address[8]),
    .ADB11 (read_address[7]), .ADB10 (read_address[6]),
    .ADB9  (read_address[5]), .ADB8 (read_address[4]),
    .ADB7  (read_address[3]), .ADB6 (read_address[2]),
    .ADB5  (read_address[1]), .ADB4 (read_address[0]),
    .ADB3  (1'b0), .ADB2 (1'b0), .ADB1 (1'b0), .ADB0 (1'b0),
    .CEB   (1'b1), .OCEB (1'b1), .CLKB (read_clk), .WEB (1'b0),
    .CSB2  (1'b0), .CSB1 (1'b0), .CSB0 (1'b0), .RSTB (1'b0),

    .DOA17 (), .DOA16 (), .DOA15 (), .DOA14 (), .DOA13 (), .DOA12 (),
    .DOA11 (), .DOA10 (), .DOA9 (), .DOA8 (), .DOA7 (), .DOA6 (),
    .DOA5 (), .DOA4 (), .DOA3 (), .DOA2 (), .DOA1 (), .DOA0 (),
    .DOB17 (), .DOB16 (), .DOB15 (read_data[15]),
    .DOB14 (read_data[14]), .DOB13 (read_data[13]),
    .DOB12 (read_data[12]), .DOB11 (read_data[11]),
    .DOB10 (read_data[10]), .DOB9 (read_data[9]),
    .DOB8 (read_data[8]), .DOB7 (read_data[7]),
    .DOB6 (read_data[6]), .DOB5 (read_data[5]),
    .DOB4 (read_data[4]), .DOB3 (read_data[3]),
    .DOB2 (read_data[2]), .DOB1 (read_data[1]),
    .DOB0 (read_data[0])
);

endmodule

`ifndef YOSYS
`default_nettype wire
`endif
