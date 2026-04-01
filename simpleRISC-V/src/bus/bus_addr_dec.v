// ============================================================================
// Project     : simpleRISC-V
// Module      : bus_addr_dec
// Description : Address decoder for the shared bus. Extracts a slave index
//               from the high bits of the word address and asserts the
//               corresponding chip-select (active-low).
//               Parameterized slave count and index bit position.
// ============================================================================

module bus_addr_dec #(
    parameter NUM_SLAVES  = 8,                          // Number of bus slaves
    parameter ADDR_W      = 30,                         // Word address width
    parameter IDX_MSB     = 29,                         // Slave index MSB in addr
    parameter IDX_LSB     = 27                          // Slave index LSB in addr
) (
    input  wire [ADDR_W-1:0]       s_addr,              // Word address from bus
    output reg  [NUM_SLAVES-1:0]   s_cs_n               // Chip selects (active-low)
);

    // Derived parameter: width of slave index field
    localparam IDX_W = IDX_MSB - IDX_LSB + 1;

    wire [IDX_W-1:0] slave_idx = s_addr[IDX_MSB:IDX_LSB];

    integer i;

    // ========================================================================
    // Combinational Decode
    // ========================================================================
    always @(*) begin
        s_cs_n = {NUM_SLAVES{1'b1}};                   // Default: all deselected
        for (i = 0; i < NUM_SLAVES; i = i + 1) begin
            if (slave_idx == i[IDX_W-1:0]) begin
                s_cs_n[i] = 1'b0;                      // Assert chip-select
            end
        end
    end

endmodule