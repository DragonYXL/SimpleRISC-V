// ============================================================================
// Project     : simpleRISC-V
// Module      : srv_uart
// Description : UART peripheral with bus slave interface.
// ============================================================================

`include "peripheral_defines.vh"

module srv_uart #(
    parameter ADDR_W = `SRV_PERIPH_ADDR_W,
    parameter DATA_W = `SRV_PERIPH_DATA_W
) (
    input  wire                 clk,
    input  wire                 rst_n,
    input  wire                 cs_n,
    input  wire                 as_n,
    input  wire                 rw,
    input  wire [ADDR_W-1:0]    addr,
    input  wire [DATA_W-1:0]    wr_data,
    output wire [DATA_W-1:0]    rd_data,
    output wire                 rdy_n,
    output wire                 irq_rx_o,
    output wire                 irq_tx_o,
    input  wire                 uart_rx_i,
    output wire                 uart_tx_o
);

    wire                        rx_busy;
    wire                        rx_done;
    wire [`SRV_UART_DATA_W-1:0] rx_data;
    wire                        tx_busy;
    wire                        tx_done;
    wire                        tx_start;
    wire [`SRV_UART_DATA_W-1:0] tx_data;

    srv_uart_ctrl #(
        .ADDR_W (ADDR_W),
        .DATA_W (DATA_W)
    ) u_uart_ctrl (
        .clk      (clk),
        .rst_n    (rst_n),
        .cs_n     (cs_n),
        .as_n     (as_n),
        .rw       (rw),
        .addr     (addr),
        .wr_data  (wr_data),
        .rd_data  (rd_data),
        .rdy_n    (rdy_n),
        .irq_rx_o (irq_rx_o),
        .irq_tx_o (irq_tx_o),
        .rx_busy  (rx_busy),
        .rx_done  (rx_done),
        .rx_data  (rx_data),
        .tx_busy  (tx_busy),
        .tx_done  (tx_done),
        .tx_start (tx_start),
        .tx_data  (tx_data)
    );

    srv_uart_tx u_uart_tx (
        .clk      (clk),
        .rst_n    (rst_n),
        .tx_start (tx_start),
        .tx_data  (tx_data),
        .tx_busy  (tx_busy),
        .tx_done  (tx_done),
        .tx_o     (uart_tx_o)
    );

    srv_uart_rx u_uart_rx (
        .clk      (clk),
        .rst_n    (rst_n),
        .rx_busy  (rx_busy),
        .rx_done  (rx_done),
        .rx_data  (rx_data),
        .rx_i     (uart_rx_i)
    );

endmodule
