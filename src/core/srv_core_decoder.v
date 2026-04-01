// ============================================================================
// Project     : simpleRISC-V
// Module      : srv_core_decoder
// Description : RV32 instruction field and immediate decoder.
// ============================================================================

`include "core_defines.vh"

module srv_core_decoder #(
    parameter XLEN = `SRV_CORE_XLEN
) (
    input  wire [XLEN-1:0]      insn_i,
    output wire [6:0]           opcode_o,
    output wire [2:0]           funct3_o,
    output wire [6:0]           funct7_o,
    output wire [4:0]           rs1_addr_o,
    output wire [4:0]           rs2_addr_o,
    output wire [4:0]           rd_addr_o,
    output wire [4:0]           shamt_o,
    output wire [XLEN-1:0]      imm_i_o,
    output wire [XLEN-1:0]      imm_s_o,
    output wire [XLEN-1:0]      imm_b_o,
    output wire [XLEN-1:0]      imm_u_o,
    output wire [XLEN-1:0]      imm_j_o
);

    assign opcode_o   = insn_i[6:0];
    assign rd_addr_o  = insn_i[11:7];
    assign funct3_o   = insn_i[14:12];
    assign rs1_addr_o = insn_i[19:15];
    assign rs2_addr_o = insn_i[24:20];
    assign shamt_o    = insn_i[24:20];
    assign funct7_o   = insn_i[31:25];

    assign imm_i_o = {{20{insn_i[31]}}, insn_i[31:20]};
    assign imm_s_o = {{20{insn_i[31]}}, insn_i[31:25], insn_i[11:7]};
    assign imm_b_o = {{19{insn_i[31]}}, insn_i[31], insn_i[7], insn_i[30:25], insn_i[11:8], 1'b0};
    assign imm_u_o = {insn_i[31:12], 12'b0};
    assign imm_j_o = {{11{insn_i[31]}}, insn_i[31], insn_i[19:12], insn_i[20], insn_i[30:21], 1'b0};

endmodule
