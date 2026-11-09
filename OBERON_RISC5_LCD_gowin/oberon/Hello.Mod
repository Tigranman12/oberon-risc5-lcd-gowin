MODULE Hello; (*OBERON_RISC5_FAST O9: compiled on the board with ORP.Compile Hello.Mod/s, then Hello.Run; Hello.Trap traps*)
  IMPORT Texts, Oberon;
  VAR W: Texts.Writer;

  PROCEDURE Run*;
    VAR i, s: INTEGER;
  BEGIN s := 0;
    FOR i := 1 TO 100 DO s := s + i END ;
    Texts.WriteString(W, "Hello from Oberon on the Tang Nano 9K, 1+..+100 = "); Texts.WriteInt(W, s, 1);
    Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
  END Run;

  PROCEDURE Trap*;   (*index out of range: TTY must come back with OR>*)
    VAR a: ARRAY 4 OF INTEGER; i: INTEGER;
  BEGIN i := 4; a[i] := 1
  END Trap;

BEGIN Texts.OpenWriter(W)
END Hello.
