`timescale 1ns/1ps

// ============================================================================
// Project     : simpleRISC-V
// Module      : bus_top_tb
// Description : Directed testbench for bus_top.
//
//               Stimulus convention:
//                 - ALL master inputs are driven on @(negedge clk) only.
//                 - ALL checks are performed on @(negedge clk) only
//                   (after posedge has registered arbiter grant).
//                 - No #1 delays — avoids combinational glitches on m_rdy_n
//                   caused by mid-cycle input changes rippling through the
//                   purely combinational master_mux -> addr_dec -> slave_mux.
//
//               Slave model: registered, configurable 1-3 cycle latency.
//
//               Test coverage:
//                 [T0]  Idle-bus defaults
//                 [T1]  Each master reads from every slave
//                 [T2]  Each master writes to every slave
//                 [T3]  Slave latency verification (S3=3cyc, S0=1cyc)
//                 [T4]  Two-master contention: M0 > M1
//                 [T5]  Two-master contention: M0 > M2
//                 [T6]  Two-master contention: M0 > M3
//                 [T7]  Two-master contention: M1 > M2
//                 [T8]  Two-master contention: M1 > M3
//                 [T9]  Two-master contention: M2 > M3
//                 [T10] Three-master contention: M0 > M1 > M2
//                 [T11] Four-master contention: M0 wins
//                 [T12] Non-preemptive ownership
//                 [T13] Priority chain after owner release
//                 [T14] Owner switches target slave mid-ownership
//                 [T15] Rapid ownership handoff
//                 [T16] Bus returns to clean idle state
//                 [T17] Valid deasserted between transactions (bus hold)
// ============================================================================

`include "../../src/bus/bus_defines.vh"

