# Project Oberon on the Tang Nano 9K with the 4.3" LCD: setup, build and demo

This guide sets up the demo on a new Linux PC: Niklaus Wirth's Project Oberon V5 runs on a RISC5 CPU in the
Tang Nano 9K's FPGA, boots from a microSD card, shows its screen on the 4.3" 480 x 272 LCD, and is driven by
commands typed on the USB serial line.

Part A runs the demo from the ready-made files (no Gowin build needed). Part B rebuilds everything from the
sources. Part C lists the problems seen so far and their fixes.

## What the demo shows

1. The board's monitor (`r5>`) in a terminal on the PC.
2. `o`: Oberon boots from the SD card. The LCD shows Oberon's screen: an empty user track on the left, the
   System.Log and System.Tool viewers on the right. The terminal shows `OR>`, Oberon's command line.
3. `ORP.Compile Hello.Mod/s`, `Hello.Run`: Oberon's compiler compiles a program on the FPGA; it prints
   `1+..+100 = 5050` (in the terminal and in System.Log on the LCD).
4. `Hilbert.Draw`, `Sierpinski.Draw`, `Checkers.Open`, `Stars.Open` + `Stars.Run`: Oberon's graphics programs
   draw on the LCD (the stars move). `ORP.Compile Mandel.Mod/s`, `Mandel.Draw`: the Mandelbrot set, compiled and
   computed on the FPGA.
5. Files compiled on the board are stored on the SD card and are still there after a power cycle.

Photos of the result: `OBERON_RISC5_LCD_gowin/docs/l2_board_oberon.jpg`, `docs/l3_board_drawings.jpg`.

## Hardware

| item | note |
|---|---|
| Sipeed Tang Nano 9K (GW1NR-9C) | the USB-C port gives power, JTAG and the serial line |
| Sipeed 4.3" RGB LCD, 480 x 272, 40-pin FPC | plugs into the board's 40-pin LCD connector |
| microSD card, 512 MB or larger | SDHC cards work; **the data at 256 MB..257 MB of the card is overwritten** |
| USB-C cable (data, not charge-only) | |
| microSD card reader on the PC | optional: without one the board itself writes the card (A5, method 2) |

The design expects the LCD lying with its cable on the board's side ("cable on top"), as in the photos. If the
picture is upside down with your mounting, see C6.

## Contents (repository and package)

```
gardman/
  README.md                    this guide (= OBERON_RISC5_LCD_gowin/DEMO.md)
  prebuilt/r5_tang.fs          FPGA bitstream (built and tested on the board)
  prebuilt/Oberon.dsk          Oberon disk image (1000448 bytes) for the SD card
  prebuilt/prom.mem            the monitor ROM inside that bitstream (needed only to rebuild)
  prebuilt/SHA256SUMS          checksums of the three files
  extras/runlog                optional helper: runs a command and saves its output under logs/
  OBERON_RISC5_LCD_gowin/      the project (RTL, monitor, tools, tests, Gowin build, docs)
  OBERON_RISC5/rtl/            Wirth's unchanged RISC5 Verilog (wirth/, license.txt) and the UART/ROM ports
  tools/r5/                    the RISC5 assembler (Python)
```

The project uses `../OBERON_RISC5` and `../tools/r5` by relative paths: keep this layout.

---

## Part A: run the demo

### A1. PC software

Used on Ubuntu 24.04 (other recent Linux distributions with the same packages should work).

```
sudo apt install python3 python3-serial putty
```

For programming the FPGA, one of:

- **Gowin Programmer** (part of the Gowin IDE / Gowin Programmer download from gowinsemi.com), or
- **openFPGALoader** (`sudo apt install openfpgaloader`; supports the Tang Nano 9K with `-b tangnano9k`).

The project's scripts expect Gowin under `/tools/Gowin`. If it is installed elsewhere, make a link once:

```
sudo mkdir -p /tools && sudo ln -s /path/to/your/Gowin /tools/Gowin
ls /tools/Gowin/Programmer/bin/programmer_cli      # must exist
```

### A2. Get the files and check them

From the public GitHub repository https://github.com/Tigranman12/oberon-risc5-lcd-gowin (no login needed; the
folder name `gardman` keeps the paths of this guide):

