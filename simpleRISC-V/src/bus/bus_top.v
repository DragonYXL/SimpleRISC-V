// ============================================================================
// Project     : simpleRISC-V
// Module      : bus_top
// Description : Top-level bus interconnect. Instantiates the arbiter, master
//               mux, address decoder, and slave mux to form a complete shared
//               bus fabric.
//               All sub-modules are parameterized; topology can be changed by
//               overriding NUM_MASTERS / NUM_SLAVES at instantiation.
// ============================================================================

`default_nettype none

module bus_top #(
    parameter NUM_MASTERS = 4,                              // Number of bus masters
    parameter NUM_SLAVES  = 8,                              // Number of bus slaves
    parameter ADDR_W      = 30,                             // Word address width
    parameter DATA_W      = 32,                             // Data width
    parameter IDX_MSB     = 29,                             // Slave index MSB in addr
    parameter IDX_LSB     = 27                              // Slave index LSB in addr
) (
    // Clock & Reset
    input  wire                              clk,           // System clock
    input  wire                              rst_n,         // Async reset (active-low)

    // ---- Master-side interface (active-low control) ----
    input  wire [NUM_MASTERS-1:0]            m_req_n,       // Bus request
    output wire [NUM_MASTERS-1:0]            m_grnt_n,      // Bus grant
    input  wire [NUM_MASTERS*ADDR_W-1:0]     m_addr,        // Packed addresses
    input  wire [NUM_MASTERS-1:0]            m_as_n,        // Address strobe
    input  wire [NUM_MASTERS-1:0]            m_rw,          // Read(1)/Write(0)
    input  wire [NUM_MASTERS*DATA_W-1:0]     m_wr_data,     // Packed write data
    output wire [DATA_W-1:0]                 m_rd_data,     // Read data (shared)
    output wire                              m_rdy_n,       // Ready (shared)

    // ---- Slave-side interface (directly exposed to slaves) ----
    output wire [ADDR_W-1:0]                 s_addr,        // Shared address
    output wire                              s_as_n,        // Shared address strobe
    output wire                              s_rw,          // Shared read/write
    output wire [DATA_W-1:0]                 s_wr_data,     // Shared write data
    output wire [NUM_SLAVES-1:0]             s_cs_n,        // Chip selects
    input  wire [NUM_SLAVES*DATA_W-1:0]      s_rd_data,     // Packed slave read data
    input  wire [NUM_SLAVES-1:0]             s_rdy_n        // Slave ready signals
);

    // ========================================================================
    // Bus Arbiter
    // ========================================================================
    bus_arbiter #(
        .NUM_MASTERS (NUM_MASTERS)
    ) u_arbiter (
        .clk    (clk),
        .rst_n  (rst_n),
        .req_n  (m_req_n),
        .grnt_n (m_grnt_n)
    );

    // ========================================================================
    // Master Multiplexer
    // ========================================================================
    bus_master_mux #(
        .NUM_MASTERS (NUM_MASTERS),
        .ADDR_W      (ADDR_W),
        .DATA_W      (DATA_W)
    ) u_master_mux (
        .m_addr    (m_addr),
        .m_as_n    (m_as_n),
        .m_rw      (m_rw),
        .m_wr_data (m_wr_data),
        .m_grnt_n  (m_grnt_n),
        .s_addr    (s_addr),
        .s_as_n    (s_as_n),
        .s_rw      (s_rw),
        .s_wr_data (s_wr_data)
    );

    // ========================================================================
    // Address Decoder
    // ========================================================================
    bus_addr_dec #(
        .NUM_SLAVES (NUM_SLAVES),
        .ADDR_W     (ADDR_W),
        .IDX_MSB    (IDX_MSB),
        .IDX_LSB    (IDX_LSB)
    ) u_addr_dec (
        .s_addr (s_addr),
        .s_cs_n (s_cs_n)
    );

    // ========================================================================
    // Slave Multiplexer
    // ========================================================================
    bus_slave_mux #(
        .NUM_SLAVES (NUM_SLAVES),
        .DATA_W     (DATA_W)
    ) u_slave_mux (
        .s_cs_n    (s_cs_n),
        .s_rd_data (s_rd_data),
        .s_rdy_n   (s_rdy_n),
        .m_rd_data (m_rd_data),
        .m_rdy_n   (m_rdy_n)
    );

endmodule

`default_nettype wire
