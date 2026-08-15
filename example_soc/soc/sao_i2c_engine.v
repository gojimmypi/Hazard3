/*****************************************************************************\
|                        Copyright (C) 2026 gojimmypi                        |
|                     SPDX-License-Identifier: Apache-2.0                    |
\*****************************************************************************/

// Low-level I2C command engine for the SAO bridge. SDA and SCL outputs are
// open-drain controls: a 1 on *_drive_low means drive the external line low;
// a 0 means release it. The board-level wrapper supplies the tri-state I/O.

`default_nettype none

module sao_i2c_engine (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        cmd_valid,
    input  wire [2:0]  cmd,
    input  wire [7:0]  tx_data,
    input  wire [15:0] clk_div,
    input  wire [31:0] timeout_cycles,

    input  wire        sda_i,
    input  wire        scl_i,
    output reg         sda_drive_low,
    output reg         scl_drive_low,

    output reg         busy,
    output reg         done,
    output reg         ack,
    output reg         timeout,
    output reg         bus_active,
    output reg  [7:0]  rx_data
);

localparam [2:0] CMD_START     = 3'd1;
localparam [2:0] CMD_STOP      = 3'd2;
localparam [2:0] CMD_WRITE     = 3'd3;
localparam [2:0] CMD_READ_ACK  = 3'd4;
localparam [2:0] CMD_READ_NACK = 3'd5;
localparam [2:0] CMD_RECOVER   = 3'd6;
localparam [2:0] CMD_ABORT     = 3'd7;

localparam [5:0] ST_IDLE                   = 6'd0;
localparam [5:0] ST_START_WAIT_HIGH        = 6'd1;
localparam [5:0] ST_START_HIGH_HOLD        = 6'd2;
localparam [5:0] ST_START_SDA_LOW          = 6'd3;
localparam [5:0] ST_STOP_LOW               = 6'd4;
localparam [5:0] ST_STOP_WAIT_HIGH         = 6'd5;
localparam [5:0] ST_STOP_HIGH_HOLD         = 6'd6;
localparam [5:0] ST_STOP_RELEASE           = 6'd7;
localparam [5:0] ST_WRITE_LOW              = 6'd8;
localparam [5:0] ST_WRITE_WAIT_HIGH        = 6'd9;
localparam [5:0] ST_WRITE_HIGH             = 6'd10;
localparam [5:0] ST_WRITE_ACK_LOW          = 6'd11;
localparam [5:0] ST_WRITE_ACK_WAIT_HIGH    = 6'd12;
localparam [5:0] ST_WRITE_ACK_HIGH         = 6'd13;
localparam [5:0] ST_READ_LOW               = 6'd14;
localparam [5:0] ST_READ_WAIT_HIGH         = 6'd15;
localparam [5:0] ST_READ_HIGH              = 6'd16;
localparam [5:0] ST_READ_ACK_LOW           = 6'd17;
localparam [5:0] ST_READ_ACK_WAIT_HIGH     = 6'd18;
localparam [5:0] ST_READ_ACK_HIGH          = 6'd19;
localparam [5:0] ST_RECOVER_LOW            = 6'd20;
localparam [5:0] ST_RECOVER_WAIT_HIGH      = 6'd21;
localparam [5:0] ST_RECOVER_HIGH           = 6'd22;
localparam [5:0] ST_RECOVER_STOP_LOW       = 6'd23;
localparam [5:0] ST_RECOVER_STOP_WAIT_HIGH = 6'd24;
localparam [5:0] ST_RECOVER_STOP_HIGH      = 6'd25;
localparam [5:0] ST_RECOVER_STOP_RELEASE   = 6'd26;

reg [5:0] state;
reg [15:0] phase_timer;
reg [31:0] stretch_timer;
reg [7:0] rx_shift;
reg [2:0] bit_index;
reg [3:0] recover_pulses;
reg read_send_ack;

wire [15:0] phase_reload = (clk_div > 16'd1) ? (clk_div - 16'd1) : 16'd0;
wire timeout_enabled = |timeout_cycles;
wire stretch_expired = timeout_enabled && stretch_timer >= timeout_cycles - 1'b1;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state          <= ST_IDLE;
        phase_timer    <= 16'd0;
        stretch_timer  <= 32'd0;
        rx_shift       <= 8'd0;
        bit_index      <= 3'd0;
        recover_pulses <= 4'd0;
        read_send_ack  <= 1'b0;
        sda_drive_low  <= 1'b0;
        scl_drive_low  <= 1'b0;
        busy           <= 1'b0;
        done           <= 1'b0;
        ack            <= 1'b0;
        timeout        <= 1'b0;
        bus_active     <= 1'b0;
        rx_data        <= 8'd0;
    end else begin
        done <= 1'b0;

        if (busy && cmd_valid && cmd == CMD_ABORT) begin
            state         <= ST_IDLE;
            phase_timer   <= 16'd0;
            stretch_timer <= 32'd0;
            sda_drive_low <= 1'b0;
            scl_drive_low <= 1'b0;
            busy          <= 1'b0;
            done          <= 1'b1;
            timeout       <= 1'b0;
            bus_active    <= 1'b0;
        end else begin
            case (state)
                ST_IDLE: begin
                    busy <= 1'b0;
                    if (cmd_valid) begin
                        ack           <= 1'b0;
                        timeout       <= 1'b0;
                        stretch_timer <= 32'd0;
                        phase_timer   <= phase_reload;
                        case (cmd)
                            CMD_START: begin
                                busy          <= 1'b1;
                                sda_drive_low <= 1'b0;
                                scl_drive_low <= 1'b0;
                                state         <= ST_START_WAIT_HIGH;
                            end
                            CMD_STOP: begin
                                busy          <= 1'b1;
                                sda_drive_low <= 1'b1;
                                scl_drive_low <= 1'b1;
                                state         <= ST_STOP_LOW;
                            end
                            CMD_WRITE: begin
                                busy          <= 1'b1;
                                bit_index     <= 3'd7;
                                sda_drive_low <= ~tx_data[7];
                                scl_drive_low <= 1'b1;
                                state         <= ST_WRITE_LOW;
                            end
                            CMD_READ_ACK,
                            CMD_READ_NACK: begin
                                busy          <= 1'b1;
                                rx_shift      <= 8'd0;
                                bit_index     <= 3'd7;
                                read_send_ack <= cmd == CMD_READ_ACK;
                                sda_drive_low <= 1'b0;
                                scl_drive_low <= 1'b1;
                                state         <= ST_READ_LOW;
                            end
                            CMD_RECOVER: begin
                                busy           <= 1'b1;
                                bus_active     <= 1'b0;
                                recover_pulses <= 4'd0;
                                sda_drive_low  <= 1'b0;
                                scl_drive_low  <= 1'b1;
                                state          <= ST_RECOVER_LOW;
                            end
                            CMD_ABORT: begin
                                sda_drive_low <= 1'b0;
                                scl_drive_low <= 1'b0;
                                bus_active    <= 1'b0;
                                done          <= 1'b1;
                            end
                            default: begin
                                done <= 1'b1;
                            end
                        endcase
                    end
                end

                ST_START_WAIT_HIGH: begin
                    if (scl_i && sda_i) begin
                        stretch_timer <= 32'd0;
                        phase_timer   <= phase_reload;
                        state         <= ST_START_HIGH_HOLD;
                    end else if (stretch_expired) begin
                        timeout       <= 1'b1;
                        busy          <= 1'b0;
                        done          <= 1'b1;
                        bus_active    <= 1'b0;
                        sda_drive_low <= 1'b0;
                        scl_drive_low <= 1'b0;
                        state         <= ST_IDLE;
                    end else begin
                        stretch_timer <= stretch_timer + 1'b1;
                    end
                end

                ST_START_HIGH_HOLD: begin
                    if (|phase_timer) begin
                        phase_timer <= phase_timer - 1'b1;
                    end else begin
                        sda_drive_low <= 1'b1;
                        phase_timer   <= phase_reload;
                        state         <= ST_START_SDA_LOW;
                    end
                end

                ST_START_SDA_LOW: begin
                    if (|phase_timer) begin
                        phase_timer <= phase_timer - 1'b1;
                    end else begin
                        scl_drive_low <= 1'b1;
                        bus_active    <= 1'b1;
                        busy          <= 1'b0;
                        done          <= 1'b1;
                        state         <= ST_IDLE;
                    end
                end

                ST_STOP_LOW: begin
                    if (|phase_timer) begin
                        phase_timer <= phase_timer - 1'b1;
                    end else begin
                        scl_drive_low <= 1'b0;
                        stretch_timer <= 32'd0;
                        state         <= ST_STOP_WAIT_HIGH;
                    end
                end

                ST_STOP_WAIT_HIGH: begin
                    if (scl_i) begin
                        stretch_timer <= 32'd0;
                        phase_timer   <= phase_reload;
                        state         <= ST_STOP_HIGH_HOLD;
                    end else if (stretch_expired) begin
                        timeout       <= 1'b1;
                        busy          <= 1'b0;
                        done          <= 1'b1;
                        bus_active    <= 1'b0;
                        sda_drive_low <= 1'b0;
                        scl_drive_low <= 1'b0;
                        state         <= ST_IDLE;
                    end else begin
                        stretch_timer <= stretch_timer + 1'b1;
                    end
                end

                ST_STOP_HIGH_HOLD: begin
                    if (|phase_timer) begin
                        phase_timer <= phase_timer - 1'b1;
                    end else begin
                        sda_drive_low <= 1'b0;
                        phase_timer   <= phase_reload;
                        state         <= ST_STOP_RELEASE;
                    end
                end

                ST_STOP_RELEASE: begin
                    if (|phase_timer) begin
                        phase_timer <= phase_timer - 1'b1;
                    end else begin
                        bus_active <= 1'b0;
                        busy       <= 1'b0;
                        done       <= 1'b1;
                        state      <= ST_IDLE;
                    end
                end

                ST_WRITE_LOW: begin
                    if (|phase_timer) begin
                        phase_timer <= phase_timer - 1'b1;
                    end else begin
                        scl_drive_low <= 1'b0;
                        stretch_timer <= 32'd0;
                        state         <= ST_WRITE_WAIT_HIGH;
                    end
                end

                ST_WRITE_WAIT_HIGH: begin
                    if (scl_i) begin
                        stretch_timer <= 32'd0;
                        phase_timer   <= phase_reload;
                        state         <= ST_WRITE_HIGH;
                    end else if (stretch_expired) begin
                        timeout       <= 1'b1;
                        busy          <= 1'b0;
                        done          <= 1'b1;
                        bus_active    <= 1'b0;
                        sda_drive_low <= 1'b0;
                        scl_drive_low <= 1'b0;
                        state         <= ST_IDLE;
                    end else begin
                        stretch_timer <= stretch_timer + 1'b1;
                    end
                end

                ST_WRITE_HIGH: begin
                    if (|phase_timer) begin
                        phase_timer <= phase_timer - 1'b1;
                    end else begin
                        scl_drive_low <= 1'b1;
                        phase_timer   <= phase_reload;
                        if (bit_index == 3'd0) begin
                            sda_drive_low <= 1'b0;
                            state         <= ST_WRITE_ACK_LOW;
                        end else begin
                            bit_index     <= bit_index - 1'b1;
                            sda_drive_low <= ~tx_data[bit_index - 1'b1];
                            state         <= ST_WRITE_LOW;
                        end
                    end
                end

                ST_WRITE_ACK_LOW: begin
                    if (|phase_timer) begin
                        phase_timer <= phase_timer - 1'b1;
                    end else begin
                        scl_drive_low <= 1'b0;
                        stretch_timer <= 32'd0;
                        state         <= ST_WRITE_ACK_WAIT_HIGH;
                    end
                end

                ST_WRITE_ACK_WAIT_HIGH: begin
                    if (scl_i) begin
                        stretch_timer <= 32'd0;
                        phase_timer   <= phase_reload;
                        state         <= ST_WRITE_ACK_HIGH;
                    end else if (stretch_expired) begin
                        timeout       <= 1'b1;
                        busy          <= 1'b0;
                        done          <= 1'b1;
                        bus_active    <= 1'b0;
                        sda_drive_low <= 1'b0;
                        scl_drive_low <= 1'b0;
                        state         <= ST_IDLE;
                    end else begin
                        stretch_timer <= stretch_timer + 1'b1;
                    end
                end

                ST_WRITE_ACK_HIGH: begin
                    if (|phase_timer) begin
                        phase_timer <= phase_timer - 1'b1;
                    end else begin
                        ack           <= ~sda_i;
                        scl_drive_low <= 1'b1;
                        busy          <= 1'b0;
                        done          <= 1'b1;
                        state         <= ST_IDLE;
                    end
                end

                ST_READ_LOW: begin
                    if (|phase_timer) begin
                        phase_timer <= phase_timer - 1'b1;
                    end else begin
                        scl_drive_low <= 1'b0;
                        stretch_timer <= 32'd0;
                        state         <= ST_READ_WAIT_HIGH;
                    end
                end

                ST_READ_WAIT_HIGH: begin
                    if (scl_i) begin
                        stretch_timer <= 32'd0;
                        phase_timer   <= phase_reload;
                        state         <= ST_READ_HIGH;
                    end else if (stretch_expired) begin
                        timeout       <= 1'b1;
                        busy          <= 1'b0;
                        done          <= 1'b1;
                        bus_active    <= 1'b0;
                        sda_drive_low <= 1'b0;
                        scl_drive_low <= 1'b0;
                        state         <= ST_IDLE;
                    end else begin
                        stretch_timer <= stretch_timer + 1'b1;
                    end
                end

                ST_READ_HIGH: begin
                    if (|phase_timer) begin
                        phase_timer <= phase_timer - 1'b1;
                    end else begin
                        rx_shift      <= {rx_shift[6:0], sda_i};
                        scl_drive_low <= 1'b1;
                        phase_timer   <= phase_reload;
                        if (bit_index == 3'd0) begin
                            sda_drive_low <= read_send_ack;
                            state         <= ST_READ_ACK_LOW;
                        end else begin
                            bit_index <= bit_index - 1'b1;
                            state     <= ST_READ_LOW;
                        end
                    end
                end

                ST_READ_ACK_LOW: begin
                    if (|phase_timer) begin
                        phase_timer <= phase_timer - 1'b1;
                    end else begin
                        scl_drive_low <= 1'b0;
                        stretch_timer <= 32'd0;
                        state         <= ST_READ_ACK_WAIT_HIGH;
                    end
                end

                ST_READ_ACK_WAIT_HIGH: begin
                    if (scl_i) begin
                        stretch_timer <= 32'd0;
                        phase_timer   <= phase_reload;
                        state         <= ST_READ_ACK_HIGH;
                    end else if (stretch_expired) begin
                        timeout       <= 1'b1;
                        busy          <= 1'b0;
                        done          <= 1'b1;
                        bus_active    <= 1'b0;
                        sda_drive_low <= 1'b0;
                        scl_drive_low <= 1'b0;
                        state         <= ST_IDLE;
                    end else begin
                        stretch_timer <= stretch_timer + 1'b1;
                    end
                end

                ST_READ_ACK_HIGH: begin
                    if (|phase_timer) begin
                        phase_timer <= phase_timer - 1'b1;
                    end else begin
                        scl_drive_low <= 1'b1;
                        sda_drive_low <= 1'b0;
                        rx_data       <= rx_shift;
                        busy          <= 1'b0;
                        done          <= 1'b1;
                        state         <= ST_IDLE;
                    end
                end

                ST_RECOVER_LOW: begin
                    if (|phase_timer) begin
                        phase_timer <= phase_timer - 1'b1;
                    end else begin
                        scl_drive_low <= 1'b0;
                        stretch_timer <= 32'd0;
                        state         <= ST_RECOVER_WAIT_HIGH;
                    end
                end

                ST_RECOVER_WAIT_HIGH: begin
                    if (scl_i) begin
                        stretch_timer <= 32'd0;
                        phase_timer   <= phase_reload;
                        state         <= ST_RECOVER_HIGH;
                    end else if (stretch_expired) begin
                        timeout       <= 1'b1;
                        busy          <= 1'b0;
                        done          <= 1'b1;
                        sda_drive_low <= 1'b0;
                        scl_drive_low <= 1'b0;
                        state         <= ST_IDLE;
                    end else begin
                        stretch_timer <= stretch_timer + 1'b1;
                    end
                end

                ST_RECOVER_HIGH: begin
                    if (|phase_timer) begin
                        phase_timer <= phase_timer - 1'b1;
                    end else if (sda_i || recover_pulses == 4'd8) begin
                        scl_drive_low <= 1'b1;
                        sda_drive_low <= 1'b1;
                        phase_timer   <= phase_reload;
                        state         <= ST_RECOVER_STOP_LOW;
                    end else begin
                        recover_pulses <= recover_pulses + 1'b1;
                        scl_drive_low  <= 1'b1;
                        phase_timer    <= phase_reload;
                        state          <= ST_RECOVER_LOW;
                    end
                end

                ST_RECOVER_STOP_LOW: begin
                    if (|phase_timer) begin
                        phase_timer <= phase_timer - 1'b1;
                    end else begin
                        scl_drive_low <= 1'b0;
                        stretch_timer <= 32'd0;
                        state         <= ST_RECOVER_STOP_WAIT_HIGH;
                    end
                end

                ST_RECOVER_STOP_WAIT_HIGH: begin
                    if (scl_i) begin
                        stretch_timer <= 32'd0;
                        phase_timer   <= phase_reload;
                        state         <= ST_RECOVER_STOP_HIGH;
                    end else if (stretch_expired) begin
                        timeout       <= 1'b1;
                        busy          <= 1'b0;
                        done          <= 1'b1;
                        sda_drive_low <= 1'b0;
                        scl_drive_low <= 1'b0;
                        state         <= ST_IDLE;
                    end else begin
                        stretch_timer <= stretch_timer + 1'b1;
                    end
                end

                ST_RECOVER_STOP_HIGH: begin
                    if (|phase_timer) begin
                        phase_timer <= phase_timer - 1'b1;
                    end else begin
                        sda_drive_low <= 1'b0;
                        phase_timer   <= phase_reload;
                        state         <= ST_RECOVER_STOP_RELEASE;
                    end
                end

                ST_RECOVER_STOP_RELEASE: begin
                    if (|phase_timer) begin
                        phase_timer <= phase_timer - 1'b1;
                    end else begin
                        bus_active <= 1'b0;
                        busy       <= 1'b0;
                        done       <= 1'b1;
                        state      <= ST_IDLE;
                    end
                end

                default: begin
                    state         <= ST_IDLE;
                    sda_drive_low <= 1'b0;
                    scl_drive_low <= 1'b0;
                    busy          <= 1'b0;
                    done          <= 1'b1;
                    timeout       <= 1'b1;
                    bus_active    <= 1'b0;
                end
            endcase
        end
    end
end

endmodule

`default_nettype wire
