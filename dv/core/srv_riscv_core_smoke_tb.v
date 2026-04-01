`timescale 1ns/1ps

// ============================================================================
// Project     : simpleRISC-V
// Module      : srv_riscv_core_smoke_tb
// Description : Directed smoke test for the non-pipelined RV32I core.
// ============================================================================

module srv_riscv_core_smoke_tb;

    reg         clk;
    reg         rst_n;

    wire        if_bus_req_n;
    wire [31:0] if_bus_addr;
    wire        if_bus_as_n;
    wire        if_bus_rw;
    wire [31:0] if_bus_wr_data;
    reg  [31:0] if_bus_rd_data;
    wire        if_bus_grnt_n;
    reg         if_bus_rdy_n;

    wire        mem_bus_req_n;
    wire [31:0] mem_bus_addr;
    wire        mem_bus_as_n;
    wire        mem_bus_rw;
    wire [31:0] mem_bus_wr_data;
    reg  [31:0] mem_bus_rd_data;
    wire        mem_bus_grnt_n;
    reg         mem_bus_rdy_n;

    wire        trap;
    wire [31:0] trap_pc;
    wire [3:0]  trap_cause;
    wire [31:0] dbg_pc;

    reg [31:0] if_mem  [0:63];
    reg [31:0] data_mem[0:63];

    integer idx;

    assign if_bus_grnt_n  = if_bus_req_n ? 1'b1 : 1'b0;
    assign mem_bus_grnt_n = mem_bus_req_n ? 1'b1 : 1'b0;

    srv_riscv_core u_dut (
        .clk              (clk),
        .rst_n            (rst_n),
        .if_bus_rd_data_i (if_bus_rd_data),
        .if_bus_rdy_n_i   (if_bus_rdy_n),
        .if_bus_grnt_n_i  (if_bus_grnt_n),
        .if_bus_req_n_o   (if_bus_req_n),
        .if_bus_addr_o    (if_bus_addr),
        .if_bus_as_n_o    (if_bus_as_n),
        .if_bus_rw_o      (if_bus_rw),
        .if_bus_wr_data_o (if_bus_wr_data),
        .mem_bus_rd_data_i(mem_bus_rd_data),
        .mem_bus_rdy_n_i  (mem_bus_rdy_n),
        .mem_bus_grnt_n_i (mem_bus_grnt_n),
        .mem_bus_req_n_o  (mem_bus_req_n),
        .mem_bus_addr_o   (mem_bus_addr),
        .mem_bus_as_n_o   (mem_bus_as_n),
        .mem_bus_rw_o     (mem_bus_rw),
        .mem_bus_wr_data_o(mem_bus_wr_data),
        .trap_o           (trap),
        .trap_pc_o        (trap_pc),
        .trap_cause_o     (trap_cause),
        .dbg_pc_o         (dbg_pc)
    );

    always #5 clk = ~clk;

    always @(*) begin
        if_bus_rd_data = if_mem[if_bus_addr[31:2]];
        if_bus_rdy_n   = if_bus_as_n ? 1'b1 : 1'b0;
    end

    always @(*) begin
        mem_bus_rd_data = data_mem[mem_bus_addr[31:2]];
        mem_bus_rdy_n   = mem_bus_as_n ? 1'b1 : 1'b0;
    end

    always @(posedge clk) begin
        if (!mem_bus_as_n && !mem_bus_rw) begin
            data_mem[mem_bus_addr[31:2]] <= mem_bus_wr_data;
        end
    end

    initial begin
        clk  = 1'b0;
        rst_n = 1'b0;

        for (idx = 0; idx < 64; idx = idx + 1) begin
            if_mem[idx]   = 32'h0000_0013;
            data_mem[idx] = 32'h0000_0000;
        end

        // Program:
        //   lui   x1, 0x10
        //   addi  x1, x1, 4
        //   sw    x1, 0(x0)
        //   lw    x2, 0(x0)
        //   beq   x1, x2, +8
        //   addi  x3, x0, 1
        //   add   x4, x1, x2
        //   jal   x0, 0
        if_mem[0] = 32'h0001_00b7;
        if_mem[1] = 32'h0040_8093;
        if_mem[2] = 32'h0010_2023;
        if_mem[3] = 32'h0000_2103;
        if_mem[4] = 32'h0020_8463;
        if_mem[5] = 32'h0010_0193;
        if_mem[6] = 32'h0020_8233;
        if_mem[7] = 32'h0000_006f;

        repeat (3) @(posedge clk);
        rst_n = 1'b1;

        repeat (80) @(posedge clk);

        if (trap) begin
            $display("FAIL: unexpected trap pc=%h cause=%0d", trap_pc, trap_cause);
            $finish(1);
        end

        if (data_mem[0] !== 32'h0001_0004) begin
            $display("FAIL: store result mismatch exp=00010004 act=%h", data_mem[0]);
            $finish(1);
        end

        if (u_dut.u_regfile.gpr[2] !== 32'h0001_0004) begin
            $display("FAIL: x2 mismatch exp=00010004 act=%h", u_dut.u_regfile.gpr[2]);
            $finish(1);
        end

        if (u_dut.u_regfile.gpr[3] !== 32'h0000_0000) begin
            $display("FAIL: x3 should stay zero because branch is taken act=%h", u_dut.u_regfile.gpr[3]);
            $finish(1);
        end

        if (u_dut.u_regfile.gpr[4] !== 32'h0002_0008) begin
            $display("FAIL: x4 mismatch exp=00020008 act=%h", u_dut.u_regfile.gpr[4]);
            $finish(1);
        end

        if (dbg_pc !== 32'h0000_001c) begin
            $display("FAIL: PC should park at JAL loop act=%h", dbg_pc);
            $finish(1);
        end

        $display("PASS: srv_riscv_core_smoke_tb");
        $finish;
    end

endmodule
