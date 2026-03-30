// ============================================================================
// Project     : simpleRISC-V
// Module      : bus_arbiter
// Description : Round-robin bus arbiter with parameterized master count.
//               Grants bus ownership to one master at a time. When the current
//               owner releases the bus, ownership rotates to the next
//               requesting master in round-robin order.
//               All request/grant signals are active-low.
// ============================================================================

module bus_arbiter #(
    parameter NUM_MASTERS = 4                       // Number of bus masters
) (
    input  wire                     clk,            // System clock
    input  wire                     rst_n,          // Async reset, active-low
    input  wire [NUM_MASTERS-1:0]   req_n,          // Bus request (active-low)
    output reg  [NUM_MASTERS-1:0]   grnt_n          // Bus grant   (active-low)
);

    // ========================================================================
    // Internal Signals
    // ========================================================================
    reg [$clog2(NUM_MASTERS)-1:0] owner;            // Current bus owner index
    reg                           bus_busy;         // current bus busy flag

    // Next-state combinational signals
    reg [$clog2(NUM_MASTERS)-1:0] next_owner;       // next bus owner index 
    reg                           next_busy;        // next bus busy flag

    integer i;

    // ========================================================================
    // Round-Robin Arbitration Logic (combinational)
    // ========================================================================
    always @(*) begin
        next_owner = owner;
        next_busy  = 1'b0;

        if (bus_busy && ~req_n[owner]) begin // Current owner still holds the bus
            next_owner = owner;
            next_busy  = 1'b1;
        end else begin // Bus is free — scan from (owner+1) in round-robin
            next_busy = 1'b0;
            for (i = 0; i < NUM_MASTERS; i = i + 1) begin
                if (~next_busy) begin : scan
                    // Compute candidate index with wrap-around
                    if (~req_n[(owner + 1 + i) % NUM_MASTERS]) begin
                        next_owner = (owner + 1 + i) % NUM_MASTERS;
                        next_busy  = 1'b1;
                    end
                end
            end
        end
    end

    // ========================================================================
    // Grant Output Decode
    // ========================================================================
    always @(*) begin
        grnt_n = {NUM_MASTERS{1'b1}};              // Default: all deasserted
        if (next_busy) begin
            grnt_n[next_owner] = 1'b0;             // Assert grant for winner
        end
    end

    // ========================================================================
    // State Register
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            owner    <= {$clog2(NUM_MASTERS){1'b0}};
            bus_busy <= 1'b0;
        end else begin
            owner    <= next_owner;
            bus_busy <= next_busy;
        end
    end

endmodule