```
mkdir -p ~/oberon && cd ~/oberon
git clone https://github.com/Tigranman12/oberon-risc5-lcd-gowin.git gardman
cd gardman
sha256sum -c prebuilt/SHA256SUMS                    # three lines "OK"
```

Or from the tar.gz package:

```
mkdir -p ~/oberon && cd ~/oberon
tar xzf OBERON_RISC5_LCD_gowin-*.tar.gz
cd gardman
sha256sum -c prebuilt/SHA256SUMS                    # three lines "OK"
```

### A3. USB permissions (once per PC)

The board's USB chip (FTDI FT2232, ID 0403:6010) has two channels: channel A = JTAG (programming), channel B =
the serial line. Your user needs access to both:

```
sudo usermod -aG dialout,plugdev $USER
echo 'SUBSYSTEM=="usb", ATTRS{idVendor}=="0403", ATTRS{idProduct}=="6010", MODE="0666", GROUP="plugdev"' \
  | sudo tee /etc/udev/rules.d/99-gowin-ftdi.rules
sudo udevadm control --reload-rules
```

Log out and in again (for the new groups).

### A4. Connect the board

1. With the USB cable **unplugged**, open the latch of the board's 40-pin LCD connector, insert the LCD's
   ribbon (contacts as Sipeed's LCD examples show), close the latch.
2. Insert the microSD card (after A5, or now if the board writes it, method 2).
3. Plug in the USB cable. Two serial ports appear:

```
ls /dev/ttyUSB*            # e.g. /dev/ttyUSB0 (channel A, JTAG) and /dev/ttyUSB1 (channel B, serial)
```

If other USB-serial devices are connected, the numbers differ: the board's serial line is the second of its
pair. All scripts take `--port /dev/ttyUSBn`.

### A5. Put the Oberon disk on the SD card

The boot monitor reads the Oberon disk from absolute block 80002H (524290) of the card; the card's own
partitions and files are ignored, but whatever lies at 256 MB..257 MB is overwritten.

**Method 1: card reader on the PC (fast).**

```
lsblk -o NAME,SIZE,MODEL,TRAN               # find the card, e.g. /dev/sdb or /dev/mmcblk0 (check the SIZE!)
sudo dd if=prebuilt/Oberon.dsk of=/dev/sdX bs=512 seek=524290 conv=fsync status=progress
sync
```

Replace `/dev/sdX` with the card (the whole device, not a partition such as `/dev/sdb1`). A wrong device name
destroys that disk. Then put the card into the board.

**Method 2: the board writes the card (no card reader, about 3.5 minutes).** First program the FPGA (A6), then:

```
cd OBERON_RISC5_LCD_gowin
python3 tools/sdwrite.py ../prebuilt/Oberon.dsk          # --port /dev/ttyUSBn if not ttyUSB1
```

Expected: progress lines up to `1954/1954 blocks`, then `ok` and
`sdwrite: blocks 80002..807A3 written and read back`. Every block is read back and compared by the board. If it
stops with an error, it prints `go on with --skip K`: run the same command with that option. A card that accepts
writes but does not keep them makes this fail at the first block: use another card.

### A6. Program the FPGA

The bitstream is loaded into the FPGA's SRAM: it is lost at power-off and must be loaded again after every
power-up (or written to the flash once, A9).

**With Gowin's programmer_cli.** Linux's serial driver holds channel A after every plug-in; release it first:

```
ls /sys/bus/usb/drivers/ftdi_sio/                    # e.g. 3-2:1.0 and 3-2:1.1: take the name ending in :1.0
echo -n "3-2:1.0" | sudo tee /sys/bus/usb/drivers/ftdi_sio/unbind
ls /dev/ttyUSB*                                      # now only the serial line is left, e.g. /dev/ttyUSB1
/tools/Gowin/Programmer/bin/programmer_cli --device GW1NR-9C --run 2 --frequency 1MHz \
    --fsFile "$PWD/prebuilt/r5_tang.fs"
```

Expected: `Finished.`. The port name (`3-2`) changes with the USB socket used.

**With openFPGALoader** (it releases the JTAG channel itself):

```
openFPGALoader -b tangnano9k prebuilt/r5_tang.fs
```

### A7. Boot Oberon

Open a terminal on the serial line (115200 baud, 8N1):

```
sg dialout -c "putty -serial /dev/ttyUSB1 -sercfg 115200,8,n,1,N -fn 'client:Monospace 12'"
```

(or `picocom -b 115200 /dev/ttyUSB1`, exit with Ctrl-A Ctrl-X). Press Enter: the monitor answers `r5> `.

```
r5> ?                     the monitor's commands
r5> b 1000000             speed test: 7975FD8D in about 592 ms
r5> o                     boot Oberon from the SD card
oberon 000092C0

Oberon V5  NW 14.4.2013
Oberon TTY (OBERON_RISC5_FAST)
OR>
```

The LCD now shows Oberon's screen. (`OBERON_RISC5_FAST` in the banner is the name of the project the disk image
was made in.)

