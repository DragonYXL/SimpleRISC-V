`timescale 1ns/1ps

// ============================================================================
// Project     : simpleRISC-V
// Module      : bus_top_tb
// Description : Lightweight bus-level directed testbench.
//               Covers single-master multi-slave access, write-path routing,
//               fixed-priority arbitration, non-preemptive ownership, and
//               idle-bus defaults.
// ============================================================================

`default_nettype none

`define CHECK(cond, msg)                                                     \
    if (!(cond)) begin                                                       \
        $display("FAIL: %0s (time=%0t)", msg, $time);                        \
        $finish(1);                                                          \
    end

module bus_top_tb;

    localparam integer NUM_MASTERS = 4;
    localparam integer NUM_SLAVES  = 8;
    localparam integer ADDR_W      = 30;
    localparam integer DATA_W      = 32;
    localparam integer IDX_MSB     = 29;
    localparam integer IDX_LSB     = 27;

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
    reg  [NUM_SLAVES*DATA_W-1:0]     slave_rsp_data;
    reg  [NUM_SLAVES-1:0]            slave_rsp_rdy_n;

    integer i;

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

    always #5 clk = ~clk;

    // Only the addressed slave responds during an active transfer.
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
                if (j == slave_idx) begin
                    select_slave_n[j] = 1'b0;
                end
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
            slave_rsp_rdy_n = {NUM_SLAVES{1'b0}};
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

    initial begin
        clk   = 1'b0;
        rst_n = 1'b0;

        clear_master_inputs();
        init_slave_responses();

        repeat (2) @(posedge clk);
        rst_n = 1'b1;

        @(negedge clk);
        #1;
        `CHECK(m_grnt_n === 4'b1111, "idle bus should not grant any master");
        `CHECK(s_as_n === 1'b1, "idle bus should keep address strobe deasserted");
        `CHECK(m_rdy_n === 1'b1, "idle bus should report not-ready by default");

        // --------------------------------------------------------------------
        // Case 1: one master accesses multiple slaves
        // --------------------------------------------------------------------
        set_master(0, 1'b1, 1'b1, 1'b1, make_addr(2, 7'h04), 32'h0000_0000);
        #1;
        `CHECK(m_grnt_n === 4'b1110, "master0 should win when it is the only requester");
        `CHECK(s_cs_n === select_slave_n(2), "slave2 should be selected for master0 read");
        `CHECK(s_addr === make_addr(2, 7'h04), "slave2 read address should propagate");
        `CHECK(s_as_n === 1'b0, "read address strobe should assert");
        `CHECK(s_rw === 1'b1, "read transaction should drive s_rw high");
        `CHECK(m_rd_data === 32'hA500_0002, "slave2 read data should return to master side");
        `CHECK(m_rdy_n === 1'b0, "slave2 ready should propagate to master side");

        @(negedge clk);
        set_master(0, 1'b1, 1'b1, 1'b1, make_addr(5, 7'h11), 32'h0000_0000);
        #1;
        `CHECK(m_grnt_n === 4'b1110, "master0 should keep grant while it requests");
        `CHECK(s_cs_n === select_slave_n(5), "slave5 should be selected for second read");
        `CHECK(s_addr === make_addr(5, 7'h11), "slave5 read address should propagate");
        `CHECK(m_rd_data === 32'hA500_0005, "slave5 read data should return to master side");

        // --------------------------------------------------------------------
        // Case 2: write-path routing to a slave
        // --------------------------------------------------------------------
        @(negedge clk);
        set_master(0, 1'b1, 1'b1, 1'b0, make_addr(4, 7'h02), 32'hCAFE_BABE);
        #1;
        `CHECK(s_cs_n === select_slave_n(4), "slave4 should be selected for write");
        `CHECK(s_rw === 1'b0, "write transaction should drive s_rw low");
        `CHECK(s_wr_data === 32'hCAFE_BABE, "write data should propagate to slave side");

        slave_rsp_rdy_n[4] = 1'b1;
        #1;
        `CHECK(m_rdy_n === 1'b1, "selected slave ready deassertion should propagate");
        slave_rsp_rdy_n[4] = 1'b0;
        #1;
        `CHECK(m_rdy_n === 1'b0, "selected slave ready assertion should propagate");

        // Latch master0 as owner, then release to create an idle arbitration point.
        @(posedge clk);
        @(negedge clk);
        clear_master_inputs();
        #1;
        `CHECK(m_grnt_n === 4'b1111, "grant should clear after releasing all requests");

        // --------------------------------------------------------------------
        // Case 3: multiple masters request simultaneously
        // --------------------------------------------------------------------
        set_master(2, 1'b1, 1'b1, 1'b1, make_addr(2, 7'h01), 32'h0000_0000);
        set_master(1, 1'b1, 1'b1, 1'b1, make_addr(1, 7'h03), 32'h0000_0000);
        set_master(3, 1'b1, 1'b1, 1'b1, make_addr(3, 7'h05), 32'h0000_0000);
        #1;
        `CHECK(m_grnt_n === 4'b1101, "master1 should win simultaneous arbitration");
        `CHECK(s_addr === make_addr(1, 7'h03), "winning master1 address should drive the bus");
        `CHECK(s_cs_n === select_slave_n(1), "winning master1 target slave should be selected");

        @(posedge clk);
        @(negedge clk);
        set_master(0, 1'b1, 1'b1, 1'b1, make_addr(0, 7'h09), 32'h0000_0000);
        #1;
        `CHECK(m_grnt_n === 4'b1101, "current owner should not be preempted by a higher priority requester");
        `CHECK(s_addr === make_addr(1, 7'h03), "bus should still carry master1 signals while owned");

        // --------------------------------------------------------------------
        // Case 4: owner releases, arbiter reselects highest remaining priority
        // --------------------------------------------------------------------
        set_master(1, 1'b0, 1'b0, 1'b1, {ADDR_W{1'b0}}, {DATA_W{1'b0}});
        #1;
        `CHECK(m_grnt_n === 4'b1110, "master0 should win after master1 releases the bus");
        `CHECK(s_addr === make_addr(0, 7'h09), "master0 address should drive the bus after re-arbitration");
        `CHECK(s_cs_n === select_slave_n(0), "slave0 should be selected after re-arbitration");

        @(posedge clk);
        @(negedge clk);
        clear_master_inputs();
        #1;
        `CHECK(m_grnt_n === 4'b1111, "bus should return to idle after all requests release");
        `CHECK(s_as_n === 1'b1, "idle bus should deassert address strobe after traffic");

        $display("PASS: bus_top_tb");
        $finish;
    end

endmodule

`undef CHECK
`default_nettype wire
