// ============================================================================
// Project     : simpleRISC-V
// Module      : bus_arbiter
// Description : Fixed-priority bus arbiter with parameterized master count.
//               Grants bus ownership to one master at a time. When the current
//               owner releases the bus, the arbiter selects the first active
//               request in index order, so lower-index masters always have
//               higher priority.
//               All request/grant signals are active-low.
// ============================================================================

`default_nettype none

module bus_arbiter #(
        parameter NUM_MASTERS = 4                       // Number of bus masters
    ) (
        input  wire                     clk,            // System clock
        input  wire                     rst_n,          // Async reset, active-low
        input  wire [NUM_MASTERS-1:0]   req_n,          // Bus request (active-low)
        output reg  [NUM_MASTERS-1:0]   grnt_n          // Bus grant   (active-low)
    );

    localparam integer OWNER_W = (NUM_MASTERS > 1) ? $clog2(NUM_MASTERS) : 1;

    // ========================================================================
    // Internal Signals
    // ========================================================================
    reg [OWNER_W-1:0]               owner;          // Current bus owner index
    reg                             bus_busy;       // Current bus busy flag

    // Next-state combinational signals
    reg [OWNER_W-1:0]               next_owner;     // Next bus owner index
    reg                             next_busy;      // Next bus busy flag
    reg                             grant_found;    // First requester found flag (used for multi master contention)

    integer i;

    // ========================================================================
    // Fixed-Priority Arbitration Logic (combinational)
    // ========================================================================
    always @(*) begin
        next_owner  = owner;
        next_busy   = 1'b0;
        grant_found = 1'b0;

        if (bus_busy && ~req_n[owner]) begin
            // Current owner keeps the bus until its request is released.
            next_owner = owner;
            next_busy  = 1'b1;
        end
        else begin
            // Bus is idle: scan requests from low index to high index.
            for (i = 0; i < NUM_MASTERS; i = i + 1) begin
                if (~grant_found && ~req_n[i]) begin
                    next_owner  = i[OWNER_W-1:0];
                    next_busy   = 1'b1;
                    grant_found = 1'b1;
                end
            end
        end
    end

    // ========================================================================
    // Grant Output Decode
    // ========================================================================
    always @(*) begin
        grnt_n = {NUM_MASTERS{1'b1}};               // Default: all deasserted
        if (next_busy) begin
            grnt_n[next_owner] = 1'b0;              // Assert grant for winner
        end
    end

    // ========================================================================
    // State Register
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            owner    <= {OWNER_W{1'b0}};
            bus_busy <= 1'b0;
        end
        else begin
            owner    <= next_owner;
            bus_busy <= next_busy;
        end
    end

endmodule

`default_nettype wire
