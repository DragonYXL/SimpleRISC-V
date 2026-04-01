// ============================================================================
// Project     : simpleRISC-V
// File        : core_defines.vh
// Description : Local definitions for the SimpleRISC-V RISC-V core.
// ============================================================================

`ifndef SRV_CORE_DEFINES_VH
`define SRV_CORE_DEFINES_VH

`define SRV_CORE_XLEN                32
`define SRV_CORE_ADDR_W              32
`define SRV_CORE_REG_ADDR_W          5
`define SRV_CORE_RESET_PC            32'h0000_0000
`define SRV_CORE_NOP                 32'h0000_0013

`define SRV_CORE_STATE_W             3
`define SRV_CORE_STATE_RESET         3'd0
`define SRV_CORE_STATE_FETCH_REQ     3'd1
`define SRV_CORE_STATE_FETCH_WAIT    3'd2
`define SRV_CORE_STATE_EXECUTE       3'd3
`define SRV_CORE_STATE_MEM_REQ       3'd4
`define SRV_CORE_STATE_MEM_WAIT      3'd5
`define SRV_CORE_STATE_TRAP          3'd6

`define SRV_CORE_TRAP_CAUSE_W        4
`define SRV_CORE_TRAP_NONE           4'd0
`define SRV_CORE_TRAP_ILLEGAL        4'd1
`define SRV_CORE_TRAP_INSN_MISALIGN  4'd2
`define SRV_CORE_TRAP_LOAD_MISALIGN  4'd3
`define SRV_CORE_TRAP_STORE_MISALIGN 4'd4

`define SRV_CORE_ALU_OP_W            4
`define SRV_CORE_ALU_OP_ADD          4'd0
`define SRV_CORE_ALU_OP_SUB          4'd1
`define SRV_CORE_ALU_OP_SLL          4'd2
`define SRV_CORE_ALU_OP_SLT          4'd3
`define SRV_CORE_ALU_OP_SLTU         4'd4
`define SRV_CORE_ALU_OP_XOR          4'd5
`define SRV_CORE_ALU_OP_SRL          4'd6
`define SRV_CORE_ALU_OP_SRA          4'd7
`define SRV_CORE_ALU_OP_OR           4'd8
`define SRV_CORE_ALU_OP_AND          4'd9
`define SRV_CORE_ALU_OP_PASS         4'd10

`define SRV_RV32_OPCODE_LOAD         7'b0000011
`define SRV_RV32_OPCODE_MISC_MEM     7'b0001111
`define SRV_RV32_OPCODE_OP_IMM       7'b0010011
`define SRV_RV32_OPCODE_AUIPC        7'b0010111
`define SRV_RV32_OPCODE_STORE        7'b0100011
`define SRV_RV32_OPCODE_OP           7'b0110011
`define SRV_RV32_OPCODE_LUI          7'b0110111
`define SRV_RV32_OPCODE_BRANCH       7'b1100011
`define SRV_RV32_OPCODE_JALR         7'b1100111
`define SRV_RV32_OPCODE_JAL          7'b1101111
`define SRV_RV32_OPCODE_SYSTEM       7'b1110011

`define SRV_RV32_FUNCT3_ADD_SUB      3'b000
`define SRV_RV32_FUNCT3_SLL          3'b001
`define SRV_RV32_FUNCT3_SLT          3'b010
`define SRV_RV32_FUNCT3_SLTU         3'b011
`define SRV_RV32_FUNCT3_XOR          3'b100
`define SRV_RV32_FUNCT3_SRL_SRA      3'b101
`define SRV_RV32_FUNCT3_OR           3'b110
`define SRV_RV32_FUNCT3_AND          3'b111

`define SRV_RV32_FUNCT3_BEQ          3'b000
`define SRV_RV32_FUNCT3_BNE          3'b001
`define SRV_RV32_FUNCT3_BLT          3'b100
`define SRV_RV32_FUNCT3_BGE          3'b101
`define SRV_RV32_FUNCT3_BLTU         3'b110
`define SRV_RV32_FUNCT3_BGEU         3'b111

`define SRV_RV32_FUNCT3_LW           3'b010
`define SRV_RV32_FUNCT3_SW           3'b010

`define SRV_RV32_FUNCT7_BASE         7'b0000000
`define SRV_RV32_FUNCT7_SUB_SRA      7'b0100000

`endif
