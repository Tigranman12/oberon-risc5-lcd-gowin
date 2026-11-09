# PLAN: OBERON_RISC5_LCD_gowin

User (2026-11-09): "B, 4.3 inch 480x272, but a separate project": Oberon's real screen on the LCD (option B of
three: A = TTY text on the LCD, B = Oberon's 1-bit screen at 480 x 272, C = Wirth's 1024 x 768 desktop from the
PSRAM with mouse and keyboard). Base: OBERON_RISC5_FAST at e2a4770 (Oberon V5 + TTY boots from the SD card).

## 1. Result wanted
Oberon draws on the 4.3" LCD: after `o` the panel shows Oberon's viewers (System.Log, System.Tool), and
commands typed at OR> (e.g. `Hilbert.Draw`) draw on it. The CPU keeps its 16.875 MHz with 0 timing violations.

## 2. Design (recorded 2026-11-09, user: "ok" to "record it")
- L-D1 Panel: Sipeed 4.3" 480 x 272 RGB, pins and timing as `../G9_FTL_ARCH_V3/gowin/g9v3.cst` and
  `../G8ARCH/rtl/g8_video.v` (27 MHz / 3 = 9 MHz pixel clock; H 30 + 480 + 50 = 560, V 5 + 272 + 20 = 297,
  about 54 Hz). No pin is shared with the SD card (36-39), UART (17, 18), LEDs (10-16) or S1 (4).
- L-D2 Frame memory: 480 x 272 x 1 bit = 16320 bytes in 8 BSRAM (block RAM in the FPGA), dual clock: the CPU port
  at the CPU clock (word loads and stores, one wait clock like the cache), the LCD port at 27 MHz. BSRAM in use:
  17 + 8 = 25 of 26.
- L-D3 Address: 400000H-403FBFH (unused since O6 moved the PSRAM to 0-3FFFFFH), so the cache path does not change:
  fsel = adr[23:14] = 100H.
- L-D4 Pixel layout as Wirth's Display.Mod: pixel (x, y) is bit x MOD 32 of the word at
  Base + y * Span + (x DIV 32) * 4, Span = 60 bytes; y = 0 is the bottom line, so LCD line l shows y = 271 - l.
  Bit 1 = white (Display.white), 0 = black.
  Panel orientation (L1 board, 2026-11-09): the panel lies with its cable on top, where its scan starts at the
  bottom-right corner; r5_lcd's ROT180 = 1 (default) turns the picture: panel line l shows y = l, scan position
  p shows x = 479 - p (ROT180 = 0: the panel turned, cable at the bottom).
- L-D5 Oberon unchanged: the Display.Mod on the disk (Peter De Wachter's, for the emulator) reads a magic word
  at 0E7F00H; with 53697A67H it takes Width, Height and Base from the next words (Span = Width DIV 8). Monitor
  `o` writes 53697A67H, 480, 272, 400000H at 0E7F00H-0E7F0FH before it jumps to Oberon.
- L-D6 TTY.Mod closes the viewers a command opens (O9). For drawings they must stay on the screen: an option
  in TTY (to decide in L3).

## 3. Stages (one branch each, tag `<stage>-pass` with evidence)
| stage | what | evidence |
|---|---|---|
| L0 | the copy: same tests as OBERON_RISC5_FAST, nothing new | `run_rf.sh` TB PASS in the new folder |
| L1 | LCD controller + frame memory at 400000H; monitor writes a test picture (`f`/`w`) | sim: the LCD pixel stream for a known picture; build: Fmax, 0 violations, BSRAM 25/26; board: the picture on the panel |
| L2 | Oberon's screen: monitor `o` writes the magic words | emulator at 480 x 272 (screen to PBM): viewers drawn; board: Oberon's viewers on the panel |
| L3 | drawing from the TTY: Hilbert.Draw, Sierpinski.Draw stay on the screen | emulator PBM; board photo / user's check |

## 4. Open questions
1. 25 of 26 BSRAM: if the build does not fit or place, the cache gives up blocks (8 KB -> 4 KB).
2. How Oberon lays out its tracks at 480 x 272 (System.Open, fonts 12 px): to see in the emulator in L2.
3. Colours: white on black for now (no choice given); green / amber later = two colour constants.

## 8. Decisions log
- 2026-11-09: project created as a copy of OBERON_RISC5_FAST (e2a4770); name OBERON_RISC5_LCD_gowin (user).
- 2026-11-09: option B, 4.3" 480 x 272 LCD (user).
- 2026-11-09: design L-D1..L-D6 recorded (user "ok"); colours white on black.
- 2026-11-09: L1 board: picture correct but turned 180 degrees as the panel lies; user: "A" -> ROT180 in r5_lcd.
