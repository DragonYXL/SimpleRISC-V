// ============================================================================
// Project     : simpleRISC-V
// Module      : srv_peripherals
// Description : Peripheral subsystem wrapper for the SimpleRISC-V bus.
//               Instantiates ROM, GPIO, TIMER, and UART peripherals and packs
//               their responses into the shared slave response vectors.
// ============================================================================

`include "peripheral_defines.vh"

module srv_peripherals #(
    parameter NUM_SLAVES = `SRV_PERIPH_NUM_SLAVES,
    parameter ADDR_W     = `SRV_PERIPH_ADDR_W,
    parameter DATA_W     = `SRV_PERIPH_DATA_W,
    parameter ROM_SLOT   = `SRV_PERIPH_SLOT_ROM,
    parameter GPIO_SLOT  = `SRV_PERIPH_SLOT_GPIO,
    parameter TIMER_SLOT = `SRV_PERIPH_SLOT_TIMER,
    parameter UART_SLOT  = `SRV_PERIPH_SLOT_UART
) (
    input  wire                           clk,
    input  wire                           rst_n,
    input  wire [ADDR_W-1:0]              s_addr,
    input  wire                           s_as_n,
    input  wire                           s_rw,
    input  wire [DATA_W-1:0]              s_wr_data,
    input  wire [NUM_SLAVES-1:0]          s_cs_n,
    output reg  [NUM_SLAVES*DATA_W-1:0]   s_rd_data,
    output reg  [NUM_SLAVES-1:0]          s_rdy_n,
    input  wire [`SRV_GPIO_IN_W-1:0]      gpio_in_i,
    output wire [`SRV_GPIO_OUT_W-1:0]     gpio_out_o,
    input  wire [`SRV_GPIO_IO_W-1:0]      gpio_io_i,
    output wire [`SRV_GPIO_IO_W-1:0]      gpio_io_o,
    output wire [`SRV_GPIO_IO_W-1:0]      gpio_io_oe_o,
    output wire                           timer_irq_o,
    input  wire                           uart_rx_i,
    output wire                           uart_tx_o,
    output wire                           uart_irq_rx_o,
    output wire                           uart_irq_tx_o
);

    wire [DATA_W-1:0] rom_rd_data;
    wire [DATA_W-1:0] gpio_rd_data;
    wire [DATA_W-1:0] timer_rd_data;
    wire [DATA_W-1:0] uart_rd_data;
    wire              rom_rdy_n;
    wire              gpio_rdy_n;
    wire              timer_rdy_n;
    wire              uart_rdy_n;

    srv_rom u_rom (
        .clk     (clk),
        .rst_n   (rst_n),
        .cs_n    (s_cs_n[ROM_SLOT]),
        .as_n    (s_as_n),
        .rw      (s_rw),
        .addr    (s_addr),
        .wr_data (s_wr_data),
        .rd_data (rom_rd_data),
        .rdy_n   (rom_rdy_n)
    );

    srv_gpio u_gpio (
        .clk         (clk),
        .rst_n       (rst_n),
        .cs_n        (s_cs_n[GPIO_SLOT]),
        .as_n        (s_as_n),
        .rw          (s_rw),
        .addr        (s_addr),
        .wr_data     (s_wr_data),
        .rd_data     (gpio_rd_data),
        .rdy_n       (gpio_rdy_n),
        .gpio_in_i   (gpio_in_i),
        .gpio_out_o  (gpio_out_o),
        .gpio_io_i   (gpio_io_i),
        .gpio_io_o   (gpio_io_o),
        .gpio_io_oe_o(gpio_io_oe_o)
    );

    srv_timer u_timer (
        .clk     (clk),
        .rst_n   (rst_n),
        .cs_n    (s_cs_n[TIMER_SLOT]),
        .as_n    (s_as_n),
        .rw      (s_rw),
        .addr    (s_addr),
        .wr_data (s_wr_data),
        .rd_data (timer_rd_data),
        .rdy_n   (timer_rdy_n),
        .irq_o   (timer_irq_o)
    );

    srv_uart u_uart (
        .clk      (clk),
        .rst_n    (rst_n),
        .cs_n     (s_cs_n[UART_SLOT]),
        .as_n     (s_as_n),
        .rw       (s_rw),
        .addr     (s_addr),
        .wr_data  (s_wr_data),
        .rd_data  (uart_rd_data),
        .rdy_n    (uart_rdy_n),
        .irq_rx_o (uart_irq_rx_o),
        .irq_tx_o (uart_irq_tx_o),
        .uart_rx_i(uart_rx_i),
        .uart_tx_o(uart_tx_o)
    );

    always @(*) begin
        s_rd_data = {NUM_SLAVES*DATA_W{1'b0}};
        s_rdy_n   = {NUM_SLAVES{1'b1}};

        s_rd_data[ROM_SLOT*DATA_W +: DATA_W]   = rom_rd_data;
        s_rd_data[GPIO_SLOT*DATA_W +: DATA_W]  = gpio_rd_data;
        s_rd_data[TIMER_SLOT*DATA_W +: DATA_W] = timer_rd_data;
        s_rd_data[UART_SLOT*DATA_W +: DATA_W]  = uart_rd_data;

        s_rdy_n[ROM_SLOT]   = rom_rdy_n;
        s_rdy_n[GPIO_SLOT]  = gpio_rdy_n;
        s_rdy_n[TIMER_SLOT] = timer_rdy_n;
        s_rdy_n[UART_SLOT]  = uart_rdy_n;
    end

endmodule
