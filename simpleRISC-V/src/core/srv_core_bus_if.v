// ============================================================================
// Project     : simpleRISC-V
// Module      : srv_core_bus_if
// Description : Bus master handshake adapter aligned to the current SimpleRISC-V
//               shared-bus timing.
// ============================================================================

`include "bus_defines.vh"

module srv_core_bus_if #(
    parameter ADDR_W = `SRV_BUS_ADDR_W,
    parameter DATA_W = `SRV_BUS_DATA_W
) (
    input  wire                 clk,
    input  wire                 rst_n,
    input  wire                 cmd_valid_i,
    input  wire [ADDR_W-1:0]    cmd_addr_i,
    input  wire                 cmd_write_i,
    input  wire [DATA_W-1:0]    cmd_wdata_i,
    output reg                  busy_o,
    output reg                  done_o,
    output reg  [DATA_W-1:0]    rd_data_o,
    input  wire [DATA_W-1:0]    bus_rd_data_i,
    input  wire                 bus_rdy_n_i,
    input  wire                 bus_grnt_n_i,
    output reg                  bus_req_n_o,
    output reg  [ADDR_W-1:0]    bus_addr_o,
    output reg                  bus_as_n_o,
    output reg                  bus_rw_o,
    output reg  [DATA_W-1:0]    bus_wr_data_o
);

    localparam [1:0] ST_IDLE   = 2'd0;
    localparam [1:0] ST_REQ    = 2'd1;
    localparam [1:0] ST_ACCESS = 2'd2;

    reg [1:0] state_q;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_q       <= ST_IDLE;
            busy_o        <= 1'b0;
            done_o        <= 1'b0;
            rd_data_o     <= {DATA_W{1'b0}};
            bus_req_n_o   <= `SRV_BUS_INACTIVE_N;
            bus_addr_o    <= {ADDR_W{1'b0}};
            bus_as_n_o    <= `SRV_BUS_INACTIVE_N;
            bus_rw_o      <= `SRV_BUS_READ;
            bus_wr_data_o <= {DATA_W{1'b0}};
        end else begin
            done_o <= 1'b0;

            case (state_q)
                ST_IDLE: begin
                    busy_o      <= 1'b0;
                    bus_req_n_o <= `SRV_BUS_INACTIVE_N;
                    bus_as_n_o  <= `SRV_BUS_INACTIVE_N;
                    bus_rw_o    <= `SRV_BUS_READ;

                    if (cmd_valid_i) begin
                        state_q       <= ST_REQ;
                        busy_o        <= 1'b1;
                        bus_req_n_o   <= `SRV_BUS_ACTIVE_N;
                        bus_addr_o    <= cmd_addr_i;
                        bus_rw_o      <= cmd_write_i ? `SRV_BUS_WRITE : `SRV_BUS_READ;
                        bus_wr_data_o <= cmd_wdata_i;
                    end
                end
                ST_REQ: begin
                    busy_o <= 1'b1;
                    if (bus_grnt_n_i == `SRV_BUS_ACTIVE_N) begin
                        state_q    <= ST_ACCESS;
                        bus_as_n_o <= `SRV_BUS_ACTIVE_N;
                    end
                end
                ST_ACCESS: begin
                    busy_o     <= 1'b1;
                    bus_as_n_o <= `SRV_BUS_INACTIVE_N;

                    if (bus_rdy_n_i == `SRV_BUS_ACTIVE_N) begin
                        state_q       <= ST_IDLE;
                        busy_o        <= 1'b0;
                        done_o        <= 1'b1;
                        bus_req_n_o   <= `SRV_BUS_INACTIVE_N;
                        bus_addr_o    <= {ADDR_W{1'b0}};
                        bus_rw_o      <= `SRV_BUS_READ;
                        bus_wr_data_o <= {DATA_W{1'b0}};
                        if (!bus_rw_o) begin
                            rd_data_o <= rd_data_o;
                        end else begin
                            rd_data_o <= bus_rd_data_i;
                        end
                    end
                end
                default: begin
                    state_q <= ST_IDLE;
                    busy_o  <= 1'b0;
                end
            endcase
        end
    end

endmodule
