# Project Oberon's screen on a 480 x 272 LCD from a small FPGA

Project: `OBERON_RISC5_LCD_gowin/` in the gardman repo. Board: Tang Nano 9K (GW1NR-9) with the Sipeed 4.3"
480 x 272 RGB LCD. Predecessor: `OBERON_RISC5_FAST` (RISC5F, Oberon V5 booted from the SD card).

## Summary
Wirth's Project Oberon draws on a 1-bit frame buffer of 1024 x 768 pixels. This project gives it a 480 x 272
frame buffer in the FPGA's block RAM, read by an LCD controller, and tells Oberon the new size through the
magic words that Display.Mod already reads, so no Oberon module changes.

## 1. Question
Can the unchanged Oberon V5 system show its screen on a small LCD, with the frame buffer in on-chip memory
next to an 8 KB cache, without lowering the CPU clock?

## 2. Method
A frame memory of 16320 bytes (8 BSRAM) at 400000H, outside the cached PSRAM range; one port for the CPU, one
for the LCD controller at 9 MHz pixels. Pixel layout as Display.Mod: bit x MOD 32 of word
Base + y * 60 + (x DIV 32) * 4, y = 0 at the bottom. The boot monitor writes 53697A67H, 480, 272, 400000H at
0E7F00H; Display.InitResolution takes Width, Height and Base from there.

## 3. Expected results
- The CPU stays at 16.875 MHz with 0 setup/hold violations; 25 of 26 BSRAM.
- After boot the panel shows Oberon's viewers; drawing commands typed at the TTY draw on the panel.

## 4. How the tests prove them
- Simulation: a test picture written by the monitor appears in the LCD pixel stream at the right places.
- Emulator: Oberon at 480 x 272 (screen saved as PBM) draws its viewers and the curves.
- Board: the same picture and screens on the panel.

## 5. Results
None yet (stage L0).

## 6. Open questions
See PLAN.md section 4.

## References
N. Wirth, J. Gutknecht: Project Oberon, 2013 edition (Display.Mod, RISC5Top.v). P. De Wachter: oberon-risc-emu and
project-norebo (Display.Mod with the size magic words). Sipeed TangNano-9K-example lcd_4.3 (timing, pins).
