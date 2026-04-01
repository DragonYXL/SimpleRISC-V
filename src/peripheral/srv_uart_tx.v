// ============================================================================
// Project     : simpleRISC-V
// Module      : srv_uart_tx
// Description : UART transmitter.
// ============================================================================

`include "peripheral_defines.vh"

module srv_uart_tx #(
    parameter DATA_W  = `SRV_UART_DATA_W,
    parameter DIVISOR = `SRV_UART_DIVISOR,
    parameter DIV_W   = `SRV_UART_DIV_W
) (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               tx_start,
    input  wire [DATA_W-1:0]  tx_data,
    output wire               tx_busy,
    output reg                tx_done,
    output reg                tx_o
);

    reg                       state;
    reg [DIV_W-1:0]           div_cnt;
    reg [3:0]                 bit_cnt;
    reg [DATA_W-1:0]          shifter;

    assign tx_busy = (state == `SRV_UART_TX_BUSY);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state   <= `SRV_UART_TX_IDLE;
            div_cnt <= {DIV_W{1'b0}};
            bit_cnt <= 4'd0;
            shifter <= {DATA_W{1'b0}};
            tx_done <= 1'b0;
            tx_o    <= `SRV_UART_STOP_BIT;
        end else begin
            tx_done <= 1'b0;

            case (state)
                `SRV_UART_TX_IDLE: begin
                    tx_o <= `SRV_UART_STOP_BIT;
                    if (tx_start) begin
                        state   <= `SRV_UART_TX_BUSY;
                        div_cnt <= DIVISOR - 1'b1;
                        bit_cnt <= 4'd0;
                        shifter <= tx_data;
                        tx_o    <= `SRV_UART_START_BIT;
                    end
                end
                `SRV_UART_TX_BUSY: begin
                    if (div_cnt != {DIV_W{1'b0}}) begin
                        div_cnt <= div_cnt - 1'b1;
                    end else begin
                        div_cnt <= DIVISOR - 1'b1;
                        if (bit_cnt < DATA_W) begin
                            tx_o    <= shifter[0];
                            shifter <= {{1'b0}, shifter[DATA_W-1:1]};
                            bit_cnt <= bit_cnt + 1'b1;
                        end else if (bit_cnt == DATA_W) begin
                            tx_o    <= `SRV_UART_STOP_BIT;
                            bit_cnt <= bit_cnt + 1'b1;
                        end else begin
                            state   <= `SRV_UART_TX_IDLE;
                            tx_done <= 1'b1;
                            tx_o    <= `SRV_UART_STOP_BIT;
                        end
                    end
                end
                default: begin
                    state <= `SRV_UART_TX_IDLE;
                end
            endcase
        end
    end

endmodule
