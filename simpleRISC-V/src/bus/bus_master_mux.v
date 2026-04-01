// ============================================================================
// Project     : simpleRISC-V
// Module      : bus_master_mux
// Description : Multiplexes signals from multiple bus masters onto the shared
//               bus. The master whose grant is asserted (active-low) gets its
//               address, control, and write-data driven onto the slave-side bus.
//               Uses packed arrays for clean parameterization.
// ============================================================================

module bus_master_mux #(
        parameter NUM_MASTERS = 4,                          // Number of bus masters
        parameter ADDR_W      = 30,                         // Word address width
        parameter DATA_W      = 32                          // Data width
    ) (
        // Per-master signals (active-low as_, grnt_n)
        input  wire [NUM_MASTERS*ADDR_W-1:0] m_addr,        // Packed master addresses
        input  wire [NUM_MASTERS-1:0]        m_as_n,        // Address strobe (active-low)
        input  wire [NUM_MASTERS-1:0]        m_rw,          // Read(1) / Write(0)
        input  wire [NUM_MASTERS*DATA_W-1:0] m_wr_data,     // Packed master write data
        input  wire [NUM_MASTERS-1:0]        m_grnt_n,      // Grant (active-low)
        // Shared slave-side bus
        output reg  [ADDR_W-1:0]            s_addr,         // Slave address
        output reg                          s_as_n,         // Address strobe (active-low)
        output reg                          s_rw,           // Read / Write
        output reg  [DATA_W-1:0]            s_wr_data       // Slave write data
    );

    integer i;

    // ========================================================================
    // Combinational Mux: select the granted master's signals
    // ========================================================================
    always @(*) begin
        // Defaults: bus idle
        s_addr    = {ADDR_W{1'b0}};
        s_as_n    = 1'b1;                              // No address strobe
        s_rw      = 1'b1;                              // Default read
        s_wr_data = {DATA_W{1'b0}};

        for (i = 0; i < NUM_MASTERS; i = i + 1) begin
            if (~m_grnt_n[i]) begin
                s_addr    = m_addr[i*ADDR_W +: ADDR_W];
                s_as_n    = m_as_n[i];
                s_rw      = m_rw[i];
                s_wr_data = m_wr_data[i*DATA_W +: DATA_W];
            end
        end
    end

endmodule