### A8. Demo commands (type them at `OR>`)

| command | result |
|---|---|
| `System.Directory *.Mod` | the Oberon sources on the card (47 modules) |
| `ORP.Compile Hello.Mod/s` | `compiling Hello ...`: the compiler runs on the FPGA, writes Hello.rsc to the card |
| `Hello.Run` | `Hello from Oberon on the Tang Nano 9K, 1+..+100 = 5050` (also in System.Log on the LCD) |
| `Hello.Trap` | `TRAP 1 in Hello`: a crash; Oberon survives and prompts `OR>` again |
| `Nope.Run` | `call error 1`: unknown module |
| `System.ShowModules` | the modules loaded in memory |
| `Hilbert.Draw` | a Hilbert curve in a new viewer on the LCD |
| `Sierpinski.Draw` | a Sierpinski curve |
| `Checkers.Open` | a checkerboard |
| `Stars.Open` then `Stars.Run` | moving stars; `Stars.Stop` stops them |
| `ORP.Compile Mandel.Mod/s` then `Mandel.Draw` | the Mandelbrot set, computed with the CPU's floating-point unit (about 5-10 s; the set white, bands around it) |
| `System.Close` | closes the lowest viewer of the left track (see below) |

Each drawing opens a viewer in the left track; the track is shared, so later viewers are smaller.
`System.Close` closes the viewer under Oberon's pointer, which stays in the bottom-left corner (there is no
mouse): so each `System.Close` closes the lowest viewer of the left track; System.Log and System.Tool on the
right are not touched, and an extra `System.Close` on an empty track does nothing. To clear the screen and draw
one full-size curve:

```
Stars.Stop                 (if the stars run)
System.Close               (once per viewer on the left)
Hilbert.Draw
```

Or press S1, Enter, `o`: Oberon starts again with a clean screen (the files on the card stay).

**Power-cycle test.** After `ORP.Compile Hello.Mod/s`, unplug and plug the board, program it again (A6), `o`,
and type `Hello.Run` without compiling: it runs, because Hello.rsc was saved on the SD card.

### A9. Optional: start without the PC (flash)

To keep the bitstream across power cycles, write it to the FPGA's flash once, e.g.
`openFPGALoader -b tangnano9k -f prebuilt/r5_tang.fs`, or in the Gowin Programmer GUI: access mode "Embedded
Flash Mode", operation "embFlash Erase,Program". (Not tested in this project; the SRAM way of A6 is.) A terminal
is still needed to type `o` and the commands.

---

## Part B: build from the sources

### B1. Tools

```
sudo apt install iverilog python3 python3-serial
```

Gowin IDE (Education edition is enough; it supports the GW1NR-9C), linked as `/tools/Gowin` (A1).
The simulations use Gowin's primitive models from `/tools/Gowin/IDE/simlib/gw1n/prim_sim.v`.

### B2. Simulations

```
cd gardman/OBERON_RISC5_LCD_gowin
./run_lcd.sh                    # LCD frame memory + controller alone, both orientations: "LCD TB: 2/2 PASS", seconds
./run_rf.sh                     # the whole board with a terminal model: "RESULT: 49/49", "TB PASS", about 21 minutes
```

`run_rf.sh` also assembles the monitor into `build/prom.mem`, which the Gowin build needs.
With the helper: `../extras/runlog lcd_sim ./run_rf.sh` saves the output under `logs/`.

### B3. Gowin build

```
cd gardman/OBERON_RISC5_LCD_gowin
python3 ../tools/r5/r5asm.py programs/monitor.s -o build/prom.mem --words 1024   # if run_rf.sh was not run
cd gowin
./gw_build.sh                   # about 2-3 minutes
```

