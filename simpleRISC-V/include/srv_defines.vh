// ============================================================================
// Project     : simpleRISC-V
// File        : srv_defines.vh
// Description : Global definitions and parameters for the simpleRISC-V project.
//               All bus-width and address-space constants are centralized here.
// ============================================================================

`ifndef SRV_DEFINES_VH
`define SRV_DEFINES_VH

// ----------------------------------------------------------------------------
// Data Bus
// ----------------------------------------------------------------------------
`define SRV_DATA_W          32              // Data width (bits)
`define SRV_DATA_BUS        31:0            // Data bus range

// ----------------------------------------------------------------------------
// Address Bus (word-addressed, 30-bit word address)
// ----------------------------------------------------------------------------
`define SRV_ADDR_W          32              // Full byte address width
`define SRV_WORD_ADDR_W     30              // Word address width (addr[31:2])
`define SRV_WORD_ADDR_BUS   29:0            // Word address bus range

// ----------------------------------------------------------------------------
// Bus Topology Defaults
// ----------------------------------------------------------------------------
`define SRV_BUS_MASTER_NUM  4               // Number of bus masters
`define SRV_BUS_SLAVE_NUM   8               // Number of bus slaves
`define SRV_SLAVE_IDX_W     3               // ceil(log2(SLAVE_NUM))

// Slave index is decoded from address bits [31:29] by default
`define SRV_SLAVE_IDX_LOC   31:29

// ----------------------------------------------------------------------------
// Active-Low Signal Conventions
// ----------------------------------------------------------------------------
`define SRV_ENABLE_         1'b0            // Active-low enable
`define SRV_DISABLE_        1'b1            // Active-low disable

// ----------------------------------------------------------------------------
// Read / Write
// ----------------------------------------------------------------------------
`define SRV_READ            1'b1
`define SRV_WRITE           1'b0

`endif // SRV_DEFINES_VH
