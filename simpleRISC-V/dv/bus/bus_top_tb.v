`timescale 1ns/1ps

// ============================================================================
// Project     : simpleRISC-V
// Module      : bus_top_tb
// Description : Comprehensive directed testbench for bus_top.
//               Covers:
//                 - Every master accessing every slave (read & write)
//                 - Fixed-priority arbitration (lower index = higher priority)
//                 - Non-preemptive ownership (owner keeps bus until release)
//                 - Priority chain: M0 > M1 > M2 > M3
//                 - Idle-bus defaults and bus release behavior
//                 - Slave ready back-pressure propagation
//                 - Transaction lock during slow-slave access
//
//               Timing convention (registered grant):
//                 negedge : set master signals
//                 posedge : arbiter registers grant
//                 negedge : check — grant visible, mux outputs valid
// ============================================================================

`include "../../src/bus/bus_defines.vh"

`define CHECK(cond, msg)                                                     \
    if (!(cond)) begin                                                       \
        $display("FAIL: %0s (time=%0t)", msg, $time);                        \
        err_cnt = err_cnt + 1;                                               \
    end

module bus_top_tb;

    localparam integer NUM_MASTERS = `SRV_BUS_MASTER_NUM;
    localparam integer NUM_SLAVES  = `SRV_BUS_SLAVE_NUM;
    localparam integer ADDR_W      = `SRV_BUS_ADDR_W;
    localparam integer DATA_W      = `SRV_BUS_DATA_W;
    localparam integer IDX_MSB     = `SRV_BUS_SLAVE_IDX_MSB;
    localparam integer IDX_LSB     = `SRV_BUS_SLAVE_IDX_LSB;

    // ========================================================================
    // DUT signals
    // ========================================================================
    reg                              clk;
    reg                              rst_n;
    reg  [NUM_MASTERS-1:0]           m_req_n;
    wire [NUM_MASTERS-1:0]           m_grnt_n;
    reg  [NUM_MASTERS*ADDR_W-1:0]    m_addr;
    reg  [NUM_MASTERS-1:0]           m_as_n;
    reg  [NUM_MASTERS-1:0]           m_rw;
    reg  [NUM_MASTERS*DATA_W-1:0]    m_wr_data;
    wire [DATA_W-1:0]                m_rd_data;
    wire                             m_rdy_n;
    wire [ADDR_W-1:0]                s_addr;
    wire                             s_as_n;
    wire                             s_rw;
    wire [DATA_W-1:0]                s_wr_data;
    wire [NUM_SLAVES-1:0]            s_cs_n;
    reg  [NUM_SLAVES*DATA_W-1:0]     s_rd_data;
    reg  [NUM_SLAVES-1:0]            s_rdy_n;

    // Slave response storage
    reg  [NUM_SLAVES*DATA_W-1:0]     slave_rsp_data;
    reg  [NUM_SLAVES-1:0]            slave_rsp_rdy_n;

    integer err_cnt;
    integer i;
    integer mi, si;

    // ========================================================================
    // DUT Instantiation
    // ========================================================================
    bus_top #(
        .NUM_MASTERS (NUM_MASTERS),
        .NUM_SLAVES  (NUM_SLAVES),
        .ADDR_W      (ADDR_W),
        .DATA_W      (DATA_W),
        .IDX_MSB     (IDX_MSB),
        .IDX_LSB     (IDX_LSB)
    ) dut (
        .clk      (clk),
        .rst_n    (rst_n),
        .m_req_n  (m_req_n),
        .m_grnt_n (m_grnt_n),
        .m_addr   (m_addr),
        .m_as_n   (m_as_n),
        .m_rw     (m_rw),
        .m_wr_data(m_wr_data),
        .m_rd_data(m_rd_data),
        .m_rdy_n  (m_rdy_n),
        .s_addr   (s_addr),
        .s_as_n   (s_as_n),
        .s_rw     (s_rw),
        .s_wr_data(s_wr_data),
        .s_cs_n   (s_cs_n),
        .s_rd_data(s_rd_data),
        .s_rdy_n  (s_rdy_n)
    );

    // ========================================================================
    // Clock Generation: 100 MHz
    // ========================================================================
    always #5 clk = ~clk;

    // ========================================================================
    // Slave Response Model (combinational — instant response)
    // ========================================================================
    always @(*) begin
        s_rd_data = {NUM_SLAVES*DATA_W{1'b0}};
        s_rdy_n   = {NUM_SLAVES{1'b1}};

        for (i = 0; i < NUM_SLAVES; i = i + 1) begin
            if ((s_as_n == 1'b0) && (s_cs_n[i] == 1'b0)) begin
                s_rd_data[i*DATA_W +: DATA_W] = slave_rsp_data[i*DATA_W +: DATA_W];
                s_rdy_n[i]                    = slave_rsp_rdy_n[i];
            end
        end
    end

    // ========================================================================
    // Helper Functions & Tasks
    // ========================================================================
    function [ADDR_W-1:0] make_addr;
        input integer slave_idx;
        input integer word_offset;
        begin
            make_addr = (slave_idx << IDX_LSB) | word_offset;
        end
    endfunction

    function [NUM_SLAVES-1:0] select_slave_n;
        input integer slave_idx;
        integer j;
        begin
            select_slave_n = {NUM_SLAVES{1'b1}};
            for (j = 0; j < NUM_SLAVES; j = j + 1) begin
                if (j == slave_idx)
                    select_slave_n[j] = 1'b0;
            end
        end
    endfunction

    task clear_master_inputs;
        begin
            m_req_n   = {NUM_MASTERS{1'b1}};
            m_addr    = {NUM_MASTERS*ADDR_W{1'b0}};
            m_as_n    = {NUM_MASTERS{1'b1}};
            m_rw      = {NUM_MASTERS{1'b1}};
            m_wr_data = {NUM_MASTERS*DATA_W{1'b0}};
        end
    endtask

    task init_slave_responses;
        begin
            slave_rsp_rdy_n = {NUM_SLAVES{1'b0}};       // All slaves default ready
            for (i = 0; i < NUM_SLAVES; i = i + 1) begin
                slave_rsp_data[i*DATA_W +: DATA_W] = 32'hA500_0000 + i;
            end
        end
    endtask

    task set_master;
        input integer          master_idx;
        input                  req_valid;
        input                  as_valid;
        input                  rw_value;
        input [ADDR_W-1:0]     addr_value;
        input [DATA_W-1:0]     wr_data_value;
        begin
            m_req_n[master_idx] = ~req_valid;
            m_as_n[master_idx]  = ~as_valid;
            m_rw[master_idx]    = rw_value;
            m_addr[master_idx*ADDR_W +: ADDR_W] = addr_value;
            m_wr_data[master_idx*DATA_W +: DATA_W] = wr_data_value;
        end
    endtask

    task release_master;
        input integer master_idx;
        begin
            m_req_n[master_idx] = 1'b1;
            m_as_n[master_idx]  = 1'b1;
            m_rw[master_idx]    = 1'b1;
            m_addr[master_idx*ADDR_W +: ADDR_W] = {ADDR_W{1'b0}};
            m_wr_data[master_idx*DATA_W +: DATA_W] = {DATA_W{1'b0}};
        end
    endtask

    // Wait one arbiter cycle: posedge registers grant, negedge is check point
    task wait_arb_cycle;
        begin
            @(posedge clk);
            @(negedge clk);
        end
    endtask

    // ========================================================================
    // Main Test Sequence
    // ========================================================================
    initial begin
        $display("============================================================");
        $display(" bus_top_tb : Start");
        $display("============================================================");
        err_cnt = 0;
        clk     = 1'b0;
        rst_n   = 1'b0;

        clear_master_inputs();
        init_slave_responses();

        // ---- Reset ----
        repeat (2) @(posedge clk);
        rst_n = 1'b1;
        @(negedge clk);

        // ================================================================
        // TEST 0 : Idle-bus defaults (mux outputs, no high-Z)
        // ================================================================
        $display("[TEST 0] Idle-bus defaults");
        #1;
        `CHECK(m_grnt_n === 4'b1111,             "T0: no grant on idle bus");
        `CHECK(s_as_n   === 1'b1,                "T0: s_as_n deasserted on idle");
        `CHECK(s_rw     === 1'b1,                "T0: s_rw default read on idle");
        `CHECK(s_addr   === {ADDR_W{1'b0}},      "T0: s_addr zero on idle");
        `CHECK(s_wr_data === {DATA_W{1'b0}},     "T0: s_wr_data zero on idle");
        `CHECK(s_cs_n   === {NUM_SLAVES{1'b1}},  "T0: all cs_n deasserted on idle");
        `CHECK(m_rd_data === {DATA_W{1'b0}},     "T0: m_rd_data zero on idle");
        `CHECK(m_rdy_n  === 1'b1,                "T0: m_rdy_n high on idle");

        // ================================================================
        // TEST 1 : Each master reads from every slave
        //          (registered grant: set signals → wait 1 cycle → check)
        // ================================================================
        $display("[TEST 1] Each master reads from every slave");
        for (mi = 0; mi < NUM_MASTERS; mi = mi + 1) begin
            for (si = 0; si < NUM_SLAVES; si = si + 1) begin
                clear_master_inputs();
                wait_arb_cycle();

                // Issue read request at negedge
                set_master(mi, 1'b1, 1'b1, 1'b1, make_addr(si, 7'h10 + si), 32'h0);
                // Wait for grant to register
                wait_arb_cycle();
                #1;

                `CHECK(m_grnt_n[mi] === 1'b0,
                    $sformatf("T1: M%0d should be granted for S%0d read", mi, si));
                `CHECK(s_cs_n === select_slave_n(si),
                    $sformatf("T1: S%0d cs_n should assert for M%0d read", si, mi));
                `CHECK(s_addr === make_addr(si, 7'h10 + si),
                    $sformatf("T1: addr mismatch M%0d->S%0d read", mi, si));
                `CHECK(s_rw === 1'b1,
                    $sformatf("T1: s_rw should be 1 for M%0d read", mi));
                `CHECK(s_as_n === 1'b0,
                    $sformatf("T1: s_as_n should assert for M%0d read", mi));
                `CHECK(m_rd_data === (32'hA500_0000 + si),
                    $sformatf("T1: rd_data mismatch M%0d<-S%0d", mi, si));
                `CHECK(m_rdy_n === 1'b0,
                    $sformatf("T1: m_rdy_n should be 0 for M%0d<-S%0d", mi, si));
            end
        end

        // ================================================================
        // TEST 2 : Each master writes to every slave
        // ================================================================
        $display("[TEST 2] Each master writes to every slave");
        for (mi = 0; mi < NUM_MASTERS; mi = mi + 1) begin
            for (si = 0; si < NUM_SLAVES; si = si + 1) begin
                clear_master_inputs();
                wait_arb_cycle();

                set_master(mi, 1'b1, 1'b1, 1'b0,
                           make_addr(si, 7'h20 + si),
                           32'hDEAD_0000 + (mi << 8) + si);
                wait_arb_cycle();
                #1;

                `CHECK(m_grnt_n[mi] === 1'b0,
                    $sformatf("T2: M%0d should be granted for S%0d write", mi, si));
                `CHECK(s_cs_n === select_slave_n(si),
                    $sformatf("T2: S%0d cs_n should assert for M%0d write", si, mi));
                `CHECK(s_addr === make_addr(si, 7'h20 + si),
                    $sformatf("T2: addr mismatch M%0d->S%0d write", mi, si));
                `CHECK(s_rw === 1'b0,
                    $sformatf("T2: s_rw should be 0 for M%0d write", mi));
                `CHECK(s_wr_data === (32'hDEAD_0000 + (mi << 8) + si),
                    $sformatf("T2: wr_data mismatch M%0d->S%0d", mi, si));
                `CHECK(m_rdy_n === 1'b0,
                    $sformatf("T2: m_rdy_n should be 0 for M%0d->S%0d", mi, si));
            end
        end

        // ================================================================
        // TEST 3 : Slave ready back-pressure propagation
        // ================================================================
        $display("[TEST 3] Slave ready back-pressure");
        clear_master_inputs();
        wait_arb_cycle();

        // M0 reads S3, but S3 not ready
        slave_rsp_rdy_n[3] = 1'b1;
        set_master(0, 1'b1, 1'b1, 1'b1, make_addr(3, 7'h00), 32'h0);
        wait_arb_cycle();
        #1;
        `CHECK(m_rdy_n === 1'b1, "T3a: m_rdy_n should be 1 when S3 not ready");

        // S3 becomes ready (combinational — visible immediately)
        slave_rsp_rdy_n[3] = 1'b0;
        #1;
        `CHECK(m_rdy_n === 1'b0, "T3b: m_rdy_n should be 0 when S3 becomes ready");

        // Other slaves' rdy_n should not affect the selected slave
        slave_rsp_rdy_n[0] = 1'b1;
        slave_rsp_rdy_n[7] = 1'b1;
        #1;
        `CHECK(m_rdy_n === 1'b0, "T3c: unselected slave rdy_n should not matter");
        slave_rsp_rdy_n[0] = 1'b0;
        slave_rsp_rdy_n[7] = 1'b0;

        // ================================================================
        // TEST 4 : Two-master contention — M0 beats M1
        // ================================================================
        $display("[TEST 4] Two-master contention: M0 > M1");
        clear_master_inputs();
        wait_arb_cycle();

        set_master(0, 1'b1, 1'b1, 1'b1, make_addr(0, 7'h40), 32'h0);
        set_master(1, 1'b1, 1'b1, 1'b1, make_addr(1, 7'h41), 32'h0);
        wait_arb_cycle();
        #1;
        `CHECK(m_grnt_n === 4'b1110, "T4: M0 should win over M1");
        `CHECK(s_addr === make_addr(0, 7'h40), "T4: bus should carry M0 address");
        `CHECK(s_cs_n === select_slave_n(0),   "T4: S0 should be selected");

        // ================================================================
        // TEST 5 : Two-master contention — M0 beats M2
        // ================================================================
        $display("[TEST 5] Two-master contention: M0 > M2");
        clear_master_inputs();
        wait_arb_cycle();

        set_master(0, 1'b1, 1'b1, 1'b1, make_addr(2, 7'h50), 32'h0);
        set_master(2, 1'b1, 1'b1, 1'b1, make_addr(3, 7'h51), 32'h0);
        wait_arb_cycle();
        #1;
        `CHECK(m_grnt_n === 4'b1110, "T5: M0 should win over M2");
        `CHECK(s_addr === make_addr(2, 7'h50), "T5: bus should carry M0 address");

        // ================================================================
        // TEST 6 : Two-master contention — M0 beats M3
        // ================================================================
        $display("[TEST 6] Two-master contention: M0 > M3");
        clear_master_inputs();
        wait_arb_cycle();

        set_master(0, 1'b1, 1'b1, 1'b1, make_addr(4, 7'h60), 32'h0);
        set_master(3, 1'b1, 1'b1, 1'b1, make_addr(5, 7'h61), 32'h0);
        wait_arb_cycle();
        #1;
        `CHECK(m_grnt_n === 4'b1110, "T6: M0 should win over M3");

        // ================================================================
        // TEST 7 : Two-master contention — M1 beats M2
        // ================================================================
        $display("[TEST 7] Two-master contention: M1 > M2");
        clear_master_inputs();
        wait_arb_cycle();

        set_master(1, 1'b1, 1'b1, 1'b1, make_addr(1, 7'h70), 32'h0);
        set_master(2, 1'b1, 1'b1, 1'b1, make_addr(2, 7'h71), 32'h0);
        wait_arb_cycle();
        #1;
        `CHECK(m_grnt_n === 4'b1101, "T7: M1 should win over M2");
        `CHECK(s_addr === make_addr(1, 7'h70), "T7: bus should carry M1 address");

        // ================================================================
        // TEST 8 : Two-master contention — M1 beats M3
        // ================================================================
        $display("[TEST 8] Two-master contention: M1 > M3");
        clear_master_inputs();
        wait_arb_cycle();

        set_master(1, 1'b1, 1'b1, 1'b1, make_addr(3, 7'h78), 32'h0);
        set_master(3, 1'b1, 1'b1, 1'b1, make_addr(4, 7'h79), 32'h0);
        wait_arb_cycle();
        #1;
        `CHECK(m_grnt_n === 4'b1101, "T8: M1 should win over M3");

        // ================================================================
        // TEST 9 : Two-master contention — M2 beats M3
        // ================================================================
        $display("[TEST 9] Two-master contention: M2 > M3");
        clear_master_inputs();
        wait_arb_cycle();

        set_master(2, 1'b1, 1'b1, 1'b1, make_addr(5, 7'h01), 32'h0);
        set_master(3, 1'b1, 1'b1, 1'b1, make_addr(6, 7'h02), 32'h0);
        wait_arb_cycle();
        #1;
        `CHECK(m_grnt_n === 4'b1011, "T9: M2 should win over M3");
        `CHECK(s_addr === make_addr(5, 7'h01), "T9: bus should carry M2 address");

        // ================================================================
        // TEST 10 : Three-master contention — M0 > M1 > M2
        // ================================================================
        $display("[TEST 10] Three-master contention: M0 > M1 > M2");
        clear_master_inputs();
        wait_arb_cycle();

        set_master(0, 1'b1, 1'b1, 1'b1, make_addr(0, 7'h01), 32'h0);
        set_master(1, 1'b1, 1'b1, 1'b1, make_addr(1, 7'h02), 32'h0);
        set_master(2, 1'b1, 1'b1, 1'b1, make_addr(2, 7'h03), 32'h0);
        wait_arb_cycle();
        #1;
        `CHECK(m_grnt_n === 4'b1110, "T10: M0 should win 3-way contention");

        // ================================================================
        // TEST 11 : Four-master contention — M0 wins
        // ================================================================
        $display("[TEST 11] Four-master contention: M0 wins");
        clear_master_inputs();
        wait_arb_cycle();

        set_master(0, 1'b1, 1'b1, 1'b1, make_addr(0, 7'h0A), 32'h0);
        set_master(1, 1'b1, 1'b1, 1'b1, make_addr(1, 7'h0B), 32'h0);
        set_master(2, 1'b1, 1'b1, 1'b1, make_addr(2, 7'h0C), 32'h0);
        set_master(3, 1'b1, 1'b1, 1'b1, make_addr(3, 7'h0D), 32'h0);
        wait_arb_cycle();
        #1;
        `CHECK(m_grnt_n === 4'b1110, "T11: M0 should win 4-way contention");
        `CHECK(s_addr === make_addr(0, 7'h0A), "T11: bus should carry M0 address");
        `CHECK(s_cs_n === select_slave_n(0),   "T11: S0 should be selected");

        // ================================================================
        // TEST 12 : Non-preemptive ownership
        //           M1 owns bus → M0 arrives → M1 keeps → M1 releases → M0
        // ================================================================
        $display("[TEST 12] Non-preemptive ownership");
        clear_master_inputs();
        wait_arb_cycle();

        // M1 alone requests
        set_master(1, 1'b1, 1'b1, 1'b1, make_addr(4, 7'h30), 32'h0);
        wait_arb_cycle();
        #1;
        `CHECK(m_grnt_n[1] === 1'b0, "T12a: M1 should get grant when alone");

        // M0 also requests — M1 should keep (non-preemptive)
        set_master(0, 1'b1, 1'b1, 1'b1, make_addr(7, 7'h31), 32'h0);
        wait_arb_cycle();
        #1;
        `CHECK(m_grnt_n[1] === 1'b0, "T12b: M1 should keep bus (non-preemptive)");
        `CHECK(m_grnt_n[0] === 1'b1, "T12b: M0 should NOT be granted while M1 owns");
        `CHECK(s_addr === make_addr(4, 7'h30), "T12b: bus should still carry M1 address");

        // M1 releases — M0 takes over
        release_master(1);
        wait_arb_cycle();
        #1;
        `CHECK(m_grnt_n[0] === 1'b0, "T12c: M0 should win after M1 releases");
        `CHECK(s_addr === make_addr(7, 7'h31), "T12c: bus should carry M0 address");
        `CHECK(s_cs_n === select_slave_n(7),   "T12c: S7 should be selected");

        // ================================================================
        // TEST 13 : Priority chain after owner release
        //           M3 owns → M0,M1,M2 wait → M3 releases → M0 → M1 → M2
        // ================================================================
        $display("[TEST 13] Priority chain after owner release");
        clear_master_inputs();
        wait_arb_cycle();

        // M3 gets the bus alone
        set_master(3, 1'b1, 1'b1, 1'b1, make_addr(6, 7'h01), 32'h0);
        wait_arb_cycle();
        #1;
        `CHECK(m_grnt_n[3] === 1'b0, "T13a: M3 should get grant when alone");

        // M0, M1, M2 all request while M3 holds
        set_master(0, 1'b1, 1'b1, 1'b1, make_addr(0, 7'h10), 32'h0);
        set_master(1, 1'b1, 1'b1, 1'b1, make_addr(1, 7'h11), 32'h0);
        set_master(2, 1'b1, 1'b1, 1'b1, make_addr(2, 7'h12), 32'h0);
        wait_arb_cycle();
        #1;
        `CHECK(m_grnt_n[3] === 1'b0, "T13b: M3 should keep bus despite higher-pri requests");

        // M3 releases → M0 wins
        release_master(3);
        wait_arb_cycle();
        #1;
        `CHECK(m_grnt_n === 4'b1110, "T13c: M0 should win after M3 releases");
        `CHECK(s_addr === make_addr(0, 7'h10), "T13c: bus should carry M0 address");

        // M0 releases → M1 wins
        release_master(0);
        wait_arb_cycle();
        #1;
        `CHECK(m_grnt_n === 4'b1101, "T13d: M1 should win after M0 releases");
        `CHECK(s_addr === make_addr(1, 7'h11), "T13d: bus should carry M1 address");

        // M1 releases → M2 wins
        release_master(1);
        wait_arb_cycle();
        #1;
        `CHECK(m_grnt_n === 4'b1011, "T13e: M2 should win after M1 releases");
        `CHECK(s_addr === make_addr(2, 7'h12), "T13e: bus should carry M2 address");

        // M2 releases → bus idle
        release_master(2);
        wait_arb_cycle();
        #1;
        `CHECK(m_grnt_n === 4'b1111, "T13f: bus should be idle after all release");

        // ================================================================
        // TEST 14 : Owner switches target slave mid-ownership
        // ================================================================
        $display("[TEST 14] Owner switches target slave mid-ownership");
        clear_master_inputs();
        wait_arb_cycle();

        // M2 reads S0
        set_master(2, 1'b1, 1'b1, 1'b1, make_addr(0, 7'h00), 32'h0);
        wait_arb_cycle();
        #1;
        `CHECK(s_cs_n === select_slave_n(0), "T14a: S0 selected");
        `CHECK(m_rd_data === 32'hA500_0000,  "T14a: S0 data returned");

        // M2 switches to S7
        set_master(2, 1'b1, 1'b1, 1'b1, make_addr(7, 7'h04), 32'h0);
        wait_arb_cycle();
        #1;
        `CHECK(s_cs_n === select_slave_n(7), "T14b: S7 selected after switch");
        `CHECK(m_rd_data === 32'hA500_0007,  "T14b: S7 data returned");

        // M2 switches to S4 write
        set_master(2, 1'b1, 1'b1, 1'b0, make_addr(4, 7'h08), 32'hBEEF_CAFE);
        wait_arb_cycle();
        #1;
        `CHECK(s_cs_n === select_slave_n(4),   "T14c: S4 selected for write");
        `CHECK(s_rw === 1'b0,                  "T14c: s_rw low for write");
        `CHECK(s_wr_data === 32'hBEEF_CAFE,    "T14c: write data correct");

        // ================================================================
        // TEST 15 : Rapid ownership handoff
        // ================================================================
        $display("[TEST 15] Rapid ownership handoff");
        clear_master_inputs();
        wait_arb_cycle();

        // Both request
        set_master(0, 1'b1, 1'b1, 1'b1, make_addr(0, 7'h01), 32'h0);
        set_master(1, 1'b1, 1'b1, 1'b1, make_addr(1, 7'h02), 32'h0);
        wait_arb_cycle();
        #1;
        `CHECK(m_grnt_n === 4'b1110, "T15a: M0 wins initial contention");

        // M0 releases — M1 should take over on next cycle
        release_master(0);
        wait_arb_cycle();
        #1;
        `CHECK(m_grnt_n === 4'b1101, "T15b: M1 takes over after M0 releases");
        `CHECK(s_addr === make_addr(1, 7'h02), "T15b: bus carries M1 address");

        // ================================================================
        // TEST 16 : Bus returns to clean idle state
        // ================================================================
        $display("[TEST 16] Bus returns to clean idle state");
        clear_master_inputs();
        wait_arb_cycle();
        #1;
        `CHECK(m_grnt_n  === 4'b1111,            "T16: no grant on idle");
        `CHECK(s_as_n    === 1'b1,               "T16: s_as_n deasserted on idle");
        `CHECK(s_cs_n    === {NUM_SLAVES{1'b1}}, "T16: all cs_n deasserted");
        `CHECK(m_rdy_n   === 1'b1,               "T16: m_rdy_n high on idle");
        `CHECK(s_addr    === {ADDR_W{1'b0}},     "T16: s_addr zero on idle");
        `CHECK(s_wr_data === {DATA_W{1'b0}},     "T16: s_wr_data zero on idle");
        `CHECK(m_rd_data === {DATA_W{1'b0}},     "T16: m_rd_data zero on idle");

        // ================================================================
        // TEST 17 : Transaction lock — slow slave holds grant stable
        // ================================================================
        $display("[TEST 17] Transaction lock with slow slave");
        clear_master_inputs();
        wait_arb_cycle();

        // M1 requests S2, S2 is slow (not ready)
        slave_rsp_rdy_n[2] = 1'b1;
        set_master(1, 1'b1, 1'b1, 1'b1, make_addr(2, 7'h00), 32'h0);
        wait_arb_cycle();
        #1;
        `CHECK(m_grnt_n[1] === 1'b0, "T17a: M1 granted");
        `CHECK(m_rdy_n === 1'b1,     "T17a: slave not ready");

        // bus_lock should engage next cycle. Meanwhile M0 requests.
        set_master(0, 1'b1, 1'b1, 1'b1, make_addr(0, 7'h01), 32'h0);
        wait_arb_cycle();
        #1;
        // bus_lock was set — M1 keeps even though M0 is higher priority
        `CHECK(m_grnt_n[1] === 1'b0, "T17b: M1 keeps grant (bus locked, slave not ready)");
        `CHECK(m_grnt_n[0] === 1'b1, "T17b: M0 not granted during lock");

        // S2 responds
        slave_rsp_rdy_n[2] = 1'b0;
        #1;
        `CHECK(m_rdy_n === 1'b0, "T17c: m_rdy_n goes low when S2 responds");

        // Lock releases on next cycle. M1 still has req, so non-preemptive keeps it.
        // But if M1 releases, M0 should get the bus.
        release_master(1);
        wait_arb_cycle();
        #1;
        `CHECK(m_grnt_n[0] === 1'b0, "T17d: M0 gets bus after lock release and M1 release");

        // Cleanup
        slave_rsp_rdy_n[2] = 1'b0;
        clear_master_inputs();
        wait_arb_cycle();

        // ================================================================
        // TEST 18 : Multi-cycle slow slave — lock holds across cycles
        // ================================================================
        $display("[TEST 18] Multi-cycle slow slave lock");
        clear_master_inputs();
        wait_arb_cycle();

        slave_rsp_rdy_n[5] = 1'b1;
        set_master(2, 1'b1, 1'b1, 1'b1, make_addr(5, 7'h04), 32'h0);
        set_master(0, 1'b1, 1'b1, 1'b1, make_addr(0, 7'h05), 32'h0);
        wait_arb_cycle();
        #1;
        // M0 wins first arbitration (higher priority)
        `CHECK(m_grnt_n[0] === 1'b0, "T18a: M0 wins initial arb");

        // M0 completes quickly (S0 responds immediately). Release M0.
        release_master(0);
        wait_arb_cycle();
        #1;
        // M2 gets bus now, targets S5 (slow)
        `CHECK(m_grnt_n[2] === 1'b0, "T18b: M2 gets bus after M0 releases");
        `CHECK(m_rdy_n === 1'b1,     "T18b: S5 not ready");

        // Higher-priority M0 comes back while S5 is still slow
        set_master(0, 1'b1, 1'b1, 1'b1, make_addr(1, 7'h06), 32'h0);
        wait_arb_cycle();
        #1;
        `CHECK(m_grnt_n[2] === 1'b0, "T18c: M2 keeps grant (locked by slow S5)");

        // Wait another cycle, still locked
        wait_arb_cycle();
        #1;
        `CHECK(m_grnt_n[2] === 1'b0, "T18d: M2 still holds after 2 cycles");

        // S5 responds
        slave_rsp_rdy_n[5] = 1'b0;
        wait_arb_cycle();
        #1;
        // Lock released. M2 still has req_n active, so non-preemptive keeps it.
        `CHECK(m_grnt_n[2] === 1'b0, "T18e: M2 still owns (non-preemptive, req active)");

        // M2 releases → M0 takes over
        release_master(2);
        wait_arb_cycle();
        #1;
        `CHECK(m_grnt_n[0] === 1'b0, "T18f: M0 gets bus after M2 releases");

        // Cleanup
        slave_rsp_rdy_n[5] = 1'b0;
        clear_master_inputs();
        wait_arb_cycle();

        // ================================================================
        // Summary
        // ================================================================
        $display("============================================================");
        if (err_cnt == 0)
            $display(" PASS : bus_top_tb — all tests passed");
        else
            $display(" FAIL : bus_top_tb — %0d error(s)", err_cnt);
        $display("============================================================");
        $finish;
    end

    // Timeout watchdog
    initial begin
        #500_000;
        $display("TIMEOUT: bus_top_tb exceeded 500 us");
        $finish(1);
    end

endmodule

`undef CHECK
