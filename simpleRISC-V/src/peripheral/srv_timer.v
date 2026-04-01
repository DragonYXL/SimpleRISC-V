// ============================================================================
// Project     : simpleRISC-V
// Module      : srv_timer
// Description : Timer peripheral with one-shot and periodic modes.
// ============================================================================

`include "peripheral_defines.vh"

module srv_timer #(
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
    output reg  [DATA_W-1:0]    rd_data,
    output reg                  rdy_n,
    output reg                  irq_o
);

    localparam integer REG_ADDR_W = `SRV_TIMER_REG_ADDR_W;
    localparam integer ADDR_LSB   = `SRV_PERIPH_ADDR_ALIGN_LSB;

    reg timer_enable;
    reg timer_periodic;
    reg [DATA_W-1:0] compare_value;
    reg [DATA_W-1:0] count_value;

    wire access_valid;
    wire [REG_ADDR_W-1:0] reg_addr;
    wire match_event;

    assign access_valid = (cs_n == `SRV_PERIPH_ACTIVE_N) &&
                          (as_n == `SRV_PERIPH_ACTIVE_N);
    assign reg_addr     = addr[ADDR_LSB + REG_ADDR_W - 1:ADDR_LSB];
    assign match_event  = timer_enable && (count_value == compare_value);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_data        <= {DATA_W{1'b0}};
            rdy_n          <= `SRV_PERIPH_INACTIVE_N;
            irq_o          <= 1'b0;
            timer_enable   <= 1'b0;
            timer_periodic <= 1'b0;
            compare_value  <= {DATA_W{1'b0}};
            count_value    <= {DATA_W{1'b0}};
        end else begin
            rdy_n   <= access_valid ? `SRV_PERIPH_ACTIVE_N : `SRV_PERIPH_INACTIVE_N;
            rd_data <= {DATA_W{1'b0}};

            if (access_valid && (rw == `SRV_PERIPH_READ)) begin
                case (reg_addr)
                    `SRV_TIMER_REG_CTRL: begin
                        rd_data <= {{(DATA_W - 2){1'b0}}, timer_periodic, timer_enable};
                    end
                    `SRV_TIMER_REG_IRQ: begin
                        rd_data <= {{(DATA_W - 1){1'b0}}, irq_o};
                    end
                    `SRV_TIMER_REG_COMPARE: begin
                        rd_data <= compare_value;
                    end
                    `SRV_TIMER_REG_COUNT: begin
                        rd_data <= count_value;
                    end
                    default: begin
                        rd_data <= {DATA_W{1'b0}};
                    end
                endcase
            end

            if (access_valid && (rw == `SRV_PERIPH_WRITE)) begin
                case (reg_addr)
                    `SRV_TIMER_REG_CTRL: begin
                        timer_enable   <= wr_data[`SRV_TIMER_CTRL_EN_BIT];
                        timer_periodic <= wr_data[`SRV_TIMER_CTRL_PERIODIC_BIT];
                    end
                    `SRV_TIMER_REG_IRQ: begin
                        irq_o <= wr_data[`SRV_TIMER_IRQ_BIT];
                    end
                    `SRV_TIMER_REG_COMPARE: begin
                        compare_value <= wr_data;
                    end
                    `SRV_TIMER_REG_COUNT: begin
                        count_value <= wr_data;
                    end
                    default: begin
                    end
                endcase
            end else if (match_event) begin
                irq_o <= 1'b1;
                if (timer_periodic) begin
                    count_value <= {DATA_W{1'b0}};
                end else begin
                    timer_enable <= 1'b0;
                end
            end else if (timer_enable) begin
                count_value <= count_value + {{(DATA_W - 1){1'b0}}, 1'b1};
            end
        end
    end

endmodule
