// ============================================================================
// Project     : simpleRISC-V
// Module      : bus_master_mux
// Description : Multiplexes signals from multiple bus masters onto the shared
//               bus. The master whose grant is asserted (active-low) gets its
//               address, control, and write-data driven onto the slave-side bus.
//               Uses mux-based selection (synthesizable on both FPGA and ASIC).
// ============================================================================

`include "bus_defines.vh"

module bus_master_mux #(
        parameter NUM_MASTERS = `SRV_BUS_MASTER_NUM,        // Number of bus masters
        parameter ADDR_W      = `SRV_BUS_ADDR_W,            // Byte address width
        parameter DATA_W      = `SRV_BUS_DATA_W             // Data width
    ) (
        // Per-master signals
        input  wire [NUM_MASTERS*ADDR_W-1:0] m_addr,        // Packed master addresses
        input  wire [NUM_MASTERS-1:0]        m_valid,       // Transaction valid (active-high)
        input  wire [NUM_MASTERS-1:0]        m_rw,          // Read(1) / Write(0)
        input  wire [NUM_MASTERS*DATA_W-1:0] m_wr_data,     // Packed master write data
        input  wire [NUM_MASTERS-1:0]        m_grnt_n,      // Grant (active-low)
        // Shared slave-side bus
        output reg  [ADDR_W-1:0]            s_addr,         // Shared address bus
        output reg                          s_valid,        // Shared transaction valid
        output reg                          s_rw,           // Shared read / write
        output reg  [DATA_W-1:0]            s_wr_data       // Shared write-data bus
    );

    // ========================================================================
    // Mux-Based Bus Drive: only the granted master drives the shared bus
    // ========================================================================
    integer i;

    always @(*) begin
        s_addr    = {ADDR_W{1'b0}};
        s_valid   = 1'b0;
        s_rw      = 1'b1;
        s_wr_data = {DATA_W{1'b0}};

        for (i = 0; i < NUM_MASTERS; i = i + 1) begin
            if (m_grnt_n[i] == 1'b0) begin
                s_addr    = m_addr[i*ADDR_W +: ADDR_W];
                s_valid   = m_valid[i];
                s_rw      = m_rw[i];
                s_wr_data = m_wr_data[i*DATA_W +: DATA_W];
            end
        end
    end

endmodule
