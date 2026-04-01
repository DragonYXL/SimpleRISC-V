// ============================================================================
// Project     : simpleRISC-V
// Module      : srv_core_alu
// Description : Integer ALU for the SimpleRISC-V RV32 core.
// ============================================================================

`include "core_defines.vh"

module srv_core_alu #(
    parameter XLEN = `SRV_CORE_XLEN
) (
    input  wire [`SRV_CORE_ALU_OP_W-1:0] op_i,
    input  wire [XLEN-1:0]               operand_a_i,
    input  wire [XLEN-1:0]               operand_b_i,
    output reg  [XLEN-1:0]               result_o
);

    always @(*) begin
        case (op_i)
            `SRV_CORE_ALU_OP_ADD : result_o = operand_a_i + operand_b_i;
            `SRV_CORE_ALU_OP_SUB : result_o = operand_a_i - operand_b_i;
            `SRV_CORE_ALU_OP_SLL : result_o = operand_a_i << operand_b_i[4:0];
            `SRV_CORE_ALU_OP_SLT : result_o = {{(XLEN-1){1'b0}}, ($signed(operand_a_i) < $signed(operand_b_i))};
            `SRV_CORE_ALU_OP_SLTU: result_o = {{(XLEN-1){1'b0}}, ($unsigned(operand_a_i) < $unsigned(operand_b_i))};
            `SRV_CORE_ALU_OP_XOR : result_o = operand_a_i ^ operand_b_i;
            `SRV_CORE_ALU_OP_SRL : result_o = operand_a_i >> operand_b_i[4:0];
            `SRV_CORE_ALU_OP_SRA : result_o = $signed(operand_a_i) >>> operand_b_i[4:0];
            `SRV_CORE_ALU_OP_OR  : result_o = operand_a_i | operand_b_i;
            `SRV_CORE_ALU_OP_AND : result_o = operand_a_i & operand_b_i;
            `SRV_CORE_ALU_OP_PASS: result_o = operand_b_i;
            default              : result_o = {XLEN{1'b0}};
        endcase
    end

endmodule
