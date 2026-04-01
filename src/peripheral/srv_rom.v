// ============================================================================
// Project     : simpleRISC-V
// Module      : srv_rom
// Description : Generic synchronous ROM peripheral.
// ============================================================================

`include "peripheral_defines.vh"

module srv_rom #(
    parameter ADDR_W        = `SRV_PERIPH_ADDR_W,
    parameter DATA_W        = `SRV_PERIPH_DATA_W,
    parameter ROM_WORDS     = `SRV_ROM_WORDS,
    parameter ROM_ADDR_W    = `SRV_ROM_WORD_ADDR_W,
    parameter MEM_INIT_EN   = 0,
    parameter MEM_INIT_FILE = ""
) (
    input  wire                 clk,
    input  wire                 rst_n,
    input  wire                 cs_n,
    input  wire                 as_n,
    input  wire                 rw,
    input  wire [ADDR_W-1:0]    addr,
    input  wire [DATA_W-1:0]    wr_data,
    output reg  [DATA_W-1:0]    rd_data,
    output reg                  rdy_n
);

    localparam integer ADDR_LSB = `SRV_PERIPH_ADDR_ALIGN_LSB;

    reg [DATA_W-1:0] mem [0:ROM_WORDS-1];

    integer idx;
    wire access_valid;
    wire [ROM_ADDR_W-1:0] word_addr;

    assign access_valid = (cs_n == `SRV_PERIPH_ACTIVE_N) &&
                          (as_n == `SRV_PERIPH_ACTIVE_N);
    assign word_addr    = addr[ADDR_LSB + ROM_ADDR_W - 1:ADDR_LSB];

    initial begin
        for (idx = 0; idx < ROM_WORDS; idx = idx + 1) begin
            mem[idx] = {DATA_W{1'b0}};
        end
        if (MEM_INIT_EN) begin
            $readmemh(MEM_INIT_FILE, mem);
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_data <= {DATA_W{1'b0}};
            rdy_n   <= `SRV_PERIPH_INACTIVE_N;
        end else begin
            rdy_n   <= access_valid ? `SRV_PERIPH_ACTIVE_N : `SRV_PERIPH_INACTIVE_N;
            rd_data <= {DATA_W{1'b0}};

            if (access_valid && (rw == `SRV_PERIPH_READ) && (word_addr < ROM_WORDS)) begin
                rd_data <= mem[word_addr];
            end
        end
    end

endmodule
