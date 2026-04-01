// ============================================================================
// Project     : simpleRISC-V
// Module      : srv_core_if_stage
// Description : Instruction fetch stage wrapper. It aligns the PC check with
//               the shared-bus fetch command timing.
// ============================================================================

`include "core_defines.vh"

module srv_core_if_stage #(
    parameter XLEN   = `SRV_CORE_XLEN,
    parameter ADDR_W = `SRV_CORE_ADDR_W
) (
    input  wire                 clk,
    input  wire                 rst_n,
    input  wire                 fetch_req_i,
    input  wire [ADDR_W-1:0]    pc_i,

    input  wire [XLEN-1:0]      bus_rd_data_i,
    input  wire                 bus_rdy_n_i,
    input  wire                 bus_grnt_n_i,
    output wire                 bus_req_n_o,
    output wire [ADDR_W-1:0]    bus_addr_o,
    output wire                 bus_as_n_o,
    output wire                 bus_rw_o,
    output wire [XLEN-1:0]      bus_wr_data_o,

    output wire                 fetch_done_o,
    output wire [XLEN-1:0]      fetch_insn_o,
    output wire [ADDR_W-1:0]    seq_pc_o,
    output wire                 fetch_misaligned_o
);

    localparam [ADDR_W-1:0] PC_STEP = {{(ADDR_W-4){1'b0}}, 4'd4};

    wire unused_busy_w;

    assign seq_pc_o           = pc_i + PC_STEP;
    assign fetch_misaligned_o = (pc_i[1:0] != 2'b00);

    srv_core_bus_if u_bus_if (
        .clk          (clk),
        .rst_n        (rst_n),
        .cmd_valid_i  (fetch_req_i),
        .cmd_addr_i   (pc_i),
        .cmd_write_i  (1'b0),
        .cmd_wdata_i  ({XLEN{1'b0}}),
        .busy_o       (unused_busy_w),
        .done_o       (fetch_done_o),
        .rd_data_o    (fetch_insn_o),
        .bus_rd_data_i(bus_rd_data_i),
        .bus_rdy_n_i  (bus_rdy_n_i),
        .bus_grnt_n_i (bus_grnt_n_i),
        .bus_req_n_o  (bus_req_n_o),
        .bus_addr_o   (bus_addr_o),
        .bus_as_n_o   (bus_as_n_o),
        .bus_rw_o     (bus_rw_o),
        .bus_wr_data_o(bus_wr_data_o)
    );

endmodule
