// ============================================================================
// Project     : simpleRISC-V
// Module      : srv_uart_ctrl
// Description : UART bus control and register block.
// ============================================================================

`include "peripheral_defines.vh"

module srv_uart_ctrl #(
    parameter ADDR_W = `SRV_PERIPH_ADDR_W,
    parameter DATA_W = `SRV_PERIPH_DATA_W
) (
    input  wire                     clk,
    input  wire                     rst_n,
    input  wire                     cs_n,
    input  wire                     as_n,
    input  wire                     rw,
    input  wire [ADDR_W-1:0]        addr,
    input  wire [DATA_W-1:0]        wr_data,
    output reg  [DATA_W-1:0]        rd_data,
    output reg                      rdy_n,
    output reg                      irq_rx_o,
    output reg                      irq_tx_o,
    input  wire                     rx_busy,
    input  wire                     rx_done,
    input  wire [`SRV_UART_DATA_W-1:0] rx_data,
    input  wire                     tx_busy,
    input  wire                     tx_done,
    output reg                      tx_start,
    output reg  [`SRV_UART_DATA_W-1:0] tx_data
);

    localparam integer REG_ADDR_W = `SRV_UART_REG_ADDR_W;
    localparam integer ADDR_LSB   = `SRV_PERIPH_ADDR_ALIGN_LSB;

    reg [`SRV_UART_DATA_W-1:0] rx_buf;

    wire access_valid;
    wire [REG_ADDR_W-1:0] reg_addr;

    assign access_valid = (cs_n == `SRV_PERIPH_ACTIVE_N) &&
                          (as_n == `SRV_PERIPH_ACTIVE_N);
    assign reg_addr     = addr[ADDR_LSB + REG_ADDR_W - 1:ADDR_LSB];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_data   <= {DATA_W{1'b0}};
            rdy_n     <= `SRV_PERIPH_INACTIVE_N;
            irq_rx_o  <= 1'b0;
            irq_tx_o  <= 1'b0;
            rx_buf    <= {`SRV_UART_DATA_W{1'b0}};
            tx_start  <= 1'b0;
            tx_data   <= {`SRV_UART_DATA_W{1'b0}};
        end else begin
            rdy_n    <= access_valid ? `SRV_PERIPH_ACTIVE_N : `SRV_PERIPH_INACTIVE_N;
            rd_data  <= {DATA_W{1'b0}};
            tx_start <= 1'b0;
            tx_data  <= {`SRV_UART_DATA_W{1'b0}};

            if (rx_done) begin
                irq_rx_o <= 1'b1;
                rx_buf   <= rx_data;
            end

            if (tx_done) begin
                irq_tx_o <= 1'b1;
            end

            if (access_valid && (rw == `SRV_PERIPH_READ)) begin
                case (reg_addr)
                    `SRV_UART_REG_STATUS: begin
                        rd_data[`SRV_UART_STATUS_IRQ_RX_BIT]  <= irq_rx_o;
                        rd_data[`SRV_UART_STATUS_IRQ_TX_BIT]  <= irq_tx_o;
                        rd_data[`SRV_UART_STATUS_RX_BUSY_BIT] <= rx_busy;
                        rd_data[`SRV_UART_STATUS_TX_BUSY_BIT] <= tx_busy;
                    end
                    `SRV_UART_REG_DATA: begin
                        rd_data[`SRV_UART_DATA_W-1:0] <= rx_buf;
                    end
                    default: begin
                        rd_data <= {DATA_W{1'b0}};
                    end
                endcase
            end

            if (access_valid && (rw == `SRV_PERIPH_WRITE)) begin
                case (reg_addr)
                    `SRV_UART_REG_STATUS: begin
                        irq_rx_o <= wr_data[`SRV_UART_STATUS_IRQ_RX_BIT];
                        irq_tx_o <= wr_data[`SRV_UART_STATUS_IRQ_TX_BIT];
                    end
                    `SRV_UART_REG_DATA: begin
                        if (!tx_busy) begin
                            tx_start <= 1'b1;
                            tx_data  <= wr_data[`SRV_UART_DATA_W-1:0];
                        end
                    end
                    default: begin
                    end
                endcase
            end
        end
    end

endmodule
