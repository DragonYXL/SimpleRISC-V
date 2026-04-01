// ============================================================================
// Project     : simpleRISC-V
// Module      : srv_core_ex_stage
// Description : Execute stage for the non-pipelined RV32I subset core.
// ============================================================================

`include "core_defines.vh"

module srv_core_ex_stage #(
    parameter XLEN   = `SRV_CORE_XLEN,
    parameter ADDR_W = `SRV_CORE_ADDR_W,
    parameter REG_W  = `SRV_CORE_REG_ADDR_W
) (
    input  wire [ADDR_W-1:0]    pc_i,
    input  wire [ADDR_W-1:0]    seq_pc_i,
    input  wire [6:0]           opcode_i,
    input  wire [2:0]           funct3_i,
    input  wire [6:0]           funct7_i,
    input  wire [REG_W-1:0]     rd_addr_i,
    input  wire [REG_W-1:0]     shamt_i,
    input  wire [XLEN-1:0]      rs1_data_i,
    input  wire [XLEN-1:0]      rs2_data_i,
    input  wire [XLEN-1:0]      imm_i_i,
    input  wire [XLEN-1:0]      imm_s_i,
    input  wire [XLEN-1:0]      imm_b_i,
    input  wire [XLEN-1:0]      imm_u_i,
    input  wire [XLEN-1:0]      imm_j_i,
    output reg                  wb_en_o,
    output reg  [REG_W-1:0]     wb_addr_o,
    output reg  [XLEN-1:0]      wb_data_o,
    output reg                  mem_req_o,
    output reg                  mem_write_o,
    output reg  [ADDR_W-1:0]    mem_addr_o,
    output reg  [XLEN-1:0]      mem_wdata_o,
    output reg  [ADDR_W-1:0]    next_pc_o,
    output reg                  trap_o,
    output reg  [`SRV_CORE_TRAP_CAUSE_W-1:0] trap_cause_o
);

    reg  [`SRV_CORE_ALU_OP_W-1:0] alu_op_r;
    reg  [XLEN-1:0]               alu_operand_a_r;
    reg  [XLEN-1:0]               alu_operand_b_r;
    reg  [ADDR_W-1:0]             branch_target_r;
    reg                           branch_taken_r;

    wire [XLEN-1:0]               alu_result_w;

    srv_core_alu u_alu (
        .op_i       (alu_op_r),
        .operand_a_i(alu_operand_a_r),
        .operand_b_i(alu_operand_b_r),
        .result_o   (alu_result_w)
    );

    always @(*) begin
        wb_en_o         = 1'b0;
        wb_addr_o       = rd_addr_i;
        wb_data_o       = {XLEN{1'b0}};
        mem_req_o       = 1'b0;
        mem_write_o     = 1'b0;
        mem_addr_o      = {ADDR_W{1'b0}};
        mem_wdata_o     = {XLEN{1'b0}};
        next_pc_o       = seq_pc_i;
        trap_o          = 1'b0;
        trap_cause_o    = `SRV_CORE_TRAP_NONE;
        alu_op_r        = `SRV_CORE_ALU_OP_ADD;
        alu_operand_a_r = rs1_data_i;
        alu_operand_b_r = rs2_data_i;
        branch_target_r = {ADDR_W{1'b0}};
        branch_taken_r  = 1'b0;

        case (opcode_i)
            `SRV_RV32_OPCODE_LUI: begin
                alu_op_r        = `SRV_CORE_ALU_OP_PASS;
                alu_operand_b_r = imm_u_i;
                wb_en_o         = 1'b1;
                wb_data_o       = alu_result_w;
            end
            `SRV_RV32_OPCODE_AUIPC: begin
                alu_op_r        = `SRV_CORE_ALU_OP_ADD;
                alu_operand_a_r = pc_i;
                alu_operand_b_r = imm_u_i;
                wb_en_o         = 1'b1;
                wb_data_o       = alu_result_w;
            end
            `SRV_RV32_OPCODE_JAL: begin
                branch_target_r = pc_i + imm_j_i[ADDR_W-1:0];
                if (branch_target_r[1:0] != 2'b00) begin
                    trap_o       = 1'b1;
                    trap_cause_o = `SRV_CORE_TRAP_INSN_MISALIGN;
                end else begin
                    wb_en_o   = 1'b1;
                    wb_data_o = seq_pc_i;
                    next_pc_o = branch_target_r;
                end
            end
            `SRV_RV32_OPCODE_JALR: begin
                if (funct3_i != `SRV_RV32_FUNCT3_ADD_SUB) begin
                    trap_o       = 1'b1;
                    trap_cause_o = `SRV_CORE_TRAP_ILLEGAL;
                end else begin
                    alu_op_r        = `SRV_CORE_ALU_OP_ADD;
                    alu_operand_a_r = rs1_data_i;
                    alu_operand_b_r = imm_i_i;
                    branch_target_r = {alu_result_w[ADDR_W-1:1], 1'b0};
                    if (branch_target_r[1:0] != 2'b00) begin
                        trap_o       = 1'b1;
                        trap_cause_o = `SRV_CORE_TRAP_INSN_MISALIGN;
                    end else begin
                        wb_en_o   = 1'b1;
                        wb_data_o = seq_pc_i;
                        next_pc_o = branch_target_r;
                    end
                end
            end
            `SRV_RV32_OPCODE_BRANCH: begin
                branch_target_r = pc_i + imm_b_i[ADDR_W-1:0];
                case (funct3_i)
                    `SRV_RV32_FUNCT3_BEQ : branch_taken_r = (rs1_data_i == rs2_data_i);
                    `SRV_RV32_FUNCT3_BNE : branch_taken_r = (rs1_data_i != rs2_data_i);
                    `SRV_RV32_FUNCT3_BLT : branch_taken_r = ($signed(rs1_data_i) < $signed(rs2_data_i));
                    `SRV_RV32_FUNCT3_BGE : branch_taken_r = ($signed(rs1_data_i) >= $signed(rs2_data_i));
                    `SRV_RV32_FUNCT3_BLTU: branch_taken_r = ($unsigned(rs1_data_i) < $unsigned(rs2_data_i));
                    `SRV_RV32_FUNCT3_BGEU: branch_taken_r = ($unsigned(rs1_data_i) >= $unsigned(rs2_data_i));
                    default: begin
                        trap_o       = 1'b1;
                        trap_cause_o = `SRV_CORE_TRAP_ILLEGAL;
                    end
                endcase

                if (!trap_o && branch_taken_r) begin
                    if (branch_target_r[1:0] != 2'b00) begin
                        trap_o       = 1'b1;
                        trap_cause_o = `SRV_CORE_TRAP_INSN_MISALIGN;
                    end else begin
                        next_pc_o = branch_target_r;
                    end
                end
            end
            `SRV_RV32_OPCODE_LOAD: begin
                alu_op_r        = `SRV_CORE_ALU_OP_ADD;
                alu_operand_a_r = rs1_data_i;
                alu_operand_b_r = imm_i_i;
                if (funct3_i != `SRV_RV32_FUNCT3_LW) begin
                    trap_o       = 1'b1;
                    trap_cause_o = `SRV_CORE_TRAP_ILLEGAL;
                end else if (alu_result_w[1:0] != 2'b00) begin
                    trap_o       = 1'b1;
                    trap_cause_o = `SRV_CORE_TRAP_LOAD_MISALIGN;
                end else begin
                    mem_req_o   = 1'b1;
                    mem_addr_o  = alu_result_w[ADDR_W-1:0];
                end
            end
            `SRV_RV32_OPCODE_STORE: begin
                alu_op_r        = `SRV_CORE_ALU_OP_ADD;
                alu_operand_a_r = rs1_data_i;
                alu_operand_b_r = imm_s_i;
                if (funct3_i != `SRV_RV32_FUNCT3_SW) begin
                    trap_o       = 1'b1;
                    trap_cause_o = `SRV_CORE_TRAP_ILLEGAL;
                end else if (alu_result_w[1:0] != 2'b00) begin
                    trap_o       = 1'b1;
                    trap_cause_o = `SRV_CORE_TRAP_STORE_MISALIGN;
                end else begin
                    mem_req_o   = 1'b1;
                    mem_write_o = 1'b1;
                    mem_addr_o  = alu_result_w[ADDR_W-1:0];
                    mem_wdata_o = rs2_data_i;
                end
            end
            `SRV_RV32_OPCODE_OP_IMM: begin
                wb_en_o = 1'b1;
                case (funct3_i)
                    `SRV_RV32_FUNCT3_ADD_SUB: begin
                        alu_op_r        = `SRV_CORE_ALU_OP_ADD;
                        alu_operand_b_r = imm_i_i;
                        wb_data_o       = alu_result_w;
                    end
                    `SRV_RV32_FUNCT3_SLT: begin
                        alu_op_r        = `SRV_CORE_ALU_OP_SLT;
                        alu_operand_b_r = imm_i_i;
                        wb_data_o       = alu_result_w;
                    end
                    `SRV_RV32_FUNCT3_SLTU: begin
                        alu_op_r        = `SRV_CORE_ALU_OP_SLTU;
                        alu_operand_b_r = imm_i_i;
                        wb_data_o       = alu_result_w;
                    end
                    `SRV_RV32_FUNCT3_XOR: begin
                        alu_op_r        = `SRV_CORE_ALU_OP_XOR;
                        alu_operand_b_r = imm_i_i;
                        wb_data_o       = alu_result_w;
                    end
                    `SRV_RV32_FUNCT3_OR: begin
                        alu_op_r        = `SRV_CORE_ALU_OP_OR;
                        alu_operand_b_r = imm_i_i;
                        wb_data_o       = alu_result_w;
                    end
                    `SRV_RV32_FUNCT3_AND: begin
                        alu_op_r        = `SRV_CORE_ALU_OP_AND;
                        alu_operand_b_r = imm_i_i;
                        wb_data_o       = alu_result_w;
                    end
                    `SRV_RV32_FUNCT3_SLL: begin
                        if (funct7_i != `SRV_RV32_FUNCT7_BASE) begin
                            trap_o       = 1'b1;
                            trap_cause_o = `SRV_CORE_TRAP_ILLEGAL;
                        end else begin
                            alu_op_r        = `SRV_CORE_ALU_OP_SLL;
                            alu_operand_b_r = {{(XLEN-REG_W){1'b0}}, shamt_i};
                            wb_data_o       = alu_result_w;
                        end
                    end
                    `SRV_RV32_FUNCT3_SRL_SRA: begin
                        alu_operand_b_r = {{(XLEN-REG_W){1'b0}}, shamt_i};
                        if (funct7_i == `SRV_RV32_FUNCT7_BASE) begin
                            alu_op_r  = `SRV_CORE_ALU_OP_SRL;
                            wb_data_o = alu_result_w;
                        end else if (funct7_i == `SRV_RV32_FUNCT7_SUB_SRA) begin
                            alu_op_r  = `SRV_CORE_ALU_OP_SRA;
                            wb_data_o = alu_result_w;
                        end else begin
                            trap_o       = 1'b1;
                            trap_cause_o = `SRV_CORE_TRAP_ILLEGAL;
                        end
                    end
                    default: begin
                        trap_o       = 1'b1;
                        trap_cause_o = `SRV_CORE_TRAP_ILLEGAL;
                    end
                endcase
            end
            `SRV_RV32_OPCODE_OP: begin
                wb_en_o = 1'b1;
                case (funct3_i)
                    `SRV_RV32_FUNCT3_ADD_SUB: begin
                        if (funct7_i == `SRV_RV32_FUNCT7_BASE) begin
                            alu_op_r  = `SRV_CORE_ALU_OP_ADD;
                            wb_data_o = alu_result_w;
                        end else if (funct7_i == `SRV_RV32_FUNCT7_SUB_SRA) begin
                            alu_op_r  = `SRV_CORE_ALU_OP_SUB;
                            wb_data_o = alu_result_w;
                        end else begin
                            trap_o       = 1'b1;
                            trap_cause_o = `SRV_CORE_TRAP_ILLEGAL;
                        end
                    end
                    `SRV_RV32_FUNCT3_SLL: begin
                        if (funct7_i != `SRV_RV32_FUNCT7_BASE) begin
                            trap_o       = 1'b1;
                            trap_cause_o = `SRV_CORE_TRAP_ILLEGAL;
                        end else begin
                            alu_op_r  = `SRV_CORE_ALU_OP_SLL;
                            wb_data_o = alu_result_w;
                        end
                    end
                    `SRV_RV32_FUNCT3_SLT: begin
                        if (funct7_i != `SRV_RV32_FUNCT7_BASE) begin
                            trap_o       = 1'b1;
                            trap_cause_o = `SRV_CORE_TRAP_ILLEGAL;
                        end else begin
                            alu_op_r  = `SRV_CORE_ALU_OP_SLT;
                            wb_data_o = alu_result_w;
                        end
                    end
                    `SRV_RV32_FUNCT3_SLTU: begin
                        if (funct7_i != `SRV_RV32_FUNCT7_BASE) begin
                            trap_o       = 1'b1;
                            trap_cause_o = `SRV_CORE_TRAP_ILLEGAL;
                        end else begin
                            alu_op_r  = `SRV_CORE_ALU_OP_SLTU;
                            wb_data_o = alu_result_w;
                        end
                    end
                    `SRV_RV32_FUNCT3_XOR: begin
                        if (funct7_i != `SRV_RV32_FUNCT7_BASE) begin
                            trap_o       = 1'b1;
                            trap_cause_o = `SRV_CORE_TRAP_ILLEGAL;
                        end else begin
                            alu_op_r  = `SRV_CORE_ALU_OP_XOR;
                            wb_data_o = alu_result_w;
                        end
                    end
                    `SRV_RV32_FUNCT3_SRL_SRA: begin
                        if (funct7_i == `SRV_RV32_FUNCT7_BASE) begin
                            alu_op_r  = `SRV_CORE_ALU_OP_SRL;
                            wb_data_o = alu_result_w;
                        end else if (funct7_i == `SRV_RV32_FUNCT7_SUB_SRA) begin
                            alu_op_r  = `SRV_CORE_ALU_OP_SRA;
                            wb_data_o = alu_result_w;
                        end else begin
                            trap_o       = 1'b1;
                            trap_cause_o = `SRV_CORE_TRAP_ILLEGAL;
                        end
                    end
                    `SRV_RV32_FUNCT3_OR: begin
                        if (funct7_i != `SRV_RV32_FUNCT7_BASE) begin
                            trap_o       = 1'b1;
                            trap_cause_o = `SRV_CORE_TRAP_ILLEGAL;
                        end else begin
                            alu_op_r  = `SRV_CORE_ALU_OP_OR;
                            wb_data_o = alu_result_w;
                        end
                    end
                    `SRV_RV32_FUNCT3_AND: begin
                        if (funct7_i != `SRV_RV32_FUNCT7_BASE) begin
                            trap_o       = 1'b1;
                            trap_cause_o = `SRV_CORE_TRAP_ILLEGAL;
                        end else begin
                            alu_op_r  = `SRV_CORE_ALU_OP_AND;
                            wb_data_o = alu_result_w;
                        end
                    end
                    default: begin
                        trap_o       = 1'b1;
                        trap_cause_o = `SRV_CORE_TRAP_ILLEGAL;
                    end
                endcase
            end
            `SRV_RV32_OPCODE_MISC_MEM: begin
                wb_en_o   = 1'b0;
                next_pc_o = seq_pc_i;
            end
            default: begin
                trap_o       = 1'b1;
                trap_cause_o = `SRV_CORE_TRAP_ILLEGAL;
            end
        endcase

        if (trap_o) begin
            wb_en_o     = 1'b0;
            mem_req_o   = 1'b0;
            mem_write_o = 1'b0;
        end
    end

endmodule
