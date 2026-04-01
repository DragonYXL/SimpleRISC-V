// ============================================================================
// Project     : simpleRISC-V
// Module      : srv_riscv_core
// Description : Top-level assembly for the staged SimpleRISC-V RV32I subset
//               core. The implementation keeps the current non-pipelined
//               execution model while splitting IF/ID/EX/MEM/CTRL into
//               separate modules.
// ============================================================================

`include "core_defines.vh"

module srv_riscv_core #(
    parameter XLEN     = `SRV_CORE_XLEN,
    parameter ADDR_W   = `SRV_CORE_ADDR_W,
    parameter RESET_PC = `SRV_CORE_RESET_PC
) (
    input  wire                 clk,
    input  wire                 rst_n,

    input  wire [XLEN-1:0]      if_bus_rd_data_i,
    input  wire                 if_bus_rdy_n_i,
    input  wire                 if_bus_grnt_n_i,
    output wire                 if_bus_req_n_o,
    output wire [ADDR_W-1:0]    if_bus_addr_o,
    output wire                 if_bus_as_n_o,
    output wire                 if_bus_rw_o,
    output wire [XLEN-1:0]      if_bus_wr_data_o,

    input  wire [XLEN-1:0]      mem_bus_rd_data_i,
    input  wire                 mem_bus_rdy_n_i,
    input  wire                 mem_bus_grnt_n_i,
    output wire                 mem_bus_req_n_o,
    output wire [ADDR_W-1:0]    mem_bus_addr_o,
    output wire                 mem_bus_as_n_o,
    output wire                 mem_bus_rw_o,
    output wire [XLEN-1:0]      mem_bus_wr_data_o,

    output reg                  trap_o,
    output reg  [ADDR_W-1:0]    trap_pc_o,
    output reg  [`SRV_CORE_TRAP_CAUSE_W-1:0] trap_cause_o,
    output wire [ADDR_W-1:0]    dbg_pc_o
);

    localparam integer REG_ADDR_W = `SRV_CORE_REG_ADDR_W;

    reg  [`SRV_CORE_STATE_W-1:0] state_q;
    reg  [ADDR_W-1:0]            pc_q;
    reg  [XLEN-1:0]              insn_q;

    reg  [ADDR_W-1:0]            mem_addr_q;
    reg  [XLEN-1:0]              mem_wdata_q;
    reg                          mem_write_q;
    reg                          mem_is_load_q;
    reg  [REG_ADDR_W-1:0]        mem_rd_q;
    reg  [ADDR_W-1:0]            mem_next_pc_q;

    wire [ADDR_W-1:0]            if_seq_pc_w;
    wire [XLEN-1:0]              if_insn_w;
    wire                         if_cmd_done_w;
    wire                         if_fetch_misaligned_w;

    wire [6:0]                   dec_opcode_w;
    wire [2:0]                   dec_funct3_w;
    wire [6:0]                   dec_funct7_w;
    wire [REG_ADDR_W-1:0]        dec_rs1_addr_w;
    wire [REG_ADDR_W-1:0]        dec_rs2_addr_w;
    wire [REG_ADDR_W-1:0]        dec_rd_addr_w;
    wire [REG_ADDR_W-1:0]        dec_shamt_w;
    wire [XLEN-1:0]              dec_imm_i_w;
    wire [XLEN-1:0]              dec_imm_s_w;
    wire [XLEN-1:0]              dec_imm_b_w;
    wire [XLEN-1:0]              dec_imm_u_w;
    wire [XLEN-1:0]              dec_imm_j_w;

    wire [XLEN-1:0]              rs1_data_w;
    wire [XLEN-1:0]              rs2_data_w;

    wire [ADDR_W-1:0]            id_pc_w;
    wire [6:0]                   id_opcode_w;
    wire [2:0]                   id_funct3_w;
    wire [6:0]                   id_funct7_w;
    wire [REG_ADDR_W-1:0]        id_rd_addr_w;
    wire [REG_ADDR_W-1:0]        id_shamt_w;
    wire [XLEN-1:0]              id_rs1_data_w;
    wire [XLEN-1:0]              id_rs2_data_w;
    wire [XLEN-1:0]              id_imm_i_w;
    wire [XLEN-1:0]              id_imm_s_w;
    wire [XLEN-1:0]              id_imm_b_w;
    wire [XLEN-1:0]              id_imm_u_w;
    wire [XLEN-1:0]              id_imm_j_w;

    wire                         ex_wb_en_w;
    wire [REG_ADDR_W-1:0]        ex_wb_addr_w;
    wire [XLEN-1:0]              ex_wb_data_w;
    wire                         ex_mem_req_w;
    wire                         ex_mem_write_w;
    wire [ADDR_W-1:0]            ex_mem_addr_w;
    wire [XLEN-1:0]              ex_mem_wdata_w;
    wire [ADDR_W-1:0]            ex_next_pc_w;
    wire                         ex_trap_w;
    wire [`SRV_CORE_TRAP_CAUSE_W-1:0] ex_trap_cause_w;

    wire                         mem_cmd_done_w;
    wire                         mem_wb_en_w;
    wire [REG_ADDR_W-1:0]        mem_wb_addr_w;
    wire [XLEN-1:0]              mem_wb_data_w;
    wire [ADDR_W-1:0]            mem_wb_next_pc_w;

    wire                         rf_wr_en_w;
    wire [REG_ADDR_W-1:0]        rf_wr_addr_w;
    wire [XLEN-1:0]              rf_wr_data_w;

    wire                         if_cmd_valid_w;
    wire                         mem_cmd_valid_w;
    wire [`SRV_CORE_STATE_W-1:0] ctrl_next_state_w;
    wire                         ctrl_reset_state_w;
    wire                         ctrl_fetch_fault_w;
    wire                         ctrl_fetch_accept_w;
    wire                         ctrl_execute_trap_w;
    wire                         ctrl_execute_mem_w;
    wire                         ctrl_execute_commit_w;
    wire                         ctrl_mem_complete_w;

    assign dbg_pc_o     = pc_q;
    assign rf_wr_en_w   = ((state_q == `SRV_CORE_STATE_EXECUTE) && ex_wb_en_w && !ex_trap_w) || mem_wb_en_w;
    assign rf_wr_addr_w = mem_wb_en_w ? mem_wb_addr_w : ex_wb_addr_w;
    assign rf_wr_data_w = mem_wb_en_w ? mem_wb_data_w : ex_wb_data_w;

    srv_core_if_stage u_if_stage (
        .clk               (clk),
        .rst_n             (rst_n),
        .fetch_req_i       (if_cmd_valid_w),
        .pc_i              (pc_q),
        .bus_rd_data_i     (if_bus_rd_data_i),
        .bus_rdy_n_i       (if_bus_rdy_n_i),
        .bus_grnt_n_i      (if_bus_grnt_n_i),
        .bus_req_n_o       (if_bus_req_n_o),
        .bus_addr_o        (if_bus_addr_o),
        .bus_as_n_o        (if_bus_as_n_o),
        .bus_rw_o          (if_bus_rw_o),
        .bus_wr_data_o     (if_bus_wr_data_o),
        .fetch_done_o      (if_cmd_done_w),
        .fetch_insn_o      (if_insn_w),
        .seq_pc_o          (if_seq_pc_w),
        .fetch_misaligned_o(if_fetch_misaligned_w)
    );

    srv_core_decoder u_decoder (
        .insn_i    (insn_q),
        .opcode_o  (dec_opcode_w),
        .funct3_o  (dec_funct3_w),
        .funct7_o  (dec_funct7_w),
        .rs1_addr_o(dec_rs1_addr_w),
        .rs2_addr_o(dec_rs2_addr_w),
        .rd_addr_o (dec_rd_addr_w),
        .shamt_o   (dec_shamt_w),
        .imm_i_o   (dec_imm_i_w),
        .imm_s_o   (dec_imm_s_w),
        .imm_b_o   (dec_imm_b_w),
        .imm_u_o   (dec_imm_u_w),
        .imm_j_o   (dec_imm_j_w)
    );

    srv_core_regfile u_regfile (
        .clk        (clk),
        .rst_n      (rst_n),
        .rd_addr_0_i(dec_rs1_addr_w),
        .rd_data_0_o(rs1_data_w),
        .rd_addr_1_i(dec_rs2_addr_w),
        .rd_data_1_o(rs2_data_w),
        .wr_en_i    (rf_wr_en_w),
        .wr_addr_i  (rf_wr_addr_w),
        .wr_data_i  (rf_wr_data_w)
    );

    srv_core_id_stage u_id_stage (
        .pc_i       (pc_q),
        .opcode_i   (dec_opcode_w),
        .funct3_i   (dec_funct3_w),
        .funct7_i   (dec_funct7_w),
        .rs1_addr_i (dec_rs1_addr_w),
        .rs2_addr_i (dec_rs2_addr_w),
        .rd_addr_i  (dec_rd_addr_w),
        .shamt_i    (dec_shamt_w),
        .rs1_data_i (rs1_data_w),
        .rs2_data_i (rs2_data_w),
        .imm_i_i    (dec_imm_i_w),
        .imm_s_i    (dec_imm_s_w),
        .imm_b_i    (dec_imm_b_w),
        .imm_u_i    (dec_imm_u_w),
        .imm_j_i    (dec_imm_j_w),
        .pc_o       (id_pc_w),
        .opcode_o   (id_opcode_w),
        .funct3_o   (id_funct3_w),
        .funct7_o   (id_funct7_w),
        .rs1_addr_o (),
        .rs2_addr_o (),
        .rd_addr_o  (id_rd_addr_w),
        .shamt_o    (id_shamt_w),
        .rs1_data_o (id_rs1_data_w),
        .rs2_data_o (id_rs2_data_w),
        .imm_i_o    (id_imm_i_w),
        .imm_s_o    (id_imm_s_w),
        .imm_b_o    (id_imm_b_w),
        .imm_u_o    (id_imm_u_w),
        .imm_j_o    (id_imm_j_w)
    );

    srv_core_ex_stage u_ex_stage (
        .pc_i        (id_pc_w),
        .seq_pc_i    (if_seq_pc_w),
        .opcode_i    (id_opcode_w),
        .funct3_i    (id_funct3_w),
        .funct7_i    (id_funct7_w),
        .rd_addr_i   (id_rd_addr_w),
        .shamt_i     (id_shamt_w),
        .rs1_data_i  (id_rs1_data_w),
        .rs2_data_i  (id_rs2_data_w),
        .imm_i_i     (id_imm_i_w),
        .imm_s_i     (id_imm_s_w),
        .imm_b_i     (id_imm_b_w),
        .imm_u_i     (id_imm_u_w),
        .imm_j_i     (id_imm_j_w),
        .wb_en_o     (ex_wb_en_w),
        .wb_addr_o   (ex_wb_addr_w),
        .wb_data_o   (ex_wb_data_w),
        .mem_req_o   (ex_mem_req_w),
        .mem_write_o (ex_mem_write_w),
        .mem_addr_o  (ex_mem_addr_w),
        .mem_wdata_o (ex_mem_wdata_w),
        .next_pc_o   (ex_next_pc_w),
        .trap_o      (ex_trap_w),
        .trap_cause_o(ex_trap_cause_w)
    );

    srv_core_mem_stage u_mem_stage (
        .clk         (clk),
        .rst_n       (rst_n),
        .mem_req_i   (mem_cmd_valid_w),
        .mem_addr_i  (mem_addr_q),
        .mem_write_i (mem_write_q),
        .mem_wdata_i (mem_wdata_q),
        .mem_is_load_i(mem_is_load_q),
        .mem_rd_i    (mem_rd_q),
        .mem_next_pc_i(mem_next_pc_q),
        .bus_rd_data_i(mem_bus_rd_data_i),
        .bus_rdy_n_i (mem_bus_rdy_n_i),
        .bus_grnt_n_i(mem_bus_grnt_n_i),
        .bus_req_n_o (mem_bus_req_n_o),
        .bus_addr_o  (mem_bus_addr_o),
        .bus_as_n_o  (mem_bus_as_n_o),
        .bus_rw_o    (mem_bus_rw_o),
        .bus_wr_data_o(mem_bus_wr_data_o),
        .mem_done_o  (mem_cmd_done_w),
        .wb_en_o     (mem_wb_en_w),
        .wb_addr_o   (mem_wb_addr_w),
        .wb_data_o   (mem_wb_data_w),
        .next_pc_o   (mem_wb_next_pc_w)
    );

    srv_core_ctrl u_ctrl (
        .state_i          (state_q),
        .fetch_misaligned_i(if_fetch_misaligned_w),
        .if_cmd_done_i    (if_cmd_done_w),
        .exec_trap_i      (ex_trap_w),
        .exec_mem_req_i   (ex_mem_req_w),
        .mem_cmd_done_i   (mem_cmd_done_w),
        .if_cmd_valid_o   (if_cmd_valid_w),
        .mem_cmd_valid_o  (mem_cmd_valid_w),
        .next_state_o     (ctrl_next_state_w),
        .reset_state_o    (ctrl_reset_state_w),
        .fetch_fault_o    (ctrl_fetch_fault_w),
        .fetch_accept_o   (ctrl_fetch_accept_w),
        .execute_trap_o   (ctrl_execute_trap_w),
        .execute_mem_o    (ctrl_execute_mem_w),
        .execute_commit_o (ctrl_execute_commit_w),
        .mem_complete_o   (ctrl_mem_complete_w)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_q       <= `SRV_CORE_STATE_RESET;
            pc_q          <= RESET_PC;
            insn_q        <= `SRV_CORE_NOP;
            mem_addr_q    <= {ADDR_W{1'b0}};
            mem_wdata_q   <= {XLEN{1'b0}};
            mem_write_q   <= 1'b0;
            mem_is_load_q <= 1'b0;
            mem_rd_q      <= {REG_ADDR_W{1'b0}};
            mem_next_pc_q <= RESET_PC;
            trap_o        <= 1'b0;
            trap_pc_o     <= {ADDR_W{1'b0}};
            trap_cause_o  <= `SRV_CORE_TRAP_NONE;
        end else begin
            state_q <= ctrl_next_state_w;

            if (ctrl_reset_state_w) begin
                pc_q          <= RESET_PC;
                insn_q        <= `SRV_CORE_NOP;
                mem_addr_q    <= {ADDR_W{1'b0}};
                mem_wdata_q   <= {XLEN{1'b0}};
                mem_write_q   <= 1'b0;
                mem_is_load_q <= 1'b0;
                mem_rd_q      <= {REG_ADDR_W{1'b0}};
                mem_next_pc_q <= RESET_PC;
                trap_o        <= 1'b0;
                trap_pc_o     <= {ADDR_W{1'b0}};
                trap_cause_o  <= `SRV_CORE_TRAP_NONE;
            end

            if (ctrl_fetch_fault_w) begin
                trap_o       <= 1'b1;
                trap_pc_o    <= pc_q;
                trap_cause_o <= `SRV_CORE_TRAP_INSN_MISALIGN;
            end

            if (ctrl_fetch_accept_w) begin
                insn_q <= if_insn_w;
            end

            if (ctrl_execute_trap_w) begin
                trap_o       <= 1'b1;
                trap_pc_o    <= pc_q;
                trap_cause_o <= ex_trap_cause_w;
            end

            if (ctrl_execute_mem_w) begin
                mem_addr_q    <= ex_mem_addr_w;
                mem_wdata_q   <= ex_mem_wdata_w;
                mem_write_q   <= ex_mem_write_w;
                mem_is_load_q <= !ex_mem_write_w;
                mem_rd_q      <= id_rd_addr_w;
                mem_next_pc_q <= if_seq_pc_w;
            end

            if (ctrl_execute_commit_w) begin
                pc_q <= ex_next_pc_w;
            end

            if (ctrl_mem_complete_w) begin
                pc_q <= mem_wb_next_pc_w;
            end
        end
    end

endmodule
