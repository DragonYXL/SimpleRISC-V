// ============================================================================
// Project     : simpleRISC-V
// File        : peripheral_defines.vh
// Description : Local peripheral definitions for the SimpleRISC-V peripheral
//               subsystem.
// ============================================================================

`ifndef SRV_PERIPHERAL_DEFINES_VH
`define SRV_PERIPHERAL_DEFINES_VH

`define SRV_PERIPH_ADDR_W              32
`define SRV_PERIPH_DATA_W              32
`define SRV_PERIPH_NUM_SLAVES          8
`define SRV_PERIPH_ADDR_ALIGN_LSB      2
`define SRV_PERIPH_ACTIVE_N            1'b0
`define SRV_PERIPH_INACTIVE_N          1'b1
`define SRV_PERIPH_READ                1'b1
`define SRV_PERIPH_WRITE               1'b0

`define SRV_PERIPH_SLOT_ROM            0
`define SRV_PERIPH_SLOT_GPIO           1
`define SRV_PERIPH_SLOT_TIMER          2
`define SRV_PERIPH_SLOT_UART           3

`define SRV_GPIO_IN_W                  4
`define SRV_GPIO_OUT_W                 18
`define SRV_GPIO_IO_W                  16
`define SRV_GPIO_REG_ADDR_W            2
`define SRV_GPIO_REG_IN_DATA           2'd0
`define SRV_GPIO_REG_OUT_DATA          2'd1
`define SRV_GPIO_REG_IO_DATA           2'd2
`define SRV_GPIO_REG_IO_OE             2'd3

`define SRV_TIMER_REG_ADDR_W           2
`define SRV_TIMER_REG_CTRL             2'd0
`define SRV_TIMER_REG_IRQ              2'd1
`define SRV_TIMER_REG_COMPARE          2'd2
`define SRV_TIMER_REG_COUNT            2'd3
`define SRV_TIMER_CTRL_EN_BIT          0
`define SRV_TIMER_CTRL_PERIODIC_BIT    1
`define SRV_TIMER_IRQ_BIT              0

`define SRV_ROM_WORDS                  2048
`define SRV_ROM_WORD_ADDR_W            11

`define SRV_UART_REG_ADDR_W            1
`define SRV_UART_REG_STATUS            1'b0
`define SRV_UART_REG_DATA              1'b1
`define SRV_UART_STATUS_IRQ_RX_BIT     0
`define SRV_UART_STATUS_IRQ_TX_BIT     1
`define SRV_UART_STATUS_RX_BUSY_BIT    2
`define SRV_UART_STATUS_TX_BUSY_BIT    3
`define SRV_UART_DATA_W                8
`define SRV_UART_DIVISOR               9'd260
`define SRV_UART_DIV_W                 9
`define SRV_UART_TX_IDLE               1'b0
`define SRV_UART_TX_BUSY               1'b1
`define SRV_UART_RX_IDLE               1'b0
`define SRV_UART_RX_BUSY               1'b1
`define SRV_UART_START_BIT             1'b0
`define SRV_UART_STOP_BIT              1'b1

`endif
