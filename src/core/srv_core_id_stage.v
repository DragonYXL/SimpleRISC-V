// ============================================================================
// Project     : simpleRISC-V
// Module      : srv_core_id_stage
// Description : Decode stage operand bundle. The module keeps the top-level
//               wiring aligned with the classic IF/ID/EX/MEM split.
// ============================================================================

`include "core_defines.vh"

module srv_core_id_stage #(
    parameter XLEN     = `SRV_CORE_XLEN,
    parameter ADDR_W   = `SRV_CORE_ADDR_W,
    parameter REG_W    = `SRV_CORE_REG_ADDR_W
) (
    input  wire [ADDR_W-1:0]    pc_i,
    input  wire [6:0]           opcode_i,
    input  wire [2:0]           funct3_i,
    input  wire [6:0]           funct7_i,
    input  wire [REG_W-1:0]     rs1_addr_i,
    input  wire [REG_W-1:0]     rs2_addr_i,
    input  wire [REG_W-1:0]     rd_addr_i,
    input  wire [REG_W-1:0]     shamt_i,
    input  wire [XLEN-1:0]      rs1_data_i,
    input  wire [XLEN-1:0]      rs2_data_i,
    input  wire [XLEN-1:0]      imm_i_i,
    input  wire [XLEN-1:0]      imm_s_i,
    input  wire [XLEN-1:0]      imm_b_i,
    input  wire [XLEN-1:0]      imm_u_i,
    input  wire [XLEN-1:0]      imm_j_i,
    output wire [ADDR_W-1:0]    pc_o,
    output wire [6:0]           opcode_o,
    output wire [2:0]           funct3_o,
    output wire [6:0]           funct7_o,
    output wire [REG_W-1:0]     rs1_addr_o,
    output wire [REG_W-1:0]     rs2_addr_o,
    output wire [REG_W-1:0]     rd_addr_o,
    output wire [REG_W-1:0]     shamt_o,
    output wire [XLEN-1:0]      rs1_data_o,
    output wire [XLEN-1:0]      rs2_data_o,
    output wire [XLEN-1:0]      imm_i_o,
    output wire [XLEN-1:0]      imm_s_o,
    output wire [XLEN-1:0]      imm_b_o,
    output wire [XLEN-1:0]      imm_u_o,
    output wire [XLEN-1:0]      imm_j_o
);

    assign pc_o       = pc_i;
    assign opcode_o   = opcode_i;
    assign funct3_o   = funct3_i;
    assign funct7_o   = funct7_i;
    assign rs1_addr_o = rs1_addr_i;
    assign rs2_addr_o = rs2_addr_i;
    assign rd_addr_o  = rd_addr_i;
    assign shamt_o    = shamt_i;
    assign rs1_data_o = rs1_data_i;
    assign rs2_data_o = rs2_data_i;
    assign imm_i_o    = imm_i_i;
    assign imm_s_o    = imm_s_i;
    assign imm_b_o    = imm_b_i;
    assign imm_u_o    = imm_u_i;
    assign imm_j_o    = imm_j_i;

endmodule
