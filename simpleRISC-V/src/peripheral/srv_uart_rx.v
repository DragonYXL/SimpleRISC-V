// ============================================================================
// Project     : simpleRISC-V
// Module      : srv_uart_rx
// Description : UART receiver.
// ============================================================================

`include "peripheral_defines.vh"

module srv_uart_rx #(
    parameter DATA_W  = `SRV_UART_DATA_W,
    parameter DIVISOR = `SRV_UART_DIVISOR,
    parameter DIV_W   = `SRV_UART_DIV_W
) (
    input  wire               clk,
    input  wire               rst_n,
    output wire               rx_busy,
    output reg                rx_done,
    output reg  [DATA_W-1:0]  rx_data,
    input  wire               rx_i
);

    localparam [DIV_W-1:0] HALF_DIVISOR = DIVISOR >> 1;

    reg                      state;
    reg [DIV_W-1:0]          div_cnt;
    reg [3:0]                bit_cnt;
    reg [DATA_W-1:0]         shifter;

    assign rx_busy = (state == `SRV_UART_RX_BUSY);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state   <= `SRV_UART_RX_IDLE;
            div_cnt <= {DIV_W{1'b0}};
            bit_cnt <= 4'd0;
            shifter <= {DATA_W{1'b0}};
            rx_done <= 1'b0;
            rx_data <= {DATA_W{1'b0}};
        end else begin
            rx_done <= 1'b0;

            case (state)
                `SRV_UART_RX_IDLE: begin
                    if (rx_i == `SRV_UART_START_BIT) begin
                        state   <= `SRV_UART_RX_BUSY;
                        div_cnt <= DIVISOR + HALF_DIVISOR - 1'b1;
                        bit_cnt <= 4'd0;
                    end
                end
                `SRV_UART_RX_BUSY: begin
                    if (div_cnt != {DIV_W{1'b0}}) begin
                        div_cnt <= div_cnt - 1'b1;
                    end else begin
                        div_cnt <= DIVISOR - 1'b1;
                        if (bit_cnt < DATA_W) begin
                            shifter <= {rx_i, shifter[DATA_W-1:1]};
                            bit_cnt <= bit_cnt + 1'b1;
                        end else begin
                            state <= `SRV_UART_RX_IDLE;
                            if (rx_i == `SRV_UART_STOP_BIT) begin
                                rx_data <= shifter;
                                rx_done <= 1'b1;
                            end
                        end
                    end
                end
                default: begin
                    state <= `SRV_UART_RX_IDLE;
                end
            endcase
        end
    end

endmodule
