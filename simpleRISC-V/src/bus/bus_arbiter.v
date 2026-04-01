// ============================================================================
// Project     : simpleRISC-V
// Module      : bus_arbiter
// Description : Fixed-priority bus arbiter with parameterized master count.
//               Grants bus ownership to one master at a time. When the current
//               owner releases the bus, the arbiter selects the first active
//               request in index order, so lower-index masters always have
//               higher priority.
//               All request/grant signals are active-low.
//               Grant output is registered to eliminate combinational glitches.
//               The lock input holds the current grant during an active
//               transaction (slave has not yet responded with ready).
// ============================================================================

`include "bus_defines.vh"

module bus_arbiter #(
        parameter NUM_MASTERS = `SRV_BUS_MASTER_NUM    // Number of bus masters
    ) (
        input  wire                     clk,            // System clock
        input  wire                     rst_n,          // Async reset, active-low
        input  wire [NUM_MASTERS-1:0]   req_n,          // Bus request (active-low)
        output reg  [NUM_MASTERS-1:0]   grnt_n          // Bus grant   (active-low, registered)
    );

    localparam integer OWNER_W = (NUM_MASTERS > 1) ? $clog2(NUM_MASTERS) : 1;

    // ========================================================================
    // Internal Signals
    // ========================================================================
    reg [OWNER_W-1:0]               owner;          // Current bus owner index
    reg                             owned;          // Bus currently has an owner

    // Next-state combinational signals
    reg [OWNER_W-1:0]               next_owner;     // Next bus owner index
    reg                             next_owned;     // Bus next cycle will have an owner
    reg                             grant_found;    // First request of master found flag

    integer i;

    // ========================================================================
    // Fixed-Priority Arbitration Logic (combinational)
    // ========================================================================
    always @(*) begin
        next_owner  = owner;
        next_owned  = 1'b0;
        grant_found = 1'b0;
        if (owned && ~req_n[owner]) begin
            // Current owner keeps the bus until its request is released
            next_owner = owner;
            next_owned = 1'b1;
        end
        else begin
            // Bus idle or owner released: scan from low to high index
            for (i = 0; i < NUM_MASTERS; i = i + 1) begin
                if (~grant_found && ~req_n[i]) begin
                    next_owner  = i[OWNER_W-1:0];
                    next_owned  = 1'b1;
                    grant_found = 1'b1;
                end
            end
        end
    end

    // ========================================================================
    // Registered Grant Output + State Update
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            owner  <= {OWNER_W{1'b0}};
            owned  <= 1'b0;
            grnt_n <= {NUM_MASTERS{1'b1}};
        end
        else begin
            owner  <= next_owner;
            owned  <= next_owned;
            grnt_n <= {NUM_MASTERS{1'b1}};
            if (next_owned)
                grnt_n[next_owner] <= 1'b0;
        end
    end

endmodule
