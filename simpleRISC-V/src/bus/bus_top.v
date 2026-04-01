// ============================================================================
// Project     : simpleRISC-V
// Module      : bus_top
// Description : Top-level bus interconnect. Instantiates the arbiter, master
//               mux, address decoder, and slave mux to form a complete shared
//               bus fabric.
//               Master is responsible for holding req_n and valid stable until
//               slave responds with rdy_n. The arbiter's non-preemptive
//               ownership guarantees grant stability during a transaction.
// ============================================================================

`include "bus_defines.vh"

module bus_top #(
    parameter NUM_MASTERS = `SRV_BUS_MASTER_NUM,            // Number of bus masters
    parameter NUM_SLAVES  = `SRV_BUS_SLAVE_NUM,             // Number of bus slaves
    parameter ADDR_W      = `SRV_BUS_ADDR_W,                // Byte address width
    parameter DATA_W      = `SRV_BUS_DATA_W,                // Data width
    parameter IDX_MSB     = `SRV_BUS_SLAVE_IDX_MSB,         // Slave index MSB in addr
    parameter IDX_LSB     = `SRV_BUS_SLAVE_IDX_LSB          // Slave index LSB in addr
) (
    // Clock & Reset
    input  wire                              clk,           // System clock
    input  wire                              rst_n,         // Async reset (active-low)

    // ---- Master-side interface ----
    input  wire [NUM_MASTERS-1:0]            m_req_n,       // Bus request (active-low)
    output wire [NUM_MASTERS-1:0]            m_grnt_n,      // Bus grant   (active-low)
    input  wire [NUM_MASTERS*ADDR_W-1:0]     m_addr,        // Packed addresses
    input  wire [NUM_MASTERS-1:0]            m_valid,       // Transaction valid (active-high)
    input  wire [NUM_MASTERS-1:0]            m_rw,          // Read(1)/Write(0)
    input  wire [NUM_MASTERS*DATA_W-1:0]     m_wr_data,     // Packed write data
    output wire [DATA_W-1:0]                 m_rd_data,     // Read data (shared)
    output wire                              m_rdy_n,       // Ready (shared, active-low)

    // ---- Slave-side interface ----
    output wire [ADDR_W-1:0]                 s_addr,        // Shared address
    output wire                              s_valid,       // Shared transaction valid
    output wire                              s_rw,          // Shared read/write
    output wire [DATA_W-1:0]                 s_wr_data,     // Shared write data
    output wire [NUM_SLAVES-1:0]             s_cs_n,        // Chip selects (active-low)
    input  wire [NUM_SLAVES*DATA_W-1:0]      s_rd_data,     // Packed slave read data
    input  wire [NUM_SLAVES-1:0]             s_rdy_n        // Slave ready signals (active-low)
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
        .m_valid   (m_valid),
        .m_rw      (m_rw),
        .m_wr_data (m_wr_data),
        .m_grnt_n  (m_grnt_n),
        .s_addr    (s_addr),
        .s_valid   (s_valid),
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
        .s_valid (s_valid),
        .s_addr  (s_addr),
        .s_cs_n  (s_cs_n)
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
