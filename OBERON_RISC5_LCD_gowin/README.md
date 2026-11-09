# OBERON_RISC5_LCD_gowin: Project Oberon on the Tang Nano 9K with the 4.3" LCD

A new project started from `../OBERON_RISC5_FAST` at commit e2a4770 (RISC5F at 16.875 MHz, 4 MB PSRAM through an
8 KB cache, monitor in the boot ROM, Oberon V5 + TTY booted from the SD card). Goal: Oberon's own screen on the
Sipeed 4.3" 480 x 272 RGB LCD (one bit per pixel), so that Oberon's graphics (viewers, Hilbert, Sierpinski)
appear on the panel. Commands are typed on the serial line (TTY, PuTTY 115200 8N1); there is no mouse.
`../OBERON_RISC5_FAST` stays as it is.

| file | what |
|---|---|
| `rtl/` | RISC5F CPU, board top `r5_tang.v`, cache, PSRAM, boot ROM (from OBERON_RISC5_FAST; L1 adds the LCD) |
| `programs/monitor.s` | boot-ROM monitor (`?` lists its commands; `o` boots Oberon from the SD card) |
| `oberon/` | TTY.Mod (Oberon's command line on the serial line), Hello.Mod |
| `tools/` | assembler front ends, SD and RAM-disk loaders, Oberon disk builder (`mkdisk.sh`), emulator |
| `tb/`, `run_rf.sh` | simulation: a terminal model types monitor commands and checks the answers (about 21 min) |
| `rtl/r5_lcd.v`, `tb/tb_lcd.v`, `run_lcd.sh` | L1: LCD frame memory at 400000H + panel controller; its fast test (3 s) |
| `programs/lcdtest.s` | L1: test picture (border, square at the bottom-left, diagonal, STB block): `r5load.py`, `g 4000` |
| `gowin/` | Gowin build (`build.tcl`, `r5.cst`, `r5.sdc`, `gw_build.sh`) |
| `PLAN.md`, `TASK.md`, `INFO.md`, `ARTICLE.md` | design and stages, state, the user's directions, the article |

Used read only: `../OBERON_RISC5` (Wirth's Verilog, ported UART/PROM), `../tools/r5` (assembler).

Setting up the demo on another PC (software, SD card, programming, demo commands, rebuild, problems): `DEMO.md`.

## Run (the user runs these, through `runlog`)

```
cd ~/workspace/GARDMAN/gardman/OBERON_RISC5_LCD_gowin
runlog lcd_sim ./run_rf.sh                # simulation, ends with TB PASS
./run_lcd.sh                              # L1: LCD alone, 3 s
cd gowin && runlog lcd_gowin ./gw_build.sh   # Gowin build -> impl/pnr/r5_tang.fs
```

Board, after plugging it in: free the JTAG channel (`ls /sys/bus/usb/drivers/ftdi_sio/`, then
`echo -n "<port>:1.0" | sudo tee /sys/bus/usb/drivers/ftdi_sio/unbind`), `runlog lcd_reprog tools/reprog.sh`,
then PuTTY `sg dialout -c "putty -serial /dev/ttyUSB1 -sercfg 115200,8,n,1,N"` and `o` at `r5>`.
