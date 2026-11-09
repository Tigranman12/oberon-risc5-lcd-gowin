# INFO: OBERON_RISC5_LCD_gowin, the user's directions (dated, newest last)

- 2026-11-09: after Oberon booted from the SD card in OBERON_RISC5_FAST: "I want next example something with
  lcd, will it possible". Options A (text), B (Oberon's screen at 480 x 272), C (full desktop) shown; user: "B,
  4.3 inch 480x272 but separate project like oberon_LCD or something meaningful", then "also gowin add in name"
  -> folder OBERON_RISC5_LCD_gowin (confirmed by the user), copy of OBERON_RISC5_FAST at e2a4770.
  This lifts OBERON_RISC5_FAST's "no LCD, TTY only" (its PLAN.md) for this project only.
- 2026-11-09: L0 sim passed (42/42). User asked how to demo the LCD project (not possible before L1); then "ok" to
  "record it" for PLAN.md section 2 -> design recorded, colour not chosen -> white on black. Start L1.
- 2026-11-09: L1 on the board (photo docs/l1_board_lcdtest.jpg): test picture right but turned 180 degrees with the
  cable on top. User asked how to use it and what it will demo; then "A, then go to L2" -> rotate in hardware
  (r5_lcd ROT180), then L2 (Oberon's screen on the panel).
- 2026-11-09: L3 drawings on the board (photo). User: "save this in remote private git and create from this project
  tar.gz, I want to run this project in other pc with same board, create also readme and steps how to build and
  run this demo with detailed steps" -> DEMO.md (setup, SD card, programming, demo, rebuild, problems); package
  ~/workspace/GARDMAN/dist/OBERON_RISC5_LCD_gowin-20261109-f40b859.tar.gz (not in git: the project, Wirth's RTL,
  tools/r5, prebuilt r5_tang.fs / Oberon.dsk / prom.mem with SHA256SUMS, extras/runlog; README.md = DEMO.md);
  tested from a fresh unpack. Push to origin: by the user (AGENTS.md).
- 2026-11-09: user: "is fractal here exists" -> "yes do it" -> oberon/Mandel.Mod (Mandel.Draw: the Mandelbrot set,
  compiled and computed on the board), on the disk image as a source; emulator-verified (docs/mandel_emu_lcd.png).
- 2026-11-09: user: "create public link for this project, I will give other Claude remote control to do it on same
  other gowin" -> the standalone repo becomes PUBLIC: https://github.com/Tigranman12/oberon-risc5-lcd-gowin
  (DEMO.md A2: plain git clone, no login). Creating and pushing it: by the user (AGENTS.md).
