MODULE Mandel; (*OBERON_RISC5_LCD_gowin: the Mandelbrot set in a viewer, computed with RISC5's floating-point
  unit. Installed as source: ORP.Compile Mandel.Mod/s, then Mandel.Draw (a new viewer in the user track).
  Pixel (i, j) of the frame is c = (x0 + i*s, y0 + j*s); z := z*z + c from z = 0 up to MaxIt times while |z| < 2.
  White: the points that do not escape (the set), and the points that escape after an odd number of steps
  greater than 2 (bands around the set). The region -2.2 .. 0.8 x -1.2 .. 1.2 fits into the frame.*)
  IMPORT Display, Viewers, Oberon, MenuViewers, TextFrames;

  CONST Menu = "System.Close  System.Copy  System.Grow"; MaxIt = 32;

  PROCEDURE DrawSet(F: Display.Frame);
    VAR i, j, n: INTEGER; s, cx, cy, x, y, xx, yy, x0, y0: REAL;
  BEGIN
    Display.ReplConst(Display.black, F.X, F.Y, F.W, F.H, Display.replace);
    IF F.W * 4 > F.H * 5 THEN s := 2.4 / FLT(F.H) ELSE s := 3.0 / FLT(F.W) END ;
    x0 := -0.7 - FLT(F.W) * s / 2.0; y0 := -FLT(F.H) * s / 2.0;
    FOR j := 0 TO F.H - 1 DO
      cy := y0 + FLT(j) * s;
      FOR i := 0 TO F.W - 1 DO
        cx := x0 + FLT(i) * s; x := 0.0; y := 0.0; xx := 0.0; yy := 0.0; n := 0;
        WHILE (n < MaxIt) & (xx + yy < 4.0) DO
          y := 2.0 * x * y + cy; x := xx - yy + cx; xx := x * x; yy := y * y; INC(n)
        END ;
        IF (n = MaxIt) OR ODD(n) & (n > 2) THEN Display.Dot(Display.white, F.X + i, F.Y + j, Display.replace) END
      END
    END
  END DrawSet;

  PROCEDURE Handler(F: Display.Frame; VAR M: Display.FrameMsg);
    VAR F0: Display.Frame;
  BEGIN
    IF M IS Oberon.InputMsg THEN
      IF M(Oberon.InputMsg).id = Oberon.track THEN
        Oberon.DrawMouseArrow(M(Oberon.InputMsg).X, M(Oberon.InputMsg).Y)
      END
    ELSIF M IS MenuViewers.ModifyMsg THEN
      F.Y := M(MenuViewers.ModifyMsg).Y; F.H := M(MenuViewers.ModifyMsg).H; DrawSet(F)
    ELSIF M IS Oberon.ControlMsg THEN
      IF M(Oberon.ControlMsg).id = Oberon.neutralize THEN Oberon.RemoveMarks(F.X, F.Y, F.W, F.H) END
    ELSIF M IS Oberon.CopyMsg THEN
      NEW(F0); F0^ := F^; M(Oberon.CopyMsg).F := F0
    END
  END Handler;

  PROCEDURE New(): Display.Frame;
    VAR F: Display.Frame;
  BEGIN NEW(F); F.handle := Handler; RETURN F
  END New;

  PROCEDURE Draw*;
    VAR V: Viewers.Viewer; X, Y: INTEGER;
  BEGIN Oberon.AllocateUserViewer(Oberon.Par.vwr.X, X, Y);
    V := MenuViewers.New(TextFrames.NewMenu("Mandelbrot", Menu), New(), TextFrames.menuH, X, Y)
  END Draw;

END Mandel.
