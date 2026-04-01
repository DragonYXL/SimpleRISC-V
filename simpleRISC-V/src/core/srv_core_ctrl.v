// ============================================================================
// Project     : simpleRISC-V
// Module      : srv_core_ctrl
// Description : Core control FSM for the non-pipelined SimpleRISC-V RV32 core.
// ============================================================================

`include "core_defines.vh"

module srv_core_ctrl (
    input  wire [`SRV_CORE_STATE_W-1:0] state_i,
    input  wire                         fetch_misaligned_i,
    input  wire                         if_cmd_done_i,
    input  wire                         exec_trap_i,
    input  wire                         exec_mem_req_i,
    input  wire                         mem_cmd_done_i,
    output wire                         if_cmd_valid_o,
    output wire                         mem_cmd_valid_o,
    output reg  [`SRV_CORE_STATE_W-1:0] next_state_o,
    output reg                          reset_state_o,
    output reg                          fetch_fault_o,
    output reg                          fetch_accept_o,
    output reg                          execute_trap_o,
    output reg                          execute_mem_o,
    output reg                          execute_commit_o,
    output reg                          mem_complete_o
);

    assign if_cmd_valid_o  = (state_i == `SRV_CORE_STATE_FETCH_REQ) && !fetch_misaligned_i;
    assign mem_cmd_valid_o = (state_i == `SRV_CORE_STATE_MEM_REQ);

    always @(*) begin
        next_state_o     = state_i;
        reset_state_o    = 1'b0;
        fetch_fault_o    = 1'b0;
        fetch_accept_o   = 1'b0;
        execute_trap_o   = 1'b0;
        execute_mem_o    = 1'b0;
        execute_commit_o = 1'b0;
        mem_complete_o   = 1'b0;

        case (state_i)
            `SRV_CORE_STATE_RESET: begin
                reset_state_o = 1'b1;
                next_state_o  = `SRV_CORE_STATE_FETCH_REQ;
            end
            `SRV_CORE_STATE_FETCH_REQ: begin
                if (fetch_misaligned_i) begin
                    fetch_fault_o = 1'b1;
                    next_state_o  = `SRV_CORE_STATE_TRAP;
                end else begin
                    next_state_o  = `SRV_CORE_STATE_FETCH_WAIT;
                end
            end
            `SRV_CORE_STATE_FETCH_WAIT: begin
                if (if_cmd_done_i) begin
                    fetch_accept_o = 1'b1;
                    next_state_o   = `SRV_CORE_STATE_EXECUTE;
                end
            end
            `SRV_CORE_STATE_EXECUTE: begin
                if (exec_trap_i) begin
                    execute_trap_o = 1'b1;
                    next_state_o   = `SRV_CORE_STATE_TRAP;
                end else if (exec_mem_req_i) begin
                    execute_mem_o = 1'b1;
                    next_state_o  = `SRV_CORE_STATE_MEM_REQ;
                end else begin
                    execute_commit_o = 1'b1;
                    next_state_o     = `SRV_CORE_STATE_FETCH_REQ;
                end
            end
            `SRV_CORE_STATE_MEM_REQ: begin
                next_state_o = `SRV_CORE_STATE_MEM_WAIT;
            end
            `SRV_CORE_STATE_MEM_WAIT: begin
                if (mem_cmd_done_i) begin
                    mem_complete_o = 1'b1;
                    next_state_o   = `SRV_CORE_STATE_FETCH_REQ;
                end
            end
            `SRV_CORE_STATE_TRAP: begin
                next_state_o = `SRV_CORE_STATE_TRAP;
            end
            default: begin
                next_state_o  = `SRV_CORE_STATE_RESET;
                reset_state_o = 1'b1;
            end
        endcase
    end

endmodule
