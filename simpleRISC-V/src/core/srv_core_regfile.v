// ============================================================================
// Project     : simpleRISC-V
// Module      : srv_core_regfile
// Description : Integer register file for RV32I core.
// ============================================================================

`include "core_defines.vh"

module srv_core_regfile #(
    parameter XLEN       = `SRV_CORE_XLEN,
    parameter REG_ADDR_W = `SRV_CORE_REG_ADDR_W
) (
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire [REG_ADDR_W-1:0]   rd_addr_0_i,
    output wire [XLEN-1:0]         rd_data_0_o,
    input  wire [REG_ADDR_W-1:0]   rd_addr_1_i,
    output wire [XLEN-1:0]         rd_data_1_o,
    input  wire                    wr_en_i,
    input  wire [REG_ADDR_W-1:0]   wr_addr_i,
    input  wire [XLEN-1:0]         wr_data_i
);

    localparam integer NUM_GPRS = (1 << REG_ADDR_W);

    reg [XLEN-1:0] gpr [0:NUM_GPRS-1];

    integer idx;

    assign rd_data_0_o = (rd_addr_0_i == {REG_ADDR_W{1'b0}}) ? {XLEN{1'b0}}
                                                             : gpr[rd_addr_0_i];
    assign rd_data_1_o = (rd_addr_1_i == {REG_ADDR_W{1'b0}}) ? {XLEN{1'b0}}
                                                             : gpr[rd_addr_1_i];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (idx = 0; idx < NUM_GPRS; idx = idx + 1) begin
                gpr[idx] <= {XLEN{1'b0}};
            end
        end else if (wr_en_i && (wr_addr_i != {REG_ADDR_W{1'b0}})) begin
            gpr[wr_addr_i] <= wr_data_i;
        end
    end

endmodule
