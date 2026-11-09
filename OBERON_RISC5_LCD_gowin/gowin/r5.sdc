// 27 MHz crystal; the rPLL output (16.875 MHz) runs the CPU (rtl/r5_board.v, PLAN.md D4)
create_clock -name clk27 -period 37.037 [get_ports {clk}]
create_generated_clock -name clk_cpu -source [get_ports {clk}] -master_clock clk27 -multiply_by 5 -divide_by 8 [get_pins {pll/CLKOUT}]
# O3: the PSRAM controller's clock: mpll 27 x 2 = 54 MHz. CPU <-> controller: a toggle handshake through
# 2 flip-flops and registers held stable meanwhile, so no timed paths between the two clocks.
create_generated_clock -name mclk -source [get_ports {clk}] -master_clock clk27 -multiply_by 2 [get_pins {mpll/CLKOUT}]
set_clock_groups -asynchronous -group [get_clocks {clk_cpu}] -group [get_clocks {mclk}]
# L1: the LCD side of r5_lcd runs on clk27 itself; the CPU and LCD sides share only the frame memory's two
# ports, so no timed paths between them.
set_clock_groups -asynchronous -group [get_clocks {clk_cpu}] -group [get_clocks {clk27}]