Result: `gowin/impl/pnr/r5_tang.fs`. Check:

- no `ERROR` lines in the output;
- `impl/pnr/r5_tang.rpt.txt`: BSRAM 15/26, logic about 4500/8640;
- `impl/pnr/r5_tang_tr_content.html`, "Max Frequency Summary": clk_cpu at least 16.875 MHz (built: 17.2),
  clk27 at least 27, mclk at least 54; "Total Negative Slack": 0 for setup and hold on all clocks.

Program it as in A6 with `--fsFile "$PWD/impl/pnr/r5_tang.fs"`, or with `tools/reprog.sh` (programmer_cli,
after the unbind of A6).

### B4. Test picture without Oberon

```
cd gardman/OBERON_RISC5_LCD_gowin
python3 tools/r5load.py programs/lcdtest.s          # terminal closed; prints "lcd ok"
```

The LCD shows a border, a filled square in the bottom-left corner, a diagonal from it to the upper right and a
small block near the top-right corner. Pixels can also be set by hand at `r5>`: pixel (x, y) is bit x MOD 32 of
the word at 400000H + y * 3CH + (x DIV 32) * 4 (y = 0 is the bottom line), e.g. `w 401FE0 FFFFFFFF` draws a
32-pixel line in the middle of the left edge.

### B5. The Oberon disk image (advanced)

`prebuilt/Oberon.dsk` was made by `tools/mkdisk.sh` with Peter De Wachter's project-norebo (and fonts from his
oberon-risc-emu disk), plus `oberon/TTY.Mod` (compiled into the image), `oberon/Hello.Mod` and `oberon/Mandel.Mod` (sources, compiled
on the board). Rebuilding it needs those two repositories
under `~/workspace/ext/` (see the header of `tools/mkdisk.sh`). `tools/o9emu.sh lcd` runs the image in the
emulator with the board's 480 x 272 screen and checks the TTY session (9/9).

### B6. How it works (short)

| address | what |
|---|---|
| 000000H-3FFFFFH | 4 MB PSRAM (in the GW1NR-9's package) through an 8 KB cache: Oberon's memory |
| 400000H-403FBFH | LCD frame memory: 480 x 272 pixels, 1 bit each, in 8 block RAMs (`rtl/r5_lcd.v`) |
| 0E7F00H | the monitor writes 53697A67H, 480, 272, 400000H here before starting Oberon; Oberon's Display module reads them and draws into the frame memory |
| FFE000H | the boot ROM with the monitor (`programs/monitor.s`) |
| FFFFC0H | I/O: timer, LEDs, serial line, SPI (SD card) |

The CPU runs at 16.875 MHz (PLL), the LCD at 27 MHz / 3 = 9 MHz per pixel, the PSRAM controller at 54 MHz.
Design notes: `PLAN.md`; stage results with evidence: `TASK.md`; article: `ARTICLE.md`.

---

## Part C: problems and fixes

| # | symptom | fix |
|---|---|---|
| C1 | programmer_cli: `Cable failed to open via the channel` | release channel A (A6, `unbind`); the port name changes after every plug-in |
| C2 | `no 'r5> ' prompt from the board` | program the FPGA (A6), then run the command again; leftover bytes on the line can swallow the first Enter. Still nothing: press S1 (reset button) and retry |
| C3 | `the monitor did not take 'l'` | same as C2: run it again |
| C4 | PuTTY quits: `unable to load font "server:fixed"` | add `-fn 'client:Monospace 12'` (A7) |
| C5 | `o` prints `no boot image` or `sd err` | the disk is not at block 80002H (A5), or the card is not seated; `r5load.py programs/sdtest.s` checks the card (ends with `sd ok`) |
| C6 | the LCD picture is upside down | the panel is mounted the other way: set `ROT180 = 0` in `rtl/r5_lcd.v` (parameter) and rebuild (B3) |
| C7 | scripts or PuTTY cannot open `/dev/ttyUSB1` | permissions (A3), another program holds the port (close PuTTY before running the Python tools), or a different port number (`--port`) |
| C8 | LCD stays dark / random dots after programming | normal before a program draws; run B4 or `o` |
