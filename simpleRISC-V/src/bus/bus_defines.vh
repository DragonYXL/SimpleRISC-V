// ============================================================================
// Project     : simpleRISC-V
// File        : bus_defines.vh
// Description : Local bus definitions for the SimpleRISC-V shared bus.
// ============================================================================

`ifndef SRV_BUS_DEFINES_VH
`define SRV_BUS_DEFINES_VH

`define SRV_BUS_MASTER_NUM      4
`define SRV_BUS_SLAVE_NUM       8
`define SRV_BUS_ADDR_W          32
`define SRV_BUS_DATA_W          32
`define SRV_BUS_SLAVE_IDX_MSB   31
`define SRV_BUS_SLAVE_IDX_LSB   29
`define SRV_BUS_ACTIVE_N        1'b0
`define SRV_BUS_INACTIVE_N      1'b1
`define SRV_BUS_READ            1'b1
`define SRV_BUS_WRITE           1'b0
`define SRV_BUS_ADDR_ALIGN_LSB  2

`endif
