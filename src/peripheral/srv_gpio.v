// ============================================================================
// Project     : simpleRISC-V
// Module      : srv_gpio
// Description : GPIO peripheral with bus slave interface.
//               Uses separate input/output/output-enable signals for GPIO IOs.
// ============================================================================

`include "peripheral_defines.vh"

module srv_gpio #(
    parameter ADDR_W     = `SRV_PERIPH_ADDR_W,
    parameter DATA_W     = `SRV_PERIPH_DATA_W,
    parameter GPIO_IN_W  = `SRV_GPIO_IN_W,
    parameter GPIO_OUT_W = `SRV_GPIO_OUT_W,
    parameter GPIO_IO_W  = `SRV_GPIO_IO_W
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
    input  wire [GPIO_IN_W-1:0]     gpio_in_i,
    output reg  [GPIO_OUT_W-1:0]    gpio_out_o,
    input  wire [GPIO_IO_W-1:0]     gpio_io_i,
    output reg  [GPIO_IO_W-1:0]     gpio_io_o,
    output reg  [GPIO_IO_W-1:0]     gpio_io_oe_o
);

    localparam integer REG_ADDR_W = `SRV_GPIO_REG_ADDR_W;
    localparam integer ADDR_LSB   = `SRV_PERIPH_ADDR_ALIGN_LSB;

    wire access_valid;
    wire [REG_ADDR_W-1:0] reg_addr;

    assign access_valid = (cs_n == `SRV_PERIPH_ACTIVE_N) &&
                          (as_n == `SRV_PERIPH_ACTIVE_N);
    assign reg_addr     = addr[ADDR_LSB + REG_ADDR_W - 1:ADDR_LSB];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_data      <= {DATA_W{1'b0}};
            rdy_n        <= `SRV_PERIPH_INACTIVE_N;
            gpio_out_o   <= {GPIO_OUT_W{1'b0}};
            gpio_io_o    <= {GPIO_IO_W{1'b0}};
            gpio_io_oe_o <= {GPIO_IO_W{1'b0}};
        end else begin
            rdy_n   <= access_valid ? `SRV_PERIPH_ACTIVE_N : `SRV_PERIPH_INACTIVE_N;
            rd_data <= {DATA_W{1'b0}};

            if (access_valid && (rw == `SRV_PERIPH_READ)) begin
                case (reg_addr)
                    `SRV_GPIO_REG_IN_DATA: begin
                        rd_data <= {{(DATA_W - GPIO_IN_W){1'b0}}, gpio_in_i};
                    end
                    `SRV_GPIO_REG_OUT_DATA: begin
                        rd_data <= {{(DATA_W - GPIO_OUT_W){1'b0}}, gpio_out_o};
                    end
                    `SRV_GPIO_REG_IO_DATA: begin
                        rd_data <= {{(DATA_W - GPIO_IO_W){1'b0}}, gpio_io_i};
                    end
                    `SRV_GPIO_REG_IO_OE: begin
                        rd_data <= {{(DATA_W - GPIO_IO_W){1'b0}}, gpio_io_oe_o};
                    end
                    default: begin
                        rd_data <= {DATA_W{1'b0}};
                    end
                endcase
            end

            if (access_valid && (rw == `SRV_PERIPH_WRITE)) begin
                case (reg_addr)
                    `SRV_GPIO_REG_OUT_DATA: begin
                        gpio_out_o <= wr_data[GPIO_OUT_W-1:0];
                    end
                    `SRV_GPIO_REG_IO_DATA: begin
                        gpio_io_o <= wr_data[GPIO_IO_W-1:0];
                    end
                    `SRV_GPIO_REG_IO_OE: begin
                        gpio_io_oe_o <= wr_data[GPIO_IO_W-1:0];
                    end
                    default: begin
                    end
                endcase
            end
        end
    end

endmodule