`define CHECK(cond, msg)                                                     \
    if (!(cond)) begin                                                       \
        $display("FAIL: %0s (time=%0t, mi=%0d, si=%0d)", msg, $time, mi, si);\
        err_cnt = err_cnt + 1;                                               \
    end

module bus_top_tb;

    // ========================================================================
    // Parameters
    // ========================================================================
    localparam integer NUM_MASTERS = `SRV_BUS_MASTER_NUM;
    localparam integer NUM_SLAVES  = `SRV_BUS_SLAVE_NUM;
    localparam integer ADDR_W      = `SRV_BUS_ADDR_W;
    localparam integer DATA_W      = `SRV_BUS_DATA_W;
    localparam integer IDX_MSB     = `SRV_BUS_SLAVE_IDX_MSB;
    localparam integer IDX_LSB     = `SRV_BUS_SLAVE_IDX_LSB;

    // ========================================================================
    // DUT Signals
    // ========================================================================
    reg                              clk;
    reg                              rst_n;

    // Master-side
    reg  [NUM_MASTERS-1:0]           m_req_n;
    wire [NUM_MASTERS-1:0]           m_grnt_n;
    reg  [NUM_MASTERS*ADDR_W-1:0]    m_addr;
    reg  [NUM_MASTERS-1:0]           m_valid;
    reg  [NUM_MASTERS-1:0]           m_rw;
    reg  [NUM_MASTERS*DATA_W-1:0]    m_wr_data;
    wire [DATA_W-1:0]                m_rd_data;
    wire                             m_rdy_n;

    // Slave-side
    wire [ADDR_W-1:0]                s_addr;
    wire                             s_valid;
    wire                             s_rw;
    wire [DATA_W-1:0]                s_wr_data;
    wire [NUM_SLAVES-1:0]            s_cs_n;
    reg  [NUM_SLAVES*DATA_W-1:0]     s_rd_data;
    reg  [NUM_SLAVES-1:0]            s_rdy_n;

    // Slave model internals
    reg  [NUM_SLAVES*DATA_W-1:0]     slave_rsp_data;
    reg  [1:0]                       slave_delay_cnt [0:NUM_SLAVES-1];
    reg  [1:0]                       slave_delay_cfg [0:NUM_SLAVES-1];

    integer err_cnt;
    integer i;
    integer mi, si;
    integer k;

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
        .m_valid  (m_valid),
        .m_rw     (m_rw),
        .m_wr_data(m_wr_data),
        .m_rd_data(m_rd_data),
        .m_rdy_n  (m_rdy_n),
        .s_addr   (s_addr),
        .s_valid  (s_valid),
        .s_rw     (s_rw),
        .s_wr_data(s_wr_data),
        .s_cs_n   (s_cs_n),
        .s_rd_data(s_rd_data),
        .s_rdy_n  (s_rdy_n)
    );

    // ========================================================================
    // Clock: 100 MHz, period = 10 ns
    // ========================================================================
    always #5 clk = ~clk;

    // ========================================================================
    // Slave Response Model (registered, 1-3 cycle latency)
    //
    // When cs_n[k]=0 && s_valid=1, slave counts up each posedge.
    // After slave_delay_cfg[k] cycles, it asserts rdy_n=0 and drives rd_data.
    // When deselected, counter resets immediately.
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            s_rdy_n   <= {NUM_SLAVES{1'b1}};
            s_rd_data <= {NUM_SLAVES*DATA_W{1'b0}};
            for (k = 0; k < NUM_SLAVES; k = k + 1)
                slave_delay_cnt[k] <= 2'd0;
        end else begin
            for (k = 0; k < NUM_SLAVES; k = k + 1) begin
                if (s_valid && !s_cs_n[k]) begin
                    if (slave_delay_cnt[k] < slave_delay_cfg[k]) begin
                        slave_delay_cnt[k]             <= slave_delay_cnt[k] + 2'd1;
                        s_rdy_n[k]                     <= 1'b1;
                        s_rd_data[k*DATA_W +: DATA_W]  <= {DATA_W{1'b0}};
                    end else begin
                        s_rdy_n[k]                     <= 1'b0;
                        s_rd_data[k*DATA_W +: DATA_W]  <= slave_rsp_data[k*DATA_W +: DATA_W];
                    end
                end else begin
                    slave_delay_cnt[k]             <= 2'd0;
                    s_rdy_n[k]                     <= 1'b1;
                    s_rd_data[k*DATA_W +: DATA_W]  <= {DATA_W{1'b0}};
                end
            end
        end
    end

    // ========================================================================
    // Helper: Build slave address from slave index + offset
    // ========================================================================
    function [ADDR_W-1:0] make_addr;
        input integer slave_idx;
        input integer word_offset;
        begin
            make_addr = (slave_idx << IDX_LSB) | word_offset;
        end
    endfunction

    // ========================================================================
    // Helper: Expected cs_n for a given slave index
    // ========================================================================
    function [NUM_SLAVES-1:0] expect_cs_n;
        input integer slave_idx;
        integer j;
        begin
            expect_cs_n = {NUM_SLAVES{1'b1}};
            for (j = 0; j < NUM_SLAVES; j = j + 1)
                if (j == slave_idx)
                    expect_cs_n[j] = 1'b0;
        end
    endfunction

    // ========================================================================
    // Task: Drive all master inputs to idle (call only at negedge clk)
    // ========================================================================
    task clear_all_masters;
        begin
            m_req_n   = {NUM_MASTERS{1'b1}};
            m_addr    = {NUM_MASTERS*ADDR_W{1'b0}};
            m_valid   = {NUM_MASTERS{1'b0}};
            m_rw      = {NUM_MASTERS{1'b1}};
            m_wr_data = {NUM_MASTERS*DATA_W{1'b0}};
        end
    endtask

    // ========================================================================
    // Task: Configure one master's signals (call only at negedge clk)
    // ========================================================================
    task drive_master;
        input integer          idx;
        input                  req;        // 1 = request bus
        input                  valid;      // 1 = transaction active
        input                  rw;         // 1 = read, 0 = write
        input [ADDR_W-1:0]    addr;
        input [DATA_W-1:0]    wdata;
        begin
            m_req_n[idx]                       = ~req;
            m_valid[idx]                       = valid;
            m_rw[idx]                          = rw;
            m_addr[idx*ADDR_W +: ADDR_W]       = addr;
            m_wr_data[idx*DATA_W +: DATA_W]    = wdata;
        end
    endtask

    // ========================================================================
    // Task: Release one master (call only at negedge clk)
    // ========================================================================
    task release_master;
        input integer idx;
        begin
            m_req_n[idx]                       = 1'b1;
            m_valid[idx]                       = 1'b0;
            m_rw[idx]                          = 1'b1;
            m_addr[idx*ADDR_W +: ADDR_W]       = {ADDR_W{1'b0}};
            m_wr_data[idx*DATA_W +: DATA_W]    = {DATA_W{1'b0}};
        end
    endtask

    // ========================================================================
    // Task: Wait one full bus cycle (negedge -> posedge -> negedge)
    //       After this task, we are at negedge — safe to check & drive.
    // ========================================================================
    task wait_bus_cycle;
        begin
            @(posedge clk);   // arbiter registers new grant
            @(negedge clk);   // safe check/drive point
        end
    endtask

    // ========================================================================
    // Task: Wait for m_rdy_n=0, checking only at negedge clk.
    //       Returns at negedge with m_rdy_n=0.
    //       Timeout after 100 cycles.
    // ========================================================================
    task wait_slave_ready;
        integer timeout;
        begin
            timeout = 0;
            while (m_rdy_n !== 1'b0 && timeout < 100) begin
                @(posedge clk);
                @(negedge clk);
                timeout = timeout + 1;
            end
            if (timeout >= 100)
                $display("ERROR: wait_slave_ready timeout at time=%0t", $time);
        end
    endtask

    // ========================================================================
    // Task: Initialize slave response data and latency configuration
    // ========================================================================
    task init_slave_config;
        begin
            for (i = 0; i < NUM_SLAVES; i = i + 1)
                slave_rsp_data[i*DATA_W +: DATA_W] = 32'hA500_0000 + i;

            slave_delay_cfg[0] = 2'd1;   // 1 extra cycle
            slave_delay_cfg[1] = 2'd2;   // 2 extra cycles
            slave_delay_cfg[2] = 2'd1;
            slave_delay_cfg[3] = 2'd3;   // 3 extra cycles (longest)
            slave_delay_cfg[4] = 2'd2;
            slave_delay_cfg[5] = 2'd1;
            slave_delay_cfg[6] = 2'd3;
            slave_delay_cfg[7] = 2'd2;
        end
    endtask

    // ========================================================================
    // Main Test Sequence
    //
    // Convention: every stimulus change happens at @(negedge clk).
    //   1. Drive inputs at negedge
    //   2. posedge -> arbiter registers grant, slave model updates
    //   3. negedge -> check outputs, drive next inputs
    // ========================================================================
    initial begin
        $display("============================================================");
        $display(" bus_top_tb : Start");
        $display("============================================================");

        // -- Initialization --
        err_cnt = 0;
        clk     = 1'b0;
        rst_n   = 1'b0;
        clear_all_masters();
        init_slave_config();

        // -- Reset: hold for 2 cycles, release at negedge --
        repeat (2) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;
        // Let reset propagate through one full cycle
        wait_bus_cycle();

        // ================================================================
        // TEST 0 : Idle-bus defaults
        // ================================================================
        $display("[T0] Idle-bus defaults");
        mi = 0; si = 0;
        `CHECK(m_grnt_n  === 4'b1111,            "T0: no grant on idle bus")
        `CHECK(s_valid   === 1'b0,               "T0: s_valid should be low")
        `CHECK(s_rw      === 1'b1,               "T0: s_rw default read")
        `CHECK(s_addr    === {ADDR_W{1'b0}},     "T0: s_addr should be zero")
        `CHECK(s_wr_data === {DATA_W{1'b0}},     "T0: s_wr_data should be zero")
        `CHECK(s_cs_n    === {NUM_SLAVES{1'b1}}, "T0: all cs_n deasserted")
        `CHECK(m_rd_data === {DATA_W{1'b0}},     "T0: m_rd_data should be zero")
        `CHECK(m_rdy_n   === 1'b1,               "T0: m_rdy_n should be high")

        // ================================================================
        // TEST 1 : Each master reads from every slave
        // ================================================================
        $display("[T1] Each master reads from every slave");
        for (mi = 0; mi < NUM_MASTERS; mi = mi + 1) begin
            for (si = 0; si < NUM_SLAVES; si = si + 1) begin
                // Idle cycle: clear all masters
                @(negedge clk);
                clear_all_masters();
                wait_bus_cycle();

                // Drive read request
                @(negedge clk);
                drive_master(mi, 1, 1, 1, make_addr(si, 7'h10 + si), 32'h0);

                // Wait for grant to register
                wait_bus_cycle();

                // Check bus signals
                `CHECK(m_grnt_n[mi] === 1'b0,           "T1: grant expected")
                `CHECK(s_cs_n === expect_cs_n(si),       "T1: cs_n mismatch")
                `CHECK(s_addr === make_addr(si, 7'h10+si), "T1: addr mismatch")
                `CHECK(s_rw   === 1'b1,                  "T1: s_rw should be read")
                `CHECK(s_valid === 1'b1,                 "T1: s_valid should be high")
                `CHECK(m_rdy_n === 1'b1,                 "T1: m_rdy_n should be high before slave responds")

                // Wait for slave to respond
                wait_slave_ready();
                `CHECK(m_rd_data === (32'hA500_0000 + si), "T1: rd_data mismatch")
                `CHECK(m_rdy_n === 1'b0,                   "T1: m_rdy_n should be low after slave responds")
            end
        end

        // ================================================================
        // TEST 2 : Each master writes to every slave
        // ================================================================
        $display("[T2] Each master writes to every slave");
        for (mi = 0; mi < NUM_MASTERS; mi = mi + 1) begin
            for (si = 0; si < NUM_SLAVES; si = si + 1) begin
                @(negedge clk);
                clear_all_masters();
                wait_bus_cycle();

                @(negedge clk);
                drive_master(mi, 1, 1, 0,
                             make_addr(si, 7'h20 + si),
                             32'hDEAD_0000 + (mi << 8) + si);

                wait_bus_cycle();

                `CHECK(m_grnt_n[mi] === 1'b0,           "T2: grant expected")
                `CHECK(s_cs_n === expect_cs_n(si),       "T2: cs_n mismatch")
                `CHECK(s_addr === make_addr(si, 7'h20+si), "T2: addr mismatch")
                `CHECK(s_rw   === 1'b0,                  "T2: s_rw should be write")
                `CHECK(s_wr_data === (32'hDEAD_0000 + (mi << 8) + si), "T2: wr_data mismatch")
                `CHECK(m_rdy_n === 1'b1,                 "T2: m_rdy_n should be high before slave responds")

                wait_slave_ready();
                `CHECK(m_rdy_n === 1'b0, "T2: m_rdy_n should be low after slave responds")
            end
        end

        // ================================================================
        // TEST 3 : Slave latency verification
        //          S3 has delay_cfg=3, expect 4 posedges to respond.
        //          S0 has delay_cfg=1, expect 2 posedges to respond.
        // ================================================================
        $display("[T3] Slave latency (S3, delay=3)");
        mi = 0; si = 3;
        begin : test3_block
            integer rdy_cnt;

            // --- S3 (cfg=3) ---
            @(negedge clk);
            clear_all_masters();
            wait_bus_cycle();

            @(negedge clk);
            drive_master(0, 1, 1, 1, make_addr(3, 7'h00), 32'h0);
            wait_bus_cycle();

            `CHECK(m_grnt_n[0] === 1'b0, "T3: M0 should be granted")
            `CHECK(s_cs_n[3]   === 1'b0, "T3: S3 should be selected")

            rdy_cnt = 0;
            while (m_rdy_n !== 1'b0 && rdy_cnt < 20) begin
                @(posedge clk);
                @(negedge clk);
                rdy_cnt = rdy_cnt + 1;
            end

            // cfg=3: 3 not-ready cycles + 1 response cycle = 4 posedges
            `CHECK(rdy_cnt === 4,           "T3: S3 should take 4 cycles (cfg=3)")
            `CHECK(m_rdy_n === 1'b0,        "T3: m_rdy_n should be low")
            `CHECK(m_rd_data === 32'hA500_0003, "T3: S3 data mismatch")

            // --- S0 (cfg=1) ---
            $display("[T3b] Slave latency (S0, delay=1)");
            si = 0;

            @(negedge clk);
            clear_all_masters();
            wait_bus_cycle();

            @(negedge clk);
            drive_master(0, 1, 1, 1, make_addr(0, 7'h00), 32'h0);
            wait_bus_cycle();

            rdy_cnt = 0;
            while (m_rdy_n !== 1'b0 && rdy_cnt < 20) begin
                @(posedge clk);
                @(negedge clk);
                rdy_cnt = rdy_cnt + 1;
            end

            // cfg=1: 1 not-ready + 1 response = 2 posedges
            `CHECK(rdy_cnt === 2,               "T3b: S0 should take 2 cycles (cfg=1)")
            `CHECK(m_rdy_n === 1'b0,            "T3b: m_rdy_n should be low")
            `CHECK(m_rd_data === 32'hA500_0000, "T3b: S0 data mismatch")
        end

        // ================================================================
        // TEST 4-9 : Two-master contention (all pairs)
        // ================================================================

        // T4: M0 > M1
        $display("[T4] Contention: M0 > M1");
        mi = 0; si = 0;
        @(negedge clk);
        clear_all_masters();
        wait_bus_cycle();
        @(negedge clk);
        drive_master(0, 1, 1, 1, make_addr(0, 7'h40), 32'h0);
        drive_master(1, 1, 1, 1, make_addr(1, 7'h41), 32'h0);
        wait_bus_cycle();
        `CHECK(m_grnt_n === 4'b1110,              "T4: M0 should win")
        `CHECK(s_addr   === make_addr(0, 7'h40),  "T4: bus carries M0 addr")
        `CHECK(s_cs_n   === expect_cs_n(0),        "T4: S0 selected")

        // T5: M0 > M2
        $display("[T5] Contention: M0 > M2");
        @(negedge clk);
        clear_all_masters();
        wait_bus_cycle();
        @(negedge clk);
        drive_master(0, 1, 1, 1, make_addr(2, 7'h50), 32'h0);
        drive_master(2, 1, 1, 1, make_addr(3, 7'h51), 32'h0);
        wait_bus_cycle();
        `CHECK(m_grnt_n === 4'b1110,              "T5: M0 should win")
        `CHECK(s_addr   === make_addr(2, 7'h50),  "T5: bus carries M0 addr")

        // T6: M0 > M3
        $display("[T6] Contention: M0 > M3");
        @(negedge clk);
        clear_all_masters();
        wait_bus_cycle();
        @(negedge clk);
        drive_master(0, 1, 1, 1, make_addr(4, 7'h60), 32'h0);
        drive_master(3, 1, 1, 1, make_addr(5, 7'h61), 32'h0);
        wait_bus_cycle();
        `CHECK(m_grnt_n === 4'b1110, "T6: M0 should win")

        // T7: M1 > M2
        $display("[T7] Contention: M1 > M2");
        @(negedge clk);
        clear_all_masters();
        wait_bus_cycle();
        @(negedge clk);
        drive_master(1, 1, 1, 1, make_addr(1, 7'h70), 32'h0);
        drive_master(2, 1, 1, 1, make_addr(2, 7'h71), 32'h0);
        wait_bus_cycle();
        `CHECK(m_grnt_n === 4'b1101,              "T7: M1 should win")
        `CHECK(s_addr   === make_addr(1, 7'h70),  "T7: bus carries M1 addr")

        // T8: M1 > M3
        $display("[T8] Contention: M1 > M3");
        @(negedge clk);
        clear_all_masters();
        wait_bus_cycle();
        @(negedge clk);
        drive_master(1, 1, 1, 1, make_addr(3, 7'h78), 32'h0);
        drive_master(3, 1, 1, 1, make_addr(4, 7'h79), 32'h0);
        wait_bus_cycle();
        `CHECK(m_grnt_n === 4'b1101, "T8: M1 should win")

        // T9: M2 > M3
        $display("[T9] Contention: M2 > M3");
        @(negedge clk);
        clear_all_masters();
        wait_bus_cycle();
        @(negedge clk);
        drive_master(2, 1, 1, 1, make_addr(5, 7'h01), 32'h0);
        drive_master(3, 1, 1, 1, make_addr(6, 7'h02), 32'h0);
        wait_bus_cycle();
        `CHECK(m_grnt_n === 4'b1011,              "T9: M2 should win")
        `CHECK(s_addr   === make_addr(5, 7'h01),  "T9: bus carries M2 addr")

        // ================================================================
        // TEST 10 : Three-master contention — M0 > M1 > M2
        // ================================================================
        $display("[T10] 3-way contention: M0 wins");
        @(negedge clk);
        clear_all_masters();
        wait_bus_cycle();
        @(negedge clk);
        drive_master(0, 1, 1, 1, make_addr(0, 7'h01), 32'h0);
        drive_master(1, 1, 1, 1, make_addr(1, 7'h02), 32'h0);
        drive_master(2, 1, 1, 1, make_addr(2, 7'h03), 32'h0);
        wait_bus_cycle();
        `CHECK(m_grnt_n === 4'b1110, "T10: M0 should win")

        // ================================================================
        // TEST 11 : Four-master contention — M0 wins
        // ================================================================
        $display("[T11] 4-way contention: M0 wins");
        @(negedge clk);
        clear_all_masters();
        wait_bus_cycle();
        @(negedge clk);
        drive_master(0, 1, 1, 1, make_addr(0, 7'h0A), 32'h0);
        drive_master(1, 1, 1, 1, make_addr(1, 7'h0B), 32'h0);
        drive_master(2, 1, 1, 1, make_addr(2, 7'h0C), 32'h0);
        drive_master(3, 1, 1, 1, make_addr(3, 7'h0D), 32'h0);
        wait_bus_cycle();
        `CHECK(m_grnt_n === 4'b1110,              "T11: M0 should win")
        `CHECK(s_addr   === make_addr(0, 7'h0A),  "T11: bus carries M0 addr")
        `CHECK(s_cs_n   === expect_cs_n(0),        "T11: S0 selected")

        // ================================================================
        // TEST 12 : Non-preemptive ownership
        //   M1 owns bus -> M0 arrives -> M1 keeps ->
        //   M1 releases  -> M0 takes over
        // ================================================================
        $display("[T12] Non-preemptive ownership");
        mi = 1; si = 4;

        // M1 alone requests — reads S4
        @(negedge clk);
        clear_all_masters();
        wait_bus_cycle();
        @(negedge clk);
        drive_master(1, 1, 1, 1, make_addr(4, 7'h30), 32'h0);
        wait_bus_cycle();
        `CHECK(m_grnt_n[1] === 1'b0, "T12a: M1 granted when alone")

        // M0 also requests — M1 should keep bus (non-preemptive)
        @(negedge clk);
        drive_master(0, 1, 1, 1, make_addr(7, 7'h31), 32'h0);
        wait_bus_cycle();
        `CHECK(m_grnt_n[1] === 1'b0, "T12b: M1 keeps bus (non-preemptive)")
        `CHECK(m_grnt_n[0] === 1'b1, "T12b: M0 not granted while M1 owns")
        `CHECK(s_addr === make_addr(4, 7'h30), "T12b: bus still carries M1 addr")

        // Wait for M1's slave to respond, then release M1
        wait_slave_ready();
        `CHECK(m_rdy_n === 1'b0, "T12b2: M1 slave responded")
        @(negedge clk);
        release_master(1);
        wait_bus_cycle();
        mi = 0; si = 7;
        `CHECK(m_grnt_n[0] === 1'b0,              "T12c: M0 wins after M1 releases")
        `CHECK(s_addr === make_addr(7, 7'h31),     "T12c: bus carries M0 addr")
        `CHECK(s_cs_n === expect_cs_n(7),           "T12c: S7 selected")

        // ================================================================
        // TEST 13 : Priority chain after owner release
        //   M3 owns -> M0,M1,M2 wait -> M3 releases ->
        //   M0 -> M1 -> M2 -> idle
        // ================================================================
        $display("[T13] Priority chain after owner release");

        // M3 gets the bus alone — reads S6
        @(negedge clk);
        clear_all_masters();
        wait_bus_cycle();
        @(negedge clk);
        drive_master(3, 1, 1, 1, make_addr(6, 7'h01), 32'h0);
        wait_bus_cycle();
        mi = 3; si = 6;
        `CHECK(m_grnt_n[3] === 1'b0, "T13a: M3 granted when alone")

        // M0, M1, M2 all request while M3 holds
        @(negedge clk);
        drive_master(0, 1, 1, 1, make_addr(0, 7'h10), 32'h0);
        drive_master(1, 1, 1, 1, make_addr(1, 7'h11), 32'h0);
        drive_master(2, 1, 1, 1, make_addr(2, 7'h12), 32'h0);
        wait_bus_cycle();
        `CHECK(m_grnt_n[3] === 1'b0, "T13b: M3 keeps bus despite higher-pri requests")

        // M3 done, release -> M0 wins
        wait_slave_ready();
        @(negedge clk);
        release_master(3);
        wait_bus_cycle();
        mi = 0; si = 0;
        `CHECK(m_grnt_n === 4'b1110,              "T13c: M0 wins after M3 releases")
        `CHECK(s_addr === make_addr(0, 7'h10),     "T13c: bus carries M0 addr")

        // M0 done, release -> M1 wins
        wait_slave_ready();
        @(negedge clk);
        release_master(0);
        wait_bus_cycle();
        mi = 1; si = 1;
        `CHECK(m_grnt_n === 4'b1101,              "T13d: M1 wins after M0 releases")
        `CHECK(s_addr === make_addr(1, 7'h11),     "T13d: bus carries M1 addr")

        // M1 done, release -> M2 wins
        wait_slave_ready();
        @(negedge clk);
        release_master(1);
        wait_bus_cycle();
        mi = 2; si = 2;
        `CHECK(m_grnt_n === 4'b1011,              "T13e: M2 wins after M1 releases")
        `CHECK(s_addr === make_addr(2, 7'h12),     "T13e: bus carries M2 addr")

        // M2 done, release -> bus idle
        wait_slave_ready();
        @(negedge clk);
        release_master(2);
        wait_bus_cycle();
        `CHECK(m_grnt_n === 4'b1111, "T13f: bus idle after all release")

        // ================================================================
        // TEST 14 : Owner switches target slave mid-ownership
        // ================================================================
        $display("[T14] Owner switches target slave mid-ownership");

        // M2 reads S0
        @(negedge clk);
        clear_all_masters();
        wait_bus_cycle();
        @(negedge clk);
        drive_master(2, 1, 1, 1, make_addr(0, 7'h00), 32'h0);
        wait_bus_cycle();
        mi = 2; si = 0;
        `CHECK(s_cs_n === expect_cs_n(0), "T14a: S0 selected")
        wait_slave_ready();
        `CHECK(m_rd_data === 32'hA500_0000, "T14a: S0 data correct")

        // M2 switches to S7 — drive new addr at negedge
        @(negedge clk);
        drive_master(2, 1, 1, 1, make_addr(7, 7'h04), 32'h0);
        wait_bus_cycle();
        si = 7;
        `CHECK(s_cs_n === expect_cs_n(7), "T14b: S7 selected after switch")
        wait_slave_ready();
        `CHECK(m_rd_data === 32'hA500_0007, "T14b: S7 data correct")

        // M2 switches to S4 write
        @(negedge clk);
        drive_master(2, 1, 1, 0, make_addr(4, 7'h08), 32'hBEEF_CAFE);
        wait_bus_cycle();
        si = 4;
        `CHECK(s_cs_n   === expect_cs_n(4),  "T14c: S4 selected for write")
        `CHECK(s_rw     === 1'b0,            "T14c: s_rw low for write")
        `CHECK(s_wr_data === 32'hBEEF_CAFE,  "T14c: write data correct")
        wait_slave_ready();
        `CHECK(m_rdy_n === 1'b0, "T14c: S4 write acknowledged")

        // ================================================================
        // TEST 15 : Rapid ownership handoff
        // ================================================================
        $display("[T15] Rapid ownership handoff");

        @(negedge clk);
        clear_all_masters();
        wait_bus_cycle();

        // Both request simultaneously
        @(negedge clk);
        drive_master(0, 1, 1, 1, make_addr(0, 7'h01), 32'h0);
        drive_master(1, 1, 1, 1, make_addr(1, 7'h02), 32'h0);
        wait_bus_cycle();
        mi = 0; si = 0;
        `CHECK(m_grnt_n === 4'b1110, "T15a: M0 wins initial contention")

        // M0 completes then releases -> M1 takes over
        wait_slave_ready();
        @(negedge clk);
        release_master(0);
        wait_bus_cycle();
        mi = 1; si = 1;
        `CHECK(m_grnt_n === 4'b1101,              "T15b: M1 takes over after M0")
        `CHECK(s_addr === make_addr(1, 7'h02),     "T15b: bus carries M1 addr")

        // ================================================================
        // TEST 16 : Bus returns to clean idle state
        // ================================================================
        $display("[T16] Bus returns to clean idle state");
        @(negedge clk);
        clear_all_masters();
        wait_bus_cycle();
        // Extra cycle for slave model to reset
        wait_bus_cycle();
        mi = 0; si = 0;
        `CHECK(m_grnt_n  === 4'b1111,            "T16: no grant on idle")
        `CHECK(s_valid   === 1'b0,               "T16: s_valid low")
        `CHECK(s_cs_n    === {NUM_SLAVES{1'b1}}, "T16: all cs_n deasserted")
        `CHECK(m_rdy_n   === 1'b1,               "T16: m_rdy_n high")
        `CHECK(s_addr    === {ADDR_W{1'b0}},     "T16: s_addr zero")
        `CHECK(s_wr_data === {DATA_W{1'b0}},     "T16: s_wr_data zero")
        `CHECK(m_rd_data === {DATA_W{1'b0}},     "T16: m_rd_data zero")

        // ================================================================
        // TEST 17 : Valid deasserted between transactions (bus hold)
        //           M0 holds req but toggles valid between two reads
        // ================================================================
        $display("[T17] Valid deasserted between transactions");

        // M0 reads S2
        @(negedge clk);
        clear_all_masters();
        wait_bus_cycle();
        @(negedge clk);
        drive_master(0, 1, 1, 1, make_addr(2, 7'h00), 32'h0);
        wait_bus_cycle();
        mi = 0; si = 2;
        `CHECK(s_valid === 1'b1,             "T17a: s_valid high during txn")
        `CHECK(s_cs_n === expect_cs_n(2),     "T17a: S2 selected")
        wait_slave_ready();
        `CHECK(m_rd_data === 32'hA500_0002,  "T17a: S2 data correct")

        // M0 deasserts valid (gap), keeps req to hold bus
        @(negedge clk);
        m_valid[0] = 1'b0;
        wait_bus_cycle();
        `CHECK(s_valid  === 1'b0,              "T17b: s_valid low during gap")
        `CHECK(s_cs_n   === {NUM_SLAVES{1'b1}},"T17b: no slave selected during gap")
        `CHECK(m_rdy_n  === 1'b1,              "T17b: m_rdy_n high during gap")

        // M0 reasserts valid for S5
        @(negedge clk);
        m_valid[0] = 1'b1;
        m_addr[0*ADDR_W +: ADDR_W] = make_addr(5, 7'h04);
        wait_bus_cycle();
        si = 5;
        `CHECK(s_valid === 1'b1,             "T17c: s_valid high for second txn")
        `CHECK(s_cs_n === expect_cs_n(5),     "T17c: S5 selected")
        wait_slave_ready();
        `CHECK(m_rd_data === 32'hA500_0005,  "T17c: S5 data correct")
        `CHECK(m_rdy_n === 1'b0,             "T17c: m_rdy_n low after S5 responds")
        `CHECK(m_grnt_n[0] === 1'b0,         "T17c: M0 still owns bus")

        // ================================================================
        // Summary
        // ================================================================
        $display("============================================================");
        if (err_cnt == 0)
            $display(" PASS : bus_top_tb -- all tests passed");
        else
            $display(" FAIL : bus_top_tb -- %0d error(s)", err_cnt);
        $display("============================================================");
        $finish;
    end

    // ========================================================================
    // Timeout Watchdog
    // ========================================================================
    initial begin
        #1_000_000;
        $display("TIMEOUT: bus_top_tb exceeded 1 ms");
        $finish(1);
    end

endmodule

`undef CHECK
