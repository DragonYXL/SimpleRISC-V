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
//
//               Slave model: registered with configurable 1-3 cycle latency.
//               Slaves do NOT respond on the same clock they first see cs_n.
//
//               Timing convention (registered grant):
//                 negedge : set master signals
//                 posedge : arbiter registers grant
//                 negedge : check — grant visible, mux outputs valid
//                 posedge(s) : slave processes, eventually asserts rdy_n=0
// ============================================================================

`include "../../src/bus/bus_defines.vh"

`define CHECK(cond, msg)                                                     \
    if (!(cond)) begin                                                       \
        $display("FAIL: %0s (time=%0t, mi=%0d, si=%0d)", msg, $time, mi, si);\
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
    reg  [NUM_MASTERS-1:0]           m_valid;
    reg  [NUM_MASTERS-1:0]           m_rw;
    reg  [NUM_MASTERS*DATA_W-1:0]    m_wr_data;
    wire [DATA_W-1:0]                m_rd_data;
    wire                             m_rdy_n;
    wire [ADDR_W-1:0]                s_addr;
    wire                             s_valid;
    wire                             s_rw;
    wire [DATA_W-1:0]                s_wr_data;
    wire [NUM_SLAVES-1:0]            s_cs_n;
    reg  [NUM_SLAVES*DATA_W-1:0]     s_rd_data;
    reg  [NUM_SLAVES-1:0]            s_rdy_n;

    // Slave response storage (what data each slave returns)
    reg  [NUM_SLAVES*DATA_W-1:0]     slave_rsp_data;

    // Slave delay model: configurable per-slave latency (1-3 cycles)
    reg  [1:0]                       slave_delay_cnt [0:NUM_SLAVES-1];
    reg  [1:0]                       slave_delay_cfg [0:NUM_SLAVES-1];

    integer err_cnt;
    integer i;
    integer mi, si;
    integer k;       // for slave model always block

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
    // Clock Generation: 100 MHz
    // ========================================================================
    always #5 clk = ~clk;

    // ========================================================================
    // Slave Response Model (registered — 1 to 3 cycle latency)
    //
    // Each slave has a configurable delay (slave_delay_cfg[k]).
    // When cs_n[k]=0 and valid=1, the slave counts up from 0.
    // After slave_delay_cfg[k] cycles of counting, it asserts rdy_n=0
    // and drives rd_data. When cs_n goes high, counter resets.
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
                        // Still processing — not ready
                        slave_delay_cnt[k]             <= slave_delay_cnt[k] + 2'd1;
                        s_rdy_n[k]                     <= 1'b1;
                        s_rd_data[k*DATA_W +: DATA_W]  <= {DATA_W{1'b0}};
                    end else begin
                        // Delay elapsed — respond
                        s_rdy_n[k]                     <= 1'b0;
                        s_rd_data[k*DATA_W +: DATA_W]  <= slave_rsp_data[k*DATA_W +: DATA_W];
                    end
                end else begin
                    // Not selected — reset counter
                    slave_delay_cnt[k]             <= 2'd0;
                    s_rdy_n[k]                     <= 1'b1;
                    s_rd_data[k*DATA_W +: DATA_W]  <= {DATA_W{1'b0}};
                end
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
            m_valid   = {NUM_MASTERS{1'b0}};
            m_rw      = {NUM_MASTERS{1'b1}};
            m_wr_data = {NUM_MASTERS*DATA_W{1'b0}};
        end
    endtask

    task init_slave_responses;
        begin
            for (i = 0; i < NUM_SLAVES; i = i + 1)
                slave_rsp_data[i*DATA_W +: DATA_W] = 32'hA500_0000 + i;
            // Varied delays: 1–3 cycles of "not ready" before responding
            slave_delay_cfg[0] = 2'd1;    // 1 cycle delay
            slave_delay_cfg[1] = 2'd2;    // 2 cycle delay
            slave_delay_cfg[2] = 2'd1;
            slave_delay_cfg[3] = 2'd3;    // 3 cycle delay
            slave_delay_cfg[4] = 2'd2;
            slave_delay_cfg[5] = 2'd1;
            slave_delay_cfg[6] = 2'd3;
            slave_delay_cfg[7] = 2'd2;
        end
    endtask

    task set_master;
        input integer          master_idx;
        input                  req_active;      // 1 = request bus
        input                  valid_active;    // 1 = transaction valid
        input                  rw_value;        // 1 = read, 0 = write
        input [ADDR_W-1:0]     addr_value;
        input [DATA_W-1:0]     wr_data_value;
        begin
            m_req_n[master_idx] = ~req_active;
            m_valid[master_idx] = valid_active;
            m_rw[master_idx]    = rw_value;
            m_addr[master_idx*ADDR_W +: ADDR_W] = addr_value;
            m_wr_data[master_idx*DATA_W +: DATA_W] = wr_data_value;
        end
    endtask

    task release_master;
        input integer master_idx;
        begin
            m_req_n[master_idx] = 1'b1;
            m_valid[master_idx] = 1'b0;
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

    // Wait for slave ready: poll m_rdy_n at posedge until it goes low.
    // Timeout after 100 cycles to avoid hang.
    task wait_slave_rdy;
        integer wsr_timeout;
        begin
            wsr_timeout = 0;
            #1;
            while (m_rdy_n !== 1'b0 && wsr_timeout < 100) begin
                @(posedge clk);
                #1;
                wsr_timeout = wsr_timeout + 1;
            end
            if (wsr_timeout >= 100)
                $display("ERROR: wait_slave_rdy timeout at time=%0t", $time);
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
        // TEST 0 : Idle-bus defaults
        // ================================================================
        $display("[TEST 0] Idle-bus defaults");
        #1;
        `CHECK(m_grnt_n  === 4'b1111,            "T0: no grant on idle bus");
        `CHECK(s_valid   === 1'b0,               "T0: s_valid low on idle");
        `CHECK(s_rw      === 1'b1,               "T0: s_rw default read on idle");
        `CHECK(s_addr    === {ADDR_W{1'b0}},     "T0: s_addr zero on idle");
        `CHECK(s_wr_data === {DATA_W{1'b0}},     "T0: s_wr_data zero on idle");
        `CHECK(s_cs_n    === {NUM_SLAVES{1'b1}}, "T0: all cs_n deasserted on idle");
        `CHECK(m_rd_data === {DATA_W{1'b0}},     "T0: m_rd_data zero on idle");
        `CHECK(m_rdy_n   === 1'b1,               "T0: m_rdy_n high on idle");

        // ================================================================
        // TEST 1 : Each master reads from every slave
        //          Verifies: grant, bus signals, slave latency, read data
        // ================================================================
        $display("[TEST 1] Each master reads from every slave");
        for (mi = 0; mi < NUM_MASTERS; mi = mi + 1) begin
            for (si = 0; si < NUM_SLAVES; si = si + 1) begin
                clear_master_inputs();
                wait_arb_cycle();

                set_master(mi, 1'b1, 1'b1, 1'b1, make_addr(si, 7'h10 + si), 32'h0);
                wait_arb_cycle();
                #1;

                // Bus signal checks (combinational, valid immediately after grant)
                `CHECK(m_grnt_n[mi] === 1'b0,
                    "T1: master should be granted for read");
                `CHECK(s_cs_n === select_slave_n(si),
                    "T1: cs_n should assert for read");
                `CHECK(s_addr === make_addr(si, 7'h10 + si),
                    "T1: addr mismatch on read");
                `CHECK(s_rw === 1'b1,
                    "T1: s_rw should be 1 for read");
                `CHECK(s_valid === 1'b1,
                    "T1: s_valid should be 1 for read");
                // Slave has NOT responded yet — verify not-ready
                `CHECK(m_rdy_n === 1'b1,
                    "T1: m_rdy_n should be 1 before slave responds");

                // Wait for slave to respond (1-3 cycles depending on slave)
                wait_slave_rdy();
                `CHECK(m_rd_data === (32'hA500_0000 + si),
                    "T1: rd_data mismatch");
                `CHECK(m_rdy_n === 1'b0,
                    "T1: m_rdy_n should be 0 after slave responds");
            end
        end

        // ================================================================
        // TEST 2 : Each master writes to every slave
        //          Verifies: grant, bus signals, write data path, slave ack
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

                // Bus signal checks
                `CHECK(m_grnt_n[mi] === 1'b0,
                    "T2: master should be granted for write");
                `CHECK(s_cs_n === select_slave_n(si),
                    "T2: cs_n should assert for write");
                `CHECK(s_addr === make_addr(si, 7'h20 + si),
                    "T2: addr mismatch on write");
                `CHECK(s_rw === 1'b0,
                    "T2: s_rw should be 0 for write");
                `CHECK(s_wr_data === (32'hDEAD_0000 + (mi << 8) + si),
                    "T2: wr_data mismatch");
                `CHECK(m_rdy_n === 1'b1,
                    "T2: m_rdy_n should be 1 before slave responds");

                // Wait for slave write-ack
                wait_slave_rdy();
                `CHECK(m_rdy_n === 1'b0,
                    "T2: m_rdy_n should be 0 after slave responds");
            end
        end

        // ================================================================
        // TEST 3 : Slave latency verification
        //          Verify that m_rdy_n stays high for exactly
        //          slave_delay_cfg[target] cycles before going low.
        //          Uses S3 which has cfg=3 (longest delay).
        // ================================================================
        $display("[TEST 3] Slave latency verification (S3, delay=3)");
        begin : test3_block
            integer rdy_wait_cnt;
            clear_master_inputs();
            wait_arb_cycle();

            // M0 reads S3
            set_master(0, 1'b1, 1'b1, 1'b1, make_addr(3, 7'h00), 32'h0);
            wait_arb_cycle();
            #1;
            `CHECK(m_grnt_n[0] === 1'b0, "T3: M0 should be granted");
            `CHECK(s_cs_n[3]   === 1'b0, "T3: S3 should be selected");

            // Count how many posedges until m_rdy_n goes low
            rdy_wait_cnt = 0;
            while (m_rdy_n !== 1'b0 && rdy_wait_cnt < 20) begin
                @(posedge clk);
                #1;
                rdy_wait_cnt = rdy_wait_cnt + 1;
            end

            // With cfg=3: slave needs 3 not-ready cycles + 1 response cycle = 4 posedges
            // from when it first sees cs_n (1 posedge after grant).
            // From our check point (right after grant posedge), that's:
            //   posedge+1: slave sees cs_n, cnt 0<3, not ready   (rdy_wait_cnt=1)
            //   posedge+2: cnt 1<3, not ready                     (rdy_wait_cnt=2)
            //   posedge+3: cnt 2<3, not ready                     (rdy_wait_cnt=3)
            //   posedge+4: cnt 3>=3, respond!                     (rdy_wait_cnt=4)
            `CHECK(rdy_wait_cnt === 4,
                "T3: S3 should take exactly 4 posedges to respond (cfg=3)");
            `CHECK(m_rdy_n === 1'b0, "T3: m_rdy_n should be 0 after delay");
            `CHECK(m_rd_data === 32'hA500_0003, "T3: S3 data mismatch");

            // Also test S0 which has cfg=1 (shortest delay)
            $display("[TEST 3b] Slave latency verification (S0, delay=1)");
            clear_master_inputs();
            wait_arb_cycle();

            set_master(0, 1'b1, 1'b1, 1'b1, make_addr(0, 7'h00), 32'h0);
            wait_arb_cycle();
            #1;

            rdy_wait_cnt = 0;
            while (m_rdy_n !== 1'b0 && rdy_wait_cnt < 20) begin
                @(posedge clk);
                #1;
                rdy_wait_cnt = rdy_wait_cnt + 1;
            end

            // cfg=1: 1 not-ready + 1 response = 2 posedges
            `CHECK(rdy_wait_cnt === 2,
                "T3b: S0 should take exactly 2 posedges to respond (cfg=1)");
            `CHECK(m_rdy_n === 1'b0, "T3b: m_rdy_n should be 0");
            `CHECK(m_rd_data === 32'hA500_0000, "T3b: S0 data mismatch");
        end

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
        //           M1 owns bus -> M0 arrives -> M1 keeps ->
        //           M1 completes txn & releases -> M0 takes over
        // ================================================================
        $display("[TEST 12] Non-preemptive ownership");
        clear_master_inputs();
        wait_arb_cycle();

        // M1 alone requests — reads S4
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

        // Wait for M1's slave to respond, then release M1
        wait_slave_rdy();
        `CHECK(m_rdy_n === 1'b0, "T12b2: M1 slave should have responded");
        release_master(1);
        wait_arb_cycle();
        #1;
        `CHECK(m_grnt_n[0] === 1'b0, "T12c: M0 should win after M1 releases");
        `CHECK(s_addr === make_addr(7, 7'h31), "T12c: bus should carry M0 address");
        `CHECK(s_cs_n === select_slave_n(7),   "T12c: S7 should be selected");

        // ================================================================
        // TEST 13 : Priority chain after owner release
        //           M3 owns -> M0,M1,M2 wait -> M3 releases -> M0 -> M1 -> M2
        // ================================================================
        $display("[TEST 13] Priority chain after owner release");
        clear_master_inputs();
        wait_arb_cycle();

        // M3 gets the bus alone — reads S6
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

        // M3 completes transaction and releases
        wait_slave_rdy();
        release_master(3);
        wait_arb_cycle();
        #1;
        `CHECK(m_grnt_n === 4'b1110, "T13c: M0 should win after M3 releases");
        `CHECK(s_addr === make_addr(0, 7'h10), "T13c: bus should carry M0 address");

        // M0 completes and releases -> M1 wins
        wait_slave_rdy();
        release_master(0);
        wait_arb_cycle();
        #1;
        `CHECK(m_grnt_n === 4'b1101, "T13d: M1 should win after M0 releases");
        `CHECK(s_addr === make_addr(1, 7'h11), "T13d: bus should carry M1 address");

        // M1 completes and releases -> M2 wins
        wait_slave_rdy();
        release_master(1);
        wait_arb_cycle();
        #1;
        `CHECK(m_grnt_n === 4'b1011, "T13e: M2 should win after M1 releases");
        `CHECK(s_addr === make_addr(2, 7'h12), "T13e: bus should carry M2 address");

        // M2 completes and releases -> bus idle
        wait_slave_rdy();
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
        wait_slave_rdy();
        `CHECK(m_rd_data === 32'hA500_0000,  "T14a: S0 data returned");

        // M2 switches to S7 (new slave starts counting from 0)
        set_master(2, 1'b1, 1'b1, 1'b1, make_addr(7, 7'h04), 32'h0);
        #1;
        `CHECK(s_cs_n === select_slave_n(7), "T14b: S7 selected after switch");
        wait_slave_rdy();
        `CHECK(m_rd_data === 32'hA500_0007,  "T14b: S7 data returned");

        // M2 switches to S4 write
        set_master(2, 1'b1, 1'b1, 1'b0, make_addr(4, 7'h08), 32'hBEEF_CAFE);
        #1;
        `CHECK(s_cs_n === select_slave_n(4),   "T14c: S4 selected for write");
        `CHECK(s_rw === 1'b0,                  "T14c: s_rw low for write");
        `CHECK(s_wr_data === 32'hBEEF_CAFE,    "T14c: write data correct");
        wait_slave_rdy();
        `CHECK(m_rdy_n === 1'b0,               "T14c: S4 write acknowledged");

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

        // M0 completes transaction then releases — M1 should take over
        wait_slave_rdy();
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
        // Extra cycle to let slave model reset
        wait_arb_cycle();
        #1;
        `CHECK(m_grnt_n  === 4'b1111,            "T16: no grant on idle");
        `CHECK(s_valid   === 1'b0,               "T16: s_valid low on idle");
        `CHECK(s_cs_n    === {NUM_SLAVES{1'b1}}, "T16: all cs_n deasserted");
        `CHECK(m_rdy_n   === 1'b1,               "T16: m_rdy_n high on idle");
        `CHECK(s_addr    === {ADDR_W{1'b0}},     "T16: s_addr zero on idle");
        `CHECK(s_wr_data === {DATA_W{1'b0}},     "T16: s_wr_data zero on idle");
        `CHECK(m_rd_data === {DATA_W{1'b0}},     "T16: m_rd_data zero on idle");

        // ================================================================
        // TEST 17 : Valid deasserted between transactions (bus hold)
        //           M0 holds req but toggles valid between two reads
        // ================================================================
        $display("[TEST 17] Valid deasserted between transactions");
        clear_master_inputs();
        wait_arb_cycle();

        // M0 reads S2
        set_master(0, 1'b1, 1'b1, 1'b1, make_addr(2, 7'h00), 32'h0);
        wait_arb_cycle();
        #1;
        `CHECK(s_valid === 1'b1,               "T17a: s_valid high during txn");
        `CHECK(s_cs_n === select_slave_n(2),   "T17a: S2 selected");
        wait_slave_rdy();
        `CHECK(m_rd_data === 32'hA500_0002,    "T17a: S2 data returned");

        // M0 deasserts valid (gap), keeps req to hold bus
        m_valid[0] = 1'b0;
        @(posedge clk);   // let slave model see cs_n going high
        @(negedge clk);
        #1;
        `CHECK(s_valid === 1'b0,               "T17b: s_valid low during gap");
        `CHECK(s_cs_n === {NUM_SLAVES{1'b1}},  "T17b: no slave selected during gap");
        `CHECK(m_rdy_n === 1'b1,               "T17b: m_rdy_n high during gap");

        // M0 reasserts valid for S5
        m_valid[0] = 1'b1;
        m_addr[0*ADDR_W +: ADDR_W] = make_addr(5, 7'h04);
        #1;
        `CHECK(s_valid === 1'b1,               "T17c: s_valid high for second txn");
        `CHECK(s_cs_n === select_slave_n(5),   "T17c: S5 selected");
        wait_slave_rdy();
        `CHECK(m_rd_data === 32'hA500_0005,    "T17c: S5 data returned");
        `CHECK(m_rdy_n === 1'b0,               "T17c: m_rdy_n low after S5 responds");

        // Verify M0 still owns bus (no re-arbitration happened)
        `CHECK(m_grnt_n[0] === 1'b0,           "T17c: M0 still owns bus");

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
        #1_000_000;
        $display("TIMEOUT: bus_top_tb exceeded 1 ms");
        $finish(1);
    end

endmodule

`undef CHECK
