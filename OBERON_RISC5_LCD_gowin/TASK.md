# TASK: OBERON_RISC5_LCD_gowin

## State
- L0 (branch lcd-l0): copy of OBERON_RISC5_FAST at e2a4770 (48 tracked files; only the build banner, the
  .gitignore comment and the usage line of gw_build.sh renamed; file headers keep their OBERON_RISC5_FAST
  history). Sim logs/20261109-204416-lcd_sim at 8726926: tb_mon RESULT 42/42, TB PASS, PSRAM TB 6/6, exit 0
  (about 21 min). Done: tag lcd-l0-pass.
- Design L-D1..L-D6 in PLAN.md: recorded 2026-11-09.
- L1 (branch lcd-l1): rtl/r5_lcd.v = frame memory (4 byte-wide memories, 4096 words; CPU port at the CPU clock,
  LCD port at 27 MHz) + LCD timing of G8ARCH's g8_video.v; r5_tang: fsel 400000H-403FFFH (loads: the one
  wait clock of stallX = ldw & ~ws; stores in their own clock, lanes as the cache's); r5_board: lclk = the
  crystal, LCD pins; r5.cst: the 20 LCD pins of G9_FTL_ARCH_V3; build.tcl: r5_lcd.v, use_mspi/sspi_as_gpio;
  r5.sdc: clk_cpu / clk27 asynchronous. programs/lcdtest.s: border, 32 x 32 square at (0, 0) = bottom-left,
  diagonal x = y, 8 x 8 STB block at x 440..447, y 256..263.
  Sim (agent): ./run_lcd.sh 7/7 TB PASS (3 s): 4080 words read back, byte lanes, one frame = 272 x 480 pixels,
  every pixel = Display.Mod's bit, 560 x 297 clocks, 297 hsync. The test fails as it should with the y flip
  removed and with the bit order reversed (6/7 each). tb_mon (+7 checks: w/d at 400000H, lcdtest.s, its
  words, from a Python model of lcdtest.s) compiles; the run is the user's (about 21 min).
  First build: PA2122, the DPB has no read-before-write (logs/20261109-211631-lcd_gowin) -> CPU port in normal
  mode (d8f6384). Build logs/20261109-211846-lcd_gowin at d8f6384: 0 ERROR; Fmax clk_cpu 17.697 MHz (16.875),
  clk27 65.7, mclk 71.3; TNS 0 setup and hold on all clocks; BSRAM 15/26 (8 DPB = the frame memory, 5 SDPB +
  2 others = the cache); logic 4622/8640.
  Board logs/20261109-213535-lcd_test: r5load lcdtest.s sum 57234FAA OK, 'lcd ok'. The panel (photo
  docs/l1_board_lcdtest.jpg) shows border, 32 x 32 square, diagonal, 8 x 8 STB block, all where Display.Mod's
  layout puts them, but turned 180 degrees with the panel's cable on top (as the user lays it): the panel scans
  from that corner. User: "A" = rotate in hardware.
- L1r (branch lcd-l1r): r5_lcd parameter ROT180 = 1: panel line l = y l, scan position p = x 479 - p.
  run_lcd.sh runs both orientations: 2 x 7/7; with the test expecting ROT180 but the hardware at 0: 6/7 FAIL.
  Needs: Gowin build, board lcdtest (square at the bottom-left with the cable on top), run_rf.sh 49/49.
- L2 (branch lcd-l2, from lcd-l1r): monitor cogo (o and r) writes 53697A67H, 480, 272, 400000H at 0E7F00H before
  B 0 (ROM 959 of 1024 words); coretest.s prints those 4 words, tb_mon expects them (o check).
  Emulator (agent): headless LCD=1 = risc_configure_memory(4 MB, 480, 272): the same magic words with the screen
  at 400000H, MemLim / stackOrg patched back to the board's 0E7EF0H / 80000H. tools/o9emu.sh lcd: 9/9 PASS
  (boot, TTY, compile, Hello.Run, trap, ...); tools/o9emu.sh (1024 x 768): 9/9. Screen at the end
  (docs/l2_emu_lcd.png, 1 = black there): user track 300 px empty, system track 180 px with System.Log
  (Oberon V5, the compile, Hello's line) and System.Tool.
  Build logs/20261109-214359-lcd_gowin at 3b79ed0: 0 ERROR; Fmax clk_cpu 17.213 MHz (16.875: 2 % margin), clk27
  62.2, mclk 70.0; TNS 0 on all clocks; BSRAM 15/26, logic 4529/8640. Board: logs/20261109-214533-lcd_test
  'lcd ok', the picture now right with the cable on top (user: "it 180 changed"). Monitor o (PuTTY), then
  ORP.Compile Hello.Mod/s, Hello.Run: the panel (photo docs/l2_board_oberon.jpg) shows Oberon's screen as the
  emulator's: user track empty with the arrow, System.Log with Oberon V5, OR Compiler, compiling Hello 67 40
  C43B, Hello's line; System.Tool.
  Sim logs/20261109-215355-lcd_sim at 518a9ac (L1 + L1r + L2; RTL and monitor as built): tb_mon RESULT 49/49,
  TB PASS, PSRAM TB 6/6, exit 0. (The run before, logs/20261109-211954-lcd_sim at d8f6384, failed 48/49 only because
  the agent rewrote build/core_sum.hex during the run; its 7 L1 checks passed.) Tags lcd-l1-pass, lcd-l2-pass.
- L3 look (emulator LCD=1, no change): TTY.Mod closes only text viewers (TTY.Mod:73), so graphic viewers stay.
  Hilbert.Draw (docs/l3_emu_hilbert.png); Hilbert.Draw, Sierpinski.Draw, Checkers.Open stack in the user track
  (docs/l3_emu_three.png); Stars.Open, Stars.Run animate (docs/l3_emu_stars.png). Graphic viewers cannot be closed
  from the TTY? Emulator: System.Close closes the viewer under Oberon's pointer, which stays at (0, 0) without a
  mouse = the lowest viewer of the user track; 4 x System.Close after 4 viewers (Stars running) leave the track
  empty, Hilbert.Draw is then full size; an extra System.Close on the empty track does nothing; System.CloseTrack
  does nothing (the base track). So TTY.Clear (proposed) is not needed: dropped.
  Board (PuTTY after o, photo docs/l3_board_drawings.jpg, taken turned 90 degrees): Hilbert.Draw, Stars.Open +
  Stars.Run, Sierpinski.Draw, Checkers.Open: four viewers stacked in the user track as in the emulator, System.Log
  and System.Tool in the system track. L3's goal (drawings typed at the TTY on the panel) reached without a change.
## Next
1. Evidence for L1r + L2 (one Gowin build, one run_rf.sh): run_rf.sh 49/49; build: Fmax, 0 violations;
   board: lcdtest.s (square at the bottom-left with the cable on top), then o: Oberon's screen on the panel.
2. L3: drawings from the TTY (Hilbert.Draw, Sierpinski.Draw) staying on the screen (TTY closes viewers, L-D6).
