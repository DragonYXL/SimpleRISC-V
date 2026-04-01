// ============================================================================
// Project     : simpleRISC-V
// Module      : srv_core_mem_stage
// Description : Memory stage wrapper. It drives the shared bus for data
//               accesses and generates the load write-back payload.
// ============================================================================

`include "core_defines.vh"

module srv_core_mem_stage #(
    parameter XLEN   = `SRV_CORE_XLEN,
    parameter ADDR_W = `SRV_CORE_ADDR_W,
    parameter REG_W  = `SRV_CORE_REG_ADDR_W
) (
    input  wire                 clk,
    input  wire                 rst_n,
    input  wire                 mem_req_i,
    input  wire [ADDR_W-1:0]    mem_addr_i,
    input  wire                 mem_write_i,
    input  wire [XLEN-1:0]      mem_wdata_i,
    input  wire                 mem_is_load_i,
    input  wire [REG_W-1:0]     mem_rd_i,
    input  wire [ADDR_W-1:0]    mem_next_pc_i,

    input  wire [XLEN-1:0]      bus_rd_data_i,
    input  wire                 bus_rdy_n_i,
    input  wire                 bus_grnt_n_i,
    output wire                 bus_req_n_o,
    output wire [ADDR_W-1:0]    bus_addr_o,
    output wire                 bus_as_n_o,
    output wire                 bus_rw_o,
    output wire [XLEN-1:0]      bus_wr_data_o,

    output wire                 mem_done_o,
    output wire                 wb_en_o,
    output wire [REG_W-1:0]     wb_addr_o,
    output wire [XLEN-1:0]      wb_data_o,
    output wire [ADDR_W-1:0]    next_pc_o
);

    wire unused_busy_w;
    wire [XLEN-1:0] mem_rdata_w;

    assign wb_en_o   = mem_done_o && mem_is_load_i;
    assign wb_addr_o = mem_rd_i;
    assign wb_data_o = mem_rdata_w;
    assign next_pc_o = mem_next_pc_i;

    srv_core_bus_if u_bus_if (
        .clk          (clk),
        .rst_n        (rst_n),
        .cmd_valid_i  (mem_req_i),
        .cmd_addr_i   (mem_addr_i),
        .cmd_write_i  (mem_write_i),
        .cmd_wdata_i  (mem_wdata_i),
        .busy_o       (unused_busy_w),
        .done_o       (mem_done_o),
        .rd_data_o    (mem_rdata_w),
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
