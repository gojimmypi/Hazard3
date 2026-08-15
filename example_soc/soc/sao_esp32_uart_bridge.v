/*****************************************************************************\
|                        Copyright (C) 2026 gojimmypi                        |
|                     SPDX-License-Identifier: Apache-2.0                    |
\*****************************************************************************/

// ESP32 sideband access to the SAO I2C bus. The ESP32 sends complete I2C
// operations over the ULX3S GPIO16/GPIO17 UART pair; the FPGA remains the
// only electrical I2C master connected to the SAO header.

`default_nettype none

module sao_esp32_uart_bridge #(
    parameter integer CLK_HZ = 50000000,
    parameter integer BAUD   = 115200
) (
    input  wire clk,
    input  wire rst_n,

    input  wire uart_rx,
    output wire uart_tx,
    output wire uart_tx_oe,

    output reg  bus_request,
    input  wire bus_grant,

    input  wire sao_sda_i,
    input  wire sao_scl_i,
    output wire sao_sda_drive_low,
    output wire sao_scl_drive_low
);

localparam [7:0] REQ_SYNC0 = 8'ha5;
localparam [7:0] REQ_SYNC1 = 8'h5a;
localparam [7:0] RSP_SYNC0 = 8'h5a;
localparam [7:0] RSP_SYNC1 = 8'ha5;

localparam [7:0] ESP_CMD_INFO    = 8'h01;
localparam [7:0] ESP_CMD_RECOVER = 8'h02;
localparam [7:0] ESP_CMD_PROBE   = 8'h03;
localparam [7:0] ESP_CMD_READ8   = 8'h04;
localparam [7:0] ESP_CMD_WRITE8  = 8'h05;

localparam [7:0] ESP_STATUS_OK        = 8'h00;
localparam [7:0] ESP_STATUS_NACK      = 8'h01;
localparam [7:0] ESP_STATUS_TIMEOUT   = 8'h02;
localparam [7:0] ESP_STATUS_BUSY      = 8'h03;
localparam [7:0] ESP_STATUS_BAD_CMD   = 8'h04;
localparam [7:0] ESP_STATUS_BAD_FRAME = 8'h05;

localparam [2:0] I2C_CMD_START     = 3'd1;
localparam [2:0] I2C_CMD_STOP      = 3'd2;
localparam [2:0] I2C_CMD_WRITE     = 3'd3;
localparam [2:0] I2C_CMD_READ_NACK = 3'd5;
localparam [2:0] I2C_CMD_RECOVER   = 3'd6;
localparam [2:0] I2C_CMD_ABORT     = 3'd7;

localparam [15:0] I2C_CLK_DIV = CLK_HZ / 200000;
localparam [31:0] I2C_TIMEOUT = CLK_HZ / 100; // 10 ms
localparam [31:0] GRANT_TIMEOUT = CLK_HZ / 10; // 100 ms

localparam [3:0] OP_IDLE         = 4'd0;
localparam [3:0] OP_WAIT_GRANT   = 4'd1;
localparam [3:0] OP_WAIT_RECOVER = 4'd2;
localparam [3:0] OP_WAIT_START1  = 4'd3;
localparam [3:0] OP_WAIT_ADDR_W  = 4'd4;
localparam [3:0] OP_WAIT_REG     = 4'd5;
localparam [3:0] OP_WAIT_VALUE   = 4'd6;
localparam [3:0] OP_WAIT_START2  = 4'd7;
localparam [3:0] OP_WAIT_ADDR_R  = 4'd8;
localparam [3:0] OP_WAIT_READ    = 4'd9;
localparam [3:0] OP_WAIT_STOP    = 4'd10;
localparam [3:0] OP_WAIT_ABORT   = 4'd11;

wire       uart_rx_valid;
wire [7:0] uart_rx_data;
wire       uart_tx_ready;
wire       uart_tx_valid;
wire [7:0] uart_tx_data;

reg [2:0] parser_index;
reg [7:0] parser_xor;
reg [7:0] parser_cmd;
reg [7:0] parser_addr;
reg [7:0] parser_reg;
reg [7:0] parser_value;

reg       response_start;
reg [7:0] response_status_next;
reg [7:0] response_cmd_next;
reg [7:0] response_addr_next;
reg [7:0] response_value_next;

reg       response_sending;
reg [2:0] response_index;
reg [7:0] response_status;
reg [7:0] response_cmd;
reg [7:0] response_addr;
reg [7:0] response_value;

reg [3:0] op_state;
reg [7:0] op_cmd;
reg [6:0] op_addr;
reg [7:0] op_reg;
reg [7:0] op_value;
reg [7:0] op_result;
reg [31:0] grant_timer;

reg        i2c_cmd_valid;
reg [2:0]  i2c_cmd;
reg [7:0]  i2c_tx_data;
wire       i2c_busy;
wire       i2c_done;
wire       i2c_ack;
wire       i2c_timeout;
wire       i2c_bus_active;
wire [7:0] i2c_rx_data;

reg sda_meta;
reg sda_sync;
reg scl_meta;
reg scl_sync;

wire [7:0] response_checksum =
    RSP_SYNC0 ^ RSP_SYNC1 ^ response_status ^ response_cmd ^
    response_addr ^ response_value;

// Keep the board-level FPGA -> ESP32 UART pad tri-stated unless a response
// frame is actually being sent. Keep OE asserted while the UART PHY is busy
// with the final byte after response_sending drops. The LPF pull-up provides
// the idle-high level between response frames.
assign uart_tx_oe = response_sending || !uart_tx_ready;
assign uart_tx_valid = response_sending;
assign uart_tx_data =
    response_index == 3'd0 ? RSP_SYNC0 :
    response_index == 3'd1 ? RSP_SYNC1 :
    response_index == 3'd2 ? response_status :
    response_index == 3'd3 ? response_cmd :
    response_index == 3'd4 ? response_addr :
    response_index == 3'd5 ? response_value :
                             response_checksum;

sao_uart_phy #(
    .CLK_HZ (CLK_HZ),
    .BAUD   (BAUD)
) uart_u (
    .clk      (clk),
    .rst_n    (rst_n),
    .rx_i     (uart_rx),
    .tx_o     (uart_tx),
    .rx_valid (uart_rx_valid),
    .rx_data  (uart_rx_data),
    .tx_valid (uart_tx_valid),
    .tx_data  (uart_tx_data),
    .tx_ready (uart_tx_ready)
);

sao_i2c_engine i2c_u (
    .clk            (clk),
    .rst_n          (rst_n),
    .cmd_valid      (i2c_cmd_valid),
    .cmd            (i2c_cmd),
    .tx_data        (i2c_tx_data),
    .clk_div        (I2C_CLK_DIV),
    .timeout_cycles (I2C_TIMEOUT),
    .sda_i          (sda_sync),
    .scl_i          (scl_sync),
    .sda_drive_low  (sao_sda_drive_low),
    .scl_drive_low  (sao_scl_drive_low),
    .busy           (i2c_busy),
    .done           (i2c_done),
    .ack            (i2c_ack),
    .timeout        (i2c_timeout),
    .bus_active     (i2c_bus_active),
    .rx_data        (i2c_rx_data)
);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        sda_meta <= 1'b1;
        sda_sync <= 1'b1;
        scl_meta <= 1'b1;
        scl_sync <= 1'b1;
    end else begin
        sda_meta <= sao_sda_i;
        sda_sync <= sda_meta;
        scl_meta <= sao_scl_i;
        scl_sync <= scl_meta;
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        response_sending <= 1'b0;
        response_index   <= 3'd0;
        response_status  <= ESP_STATUS_OK;
        response_cmd     <= 8'd0;
        response_addr    <= 8'd0;
        response_value   <= 8'd0;
    end else if (response_start && !response_sending) begin
        response_sending <= 1'b1;
        response_index   <= 3'd0;
        response_status  <= response_status_next;
        response_cmd     <= response_cmd_next;
        response_addr    <= response_addr_next;
        response_value   <= response_value_next;
    end else if (response_sending && uart_tx_ready) begin
        if (response_index == 3'd6) begin
            response_sending <= 1'b0;
            response_index   <= 3'd0;
        end else begin
            response_index <= response_index + 1'b1;
        end
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        parser_index         <= 3'd0;
        parser_xor           <= 8'd0;
        parser_cmd           <= 8'd0;
        parser_addr          <= 8'd0;
        parser_reg           <= 8'd0;
        parser_value         <= 8'd0;
        response_start       <= 1'b0;
        response_status_next <= ESP_STATUS_OK;
        response_cmd_next    <= 8'd0;
        response_addr_next   <= 8'd0;
        response_value_next  <= 8'd0;
        bus_request          <= 1'b0;
        op_state             <= OP_IDLE;
        op_cmd               <= 8'd0;
        op_addr              <= 7'd0;
        op_reg               <= 8'd0;
        op_value             <= 8'd0;
        op_result            <= ESP_STATUS_OK;
        grant_timer          <= 32'd0;
        i2c_cmd_valid        <= 1'b0;
        i2c_cmd              <= 3'd0;
        i2c_tx_data          <= 8'd0;
    end else begin
        response_start <= 1'b0;
        i2c_cmd_valid  <= 1'b0;

        if (uart_rx_valid && !response_sending && op_state == OP_IDLE) begin
            case (parser_index)
                3'd0: begin
                    if (uart_rx_data == REQ_SYNC0) begin
                        parser_xor   <= REQ_SYNC0;
                        parser_index <= 3'd1;
                    end
                end
                3'd1: begin
                    if (uart_rx_data == REQ_SYNC1) begin
                        parser_xor   <= parser_xor ^ uart_rx_data;
                        parser_index <= 3'd2;
                    end else begin
                        parser_index <= 3'd0;
                    end
                end
                3'd2: begin
                    parser_cmd   <= uart_rx_data;
                    parser_xor   <= parser_xor ^ uart_rx_data;
                    parser_index <= 3'd3;
                end
                3'd3: begin
                    parser_addr  <= uart_rx_data;
                    parser_xor   <= parser_xor ^ uart_rx_data;
                    parser_index <= 3'd4;
                end
                3'd4: begin
                    parser_reg   <= uart_rx_data;
                    parser_xor   <= parser_xor ^ uart_rx_data;
                    parser_index <= 3'd5;
                end
                3'd5: begin
                    parser_value <= uart_rx_data;
                    parser_xor   <= parser_xor ^ uart_rx_data;
                    parser_index <= 3'd6;
                end
                3'd6: begin
                    parser_index <= 3'd0;

                    if (uart_rx_data != parser_xor) begin
                        if (op_state == OP_IDLE) begin
                            response_status_next <= ESP_STATUS_BAD_FRAME;
                            response_cmd_next    <= parser_cmd;
                            response_addr_next   <= parser_addr;
                            response_value_next  <= 8'd0;
                            response_start       <= 1'b1;
                        end
                    end else if (parser_cmd == ESP_CMD_INFO) begin
                        response_status_next <= ESP_STATUS_OK;
                        response_cmd_next    <= parser_cmd;
                        response_addr_next   <= parser_addr;
                        response_value_next  <= 8'h21; // protocol 2.1
                        response_start       <= 1'b1;
                    end else if (
                        (parser_cmd == ESP_CMD_PROBE ||
                         parser_cmd == ESP_CMD_READ8 ||
                         parser_cmd == ESP_CMD_WRITE8) &&
                        parser_addr[7]
                    ) begin
                        response_status_next <= ESP_STATUS_BAD_FRAME;
                        response_cmd_next    <= parser_cmd;
                        response_addr_next   <= parser_addr;
                        response_value_next  <= 8'd0;
                        response_start       <= 1'b1;
                    end else if (
                        parser_cmd == ESP_CMD_RECOVER ||
                        parser_cmd == ESP_CMD_PROBE ||
                        parser_cmd == ESP_CMD_READ8 ||
                        parser_cmd == ESP_CMD_WRITE8
                    ) begin
                        op_cmd      <= parser_cmd;
                        op_addr     <= parser_addr[6:0];
                        op_reg      <= parser_reg;
                        op_value    <= parser_value;
                        op_result   <= ESP_STATUS_OK;
                        grant_timer <= 32'd0;
                        bus_request <= 1'b1;
                        op_state    <= OP_WAIT_GRANT;
                    end else begin
                        response_status_next <= ESP_STATUS_BAD_CMD;
                        response_cmd_next    <= parser_cmd;
                        response_addr_next   <= parser_addr;
                        response_value_next  <= 8'd0;
                        response_start       <= 1'b1;
                    end
                end
                default: parser_index <= 3'd0;
            endcase
        end

        case (op_state)
            OP_IDLE: begin
            end

            OP_WAIT_GRANT: begin
                if (bus_grant) begin
                    grant_timer <= 32'd0;
                    if (op_cmd == ESP_CMD_RECOVER) begin
                        i2c_cmd       <= I2C_CMD_RECOVER;
                        i2c_cmd_valid <= 1'b1;
                        op_state      <= OP_WAIT_RECOVER;
                    end else begin
                        i2c_cmd       <= I2C_CMD_START;
                        i2c_cmd_valid <= 1'b1;
                        op_state      <= OP_WAIT_START1;
                    end
                end else if (grant_timer >= GRANT_TIMEOUT - 1'b1) begin
                    bus_request          <= 1'b0;
                    response_status_next <= ESP_STATUS_BUSY;
                    response_cmd_next    <= op_cmd;
                    response_addr_next   <= {1'b0, op_addr};
                    response_value_next  <= 8'd0;
                    response_start       <= 1'b1;
                    op_state             <= OP_IDLE;
                end else begin
                    grant_timer <= grant_timer + 1'b1;
                end
            end

            OP_WAIT_RECOVER: begin
                if (i2c_done) begin
                    bus_request          <= 1'b0;
                    response_status_next <= i2c_timeout || !sda_sync || !scl_sync
                        ? ESP_STATUS_TIMEOUT : ESP_STATUS_OK;
                    response_cmd_next    <= op_cmd;
                    response_addr_next   <= {1'b0, op_addr};
                    response_value_next  <= 8'd0;
                    response_start       <= 1'b1;
                    op_state             <= OP_IDLE;
                end
            end

            OP_WAIT_START1: begin
                if (i2c_done) begin
                    if (i2c_timeout) begin
                        op_result     <= ESP_STATUS_TIMEOUT;
                        i2c_cmd       <= I2C_CMD_ABORT;
                        i2c_cmd_valid <= 1'b1;
                        op_state      <= OP_WAIT_ABORT;
                    end else begin
                        i2c_tx_data   <= {op_addr, 1'b0};
                        i2c_cmd       <= I2C_CMD_WRITE;
                        i2c_cmd_valid <= 1'b1;
                        op_state      <= OP_WAIT_ADDR_W;
                    end
                end
            end

            OP_WAIT_ADDR_W: begin
                if (i2c_done) begin
                    if (i2c_timeout) begin
                        op_result     <= ESP_STATUS_TIMEOUT;
                        i2c_cmd       <= I2C_CMD_ABORT;
                        i2c_cmd_valid <= 1'b1;
                        op_state      <= OP_WAIT_ABORT;
                    end else if (!i2c_ack) begin
                        op_result     <= ESP_STATUS_NACK;
                        i2c_cmd       <= I2C_CMD_STOP;
                        i2c_cmd_valid <= 1'b1;
                        op_state      <= OP_WAIT_STOP;
                    end else if (op_cmd == ESP_CMD_PROBE) begin
                        op_result     <= ESP_STATUS_OK;
                        i2c_cmd       <= I2C_CMD_STOP;
                        i2c_cmd_valid <= 1'b1;
                        op_state      <= OP_WAIT_STOP;
                    end else begin
                        i2c_tx_data   <= op_reg;
                        i2c_cmd       <= I2C_CMD_WRITE;
                        i2c_cmd_valid <= 1'b1;
                        op_state      <= OP_WAIT_REG;
                    end
                end
            end

            OP_WAIT_REG: begin
                if (i2c_done) begin
                    if (i2c_timeout) begin
                        op_result     <= ESP_STATUS_TIMEOUT;
                        i2c_cmd       <= I2C_CMD_ABORT;
                        i2c_cmd_valid <= 1'b1;
                        op_state      <= OP_WAIT_ABORT;
                    end else if (!i2c_ack) begin
                        op_result     <= ESP_STATUS_NACK;
                        i2c_cmd       <= I2C_CMD_STOP;
                        i2c_cmd_valid <= 1'b1;
                        op_state      <= OP_WAIT_STOP;
                    end else if (op_cmd == ESP_CMD_WRITE8) begin
                        i2c_tx_data   <= op_value;
                        i2c_cmd       <= I2C_CMD_WRITE;
                        i2c_cmd_valid <= 1'b1;
                        op_state      <= OP_WAIT_VALUE;
                    end else begin
                        i2c_cmd       <= I2C_CMD_START;
                        i2c_cmd_valid <= 1'b1;
                        op_state      <= OP_WAIT_START2;
                    end
                end
            end

            OP_WAIT_VALUE: begin
                if (i2c_done) begin
                    op_result     <= i2c_timeout ? ESP_STATUS_TIMEOUT :
                                     i2c_ack ? ESP_STATUS_OK : ESP_STATUS_NACK;
                    i2c_cmd       <= i2c_timeout ? I2C_CMD_ABORT : I2C_CMD_STOP;
                    i2c_cmd_valid <= 1'b1;
                    op_state      <= i2c_timeout ? OP_WAIT_ABORT : OP_WAIT_STOP;
                end
            end

            OP_WAIT_START2: begin
                if (i2c_done) begin
                    if (i2c_timeout) begin
                        op_result     <= ESP_STATUS_TIMEOUT;
                        i2c_cmd       <= I2C_CMD_ABORT;
                        i2c_cmd_valid <= 1'b1;
                        op_state      <= OP_WAIT_ABORT;
                    end else begin
                        i2c_tx_data   <= {op_addr, 1'b1};
                        i2c_cmd       <= I2C_CMD_WRITE;
                        i2c_cmd_valid <= 1'b1;
                        op_state      <= OP_WAIT_ADDR_R;
                    end
                end
            end

            OP_WAIT_ADDR_R: begin
                if (i2c_done) begin
                    if (i2c_timeout) begin
                        op_result     <= ESP_STATUS_TIMEOUT;
                        i2c_cmd       <= I2C_CMD_ABORT;
                        i2c_cmd_valid <= 1'b1;
                        op_state      <= OP_WAIT_ABORT;
                    end else if (!i2c_ack) begin
                        op_result     <= ESP_STATUS_NACK;
                        i2c_cmd       <= I2C_CMD_STOP;
                        i2c_cmd_valid <= 1'b1;
                        op_state      <= OP_WAIT_STOP;
                    end else begin
                        i2c_cmd       <= I2C_CMD_READ_NACK;
                        i2c_cmd_valid <= 1'b1;
                        op_state      <= OP_WAIT_READ;
                    end
                end
            end

            OP_WAIT_READ: begin
                if (i2c_done) begin
                    if (i2c_timeout) begin
                        op_result     <= ESP_STATUS_TIMEOUT;
                        i2c_cmd       <= I2C_CMD_ABORT;
                        i2c_cmd_valid <= 1'b1;
                        op_state      <= OP_WAIT_ABORT;
                    end else begin
                        op_value      <= i2c_rx_data;
                        op_result     <= ESP_STATUS_OK;
                        i2c_cmd       <= I2C_CMD_STOP;
                        i2c_cmd_valid <= 1'b1;
                        op_state      <= OP_WAIT_STOP;
                    end
                end
            end

            OP_WAIT_STOP: begin
                if (i2c_done) begin
                    bus_request          <= 1'b0;
                    response_status_next <= i2c_timeout ? ESP_STATUS_TIMEOUT : op_result;
                    response_cmd_next    <= op_cmd;
                    response_addr_next   <= {1'b0, op_addr};
                    response_value_next  <= op_cmd == ESP_CMD_READ8 ? op_value :
                                            op_cmd == ESP_CMD_WRITE8 ? op_value :
                                            op_result == ESP_STATUS_OK ? 8'h01 : 8'h00;
                    response_start       <= 1'b1;
                    op_state             <= OP_IDLE;
                end
            end

            OP_WAIT_ABORT: begin
                if (i2c_done) begin
                    bus_request          <= 1'b0;
                    response_status_next <= op_result;
                    response_cmd_next    <= op_cmd;
                    response_addr_next   <= {1'b0, op_addr};
                    response_value_next  <= 8'd0;
                    response_start       <= 1'b1;
                    op_state             <= OP_IDLE;
                end
            end

            default: begin
                bus_request <= 1'b0;
                op_state    <= OP_IDLE;
            end
        endcase
    end
end

// Keep otherwise intentionally-unused engine status visible to synthesis.
wire _unused = &{1'b0, i2c_busy, i2c_bus_active};

endmodule

`default_nettype wire
