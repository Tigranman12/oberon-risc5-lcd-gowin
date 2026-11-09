MODULE TTY; (*OBERON_RISC5_FAST O9: Oberon's command line on the RS232 line, prompt OR>*)
(*A task reads a line from the RS232 (echo, backspace), runs its first name as a command (Oberon.Call, the rest
  of the line = the parameters, as a click on the name in a text would) and sends to the RS232:
  - what was appended to Oberon.Log (since the last time),
  - the text of each viewer the command opened (System.Directory, System.ShowModules, Edit.Open ...); the
    viewer is closed then (no one sees the screen).
  A trap in a command: System.Trap writes it to the Log and calls Oberon.Reset, which removes the task that ran
  (this one); a second task (guard) installs it again (Install does nothing while it is installed).
  Loaded by Oberon.Mod after System (mkdisk.sh adds Modules.Load("TTY", Mod)).*)
  IMPORT SYSTEM, Display, Viewers, Texts, Oberon, TextFrames, RS232, System;

  CONST stat = -52; data = -56; MaxLine = 128; MaxV = 64;

  VAR line: ARRAY MaxLine OF CHAR; n: INTEGER;
    logPos: INTEGER; busy: BOOLEAN;
    W: Texts.Writer; F: Display.Frame;
    repl, guard: Oberon.Task;
    old: ARRAY MaxV OF Viewers.Viewer; nold: INTEGER;

  PROCEDURE Ch(ch: CHAR);
  BEGIN
    IF ch = 0DX THEN RS232.Send(0DH); RS232.Send(0AH)
    ELSIF (ch >= " ") & (ch < 7FX) OR (ch = 9X) THEN RS232.Send(ORD(ch))
    END
  END Ch;

  PROCEDURE Str(s: ARRAY OF CHAR);
    VAR i: INTEGER;
  BEGIN i := 0;
    WHILE (i < LEN(s)) & (s[i] # 0X) DO Ch(s[i]); INC(i) END
  END Str;

  PROCEDURE Int(x: INTEGER);
  BEGIN
    IF x < 0 THEN Ch("-"); x := -x END ;
    IF x >= 10 THEN Int(x DIV 10) END ;
    Ch(CHR(x MOD 10 + 30H))
  END Int;

  PROCEDURE SendText(t: Texts.Text; beg: INTEGER);
    VAR R: Texts.Reader; ch: CHAR; i: INTEGER;
  BEGIN Texts.OpenReader(R, t, beg); i := beg;
    WHILE i < t.len DO Texts.Read(R, ch); Ch(ch); INC(i) END
  END SendText;

  PROCEDURE FlushLog;
  BEGIN
    IF Oberon.Log # NIL THEN
      IF Oberon.Log.len < logPos THEN logPos := 0 END ;   (*System.Clear*)
      IF Oberon.Log.len > logPos THEN SendText(Oberon.Log, logPos); logPos := Oberon.Log.len END
    END
  END FlushLog;

  PROCEDURE Collect(VAR a: ARRAY OF Viewers.Viewer; VAR k: INTEGER);   (*all viewers, track by track*)
    VAR x, j: INTEGER; V, V0: Viewers.Viewer;
  BEGIN k := 0; x := 0;
    WHILE x < Display.Width DO
      V0 := Viewers.This(x, 0); V := V0; j := 0;
      REPEAT
        IF k < LEN(a) THEN a[k] := V; INC(k) END ;
        V := Viewers.Next(V); INC(j)
      UNTIL (V = V0) OR (j > 100);
      IF V0.W > 0 THEN x := V0.X + V0.W ELSE x := Display.Width END
    END
  END Collect;

  PROCEDURE ShowNew;   (*send the text of the viewers that are not in old, and close them*)
    VAR new: ARRAY MaxV OF Viewers.Viewer; k, i, j: INTEGER; V: Viewers.Viewer; seen: BOOLEAN;
  BEGIN Collect(new, k);
    FOR i := 0 TO k-1 DO
      V := new[i]; seen := FALSE;
      FOR j := 0 TO nold-1 DO IF old[j] = V THEN seen := TRUE END END ;
      IF ~seen & (V.dsc # NIL) & (V.dsc.next # NIL) & (V.dsc.next IS TextFrames.Frame) THEN
        SendText(V.dsc.next(TextFrames.Frame).text, 0); Viewers.Close(V)
      END
    END ;
    nold := 0
  END ShowNew;

  PROCEDURE Exec;
    VAR T: Texts.Text; S: Texts.Scanner; res: INTEGER;
  BEGIN T := TextFrames.Text("");
    Texts.WriteString(W, line); Texts.WriteLn(W); Texts.Append(T, W.buf);
    Texts.OpenScanner(S, T, 0); Texts.Scan(S);
    IF S.class = Texts.Name THEN
      Collect(old, nold); busy := TRUE;
      Oberon.SetPar(F, T, S.len); Oberon.Call(S.s, res);
      busy := FALSE; FlushLog; ShowNew;
      IF res # 0 THEN Str("call error "); Int(res); Str(" ("); Str(S.s); Ch(")"); Ch(0DX) END
    ELSE Str("? M.P [params]"); Ch(0DX)
    END
  END Exec;

  PROCEDURE Poll;
    VAR ch: CHAR; x: INTEGER;
  BEGIN
    IF busy THEN (*the last command trapped*) busy := FALSE; FlushLog; ShowNew; Str("OR> ") END ;
    FlushLog;
    WHILE SYSTEM.BIT(stat, 0) DO
      RS232.Rec(x); ch := CHR(x MOD 100H);
      IF ch = 0DX THEN
        Ch(0DX);
        IF n > 0 THEN line[n] := 0X; n := 0; Exec END ;
        Str("OR> ")
      ELSIF (ch = 8X) OR (ch = 7FX) THEN
        IF n > 0 THEN DEC(n); RS232.Send(8); RS232.Send(20H); RS232.Send(8) END
      ELSIF (ch >= " ") & (ch < 7FX) & (n < MaxLine-1) THEN line[n] := ch; INC(n); RS232.Send(x MOD 100H)
      END
    END
  END Poll;

  PROCEDURE Guard;
  BEGIN Oberon.Install(repl)
  END Guard;

BEGIN Texts.OpenWriter(W); NEW(F); F.X := 0; F.Y := 0; F.W := 1; F.H := 1;
  n := 0; nold := 0; busy := FALSE; logPos := 0;
  repl := Oberon.NewTask(Poll, 0); guard := Oberon.NewTask(Guard, 500);
  Oberon.Install(repl); Oberon.Install(guard);
  Ch(0DX); FlushLog; Str("Oberon TTY (OBERON_RISC5_FAST)"); Ch(0DX); Str("OR> ")
END TTY.
