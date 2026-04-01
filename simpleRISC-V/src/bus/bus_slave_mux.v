// ============================================================================
// Project     : simpleRISC-V
// Module      : bus_slave_mux
// Description : Multiplexes read-data and ready signals from multiple bus
//               slaves back to the master side. The slave whose chip-select
//               is asserted (active-low) drives the return path.
//               Uses mux-based selection (synthesizable on both FPGA and ASIC).
// ============================================================================

`include "bus_defines.vh"

module bus_slave_mux #(
    parameter NUM_SLAVES = `SRV_BUS_SLAVE_NUM,         // Number of bus slaves
    parameter DATA_W     = `SRV_BUS_DATA_W             // Data width
) (
    input  wire [NUM_SLAVES-1:0]          s_cs_n,       // Chip selects (active-low)
    input  wire [NUM_SLAVES*DATA_W-1:0]   s_rd_data,    // Packed slave read data
    input  wire [NUM_SLAVES-1:0]          s_rdy_n,      // Slave ready (active-low)
    output reg  [DATA_W-1:0]             m_rd_data,     // Shared read-data bus
    output reg                           m_rdy_n        // Shared ready signal (active-low)
);

    // ========================================================================
    // Mux-Based Response Bus: only the selected slave drives the return path
    // ========================================================================
    integer i;

    always @(*) begin
        m_rd_data = {DATA_W{1'b0}};
        m_rdy_n   = 1'b1;

        for (i = 0; i < NUM_SLAVES; i = i + 1) begin
            if (s_cs_n[i] == 1'b0) begin
                m_rd_data = s_rd_data[i*DATA_W +: DATA_W];
                m_rdy_n   = s_rdy_n[i];
            end
        end
    end

endmodule
