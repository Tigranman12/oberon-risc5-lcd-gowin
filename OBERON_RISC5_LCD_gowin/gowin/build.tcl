# OBERON_RISC5_FAST on the Tang Nano 9K: RISC5 + UART, the monitor in the boot ROM; O6: memory = the PSRAM through a 32 KB cache.
# Top: r5_board (rPLL, PLAN.md) around r5_tang. Wirth's unchanged files come from ../../OBERON_RISC5/rtl.
# Run from this folder with ./gw_build.sh (it sets the Qt/library paths gw_sh needs). Output: impl/pnr/r5_tang.fs
set_device -name GW1NR-9C GW1NR-LV9QN88PC6/I5
add_file ../rtl/RISC5F.v
add_file ../rtl/r5_prom.v
foreach f {Multiplier Divider FPAdder FPMultiplier FPDivider SPI} { add_file ../../OBERON_RISC5/rtl/wirth/$f.v }
foreach f {RS232R RS232T} { add_file ../../OBERON_RISC5/rtl/port/$f.v }
add_file ../rtl/r5_psram.v
add_file ../rtl/r5_cache.v
add_file ../rtl/r5_lcd.v
add_file ../rtl/r5_tang.v
add_file ../rtl/r5_board.v
add_file r5.cst
add_file r5.sdc
set_option -top_module r5_board
set_option -output_base_name r5_tang
set_option -verilog_std v2001
set_option -use_mspi_as_gpio 1   ;# L1: some LCD pins are MSPI/SSPI pins (as G9_FTL_ARCH_V3, Sipeed)
set_option -use_sspi_as_gpio 1

# PROM.v loads "prom.mem" with $readmemh; synthesis looks for it in the folder where gw_sh runs
if {![file exists ../build/prom.mem]} {
    puts "ERROR: ../build/prom.mem not found. Run ../run_rf.sh first: it assembles programs/monitor.s."
    exit 1
}
file copy -force ../build/prom.mem ./prom.mem
puts "OBERON_RISC5_LCD_gowin: Tang Nano 9K build"

run all
