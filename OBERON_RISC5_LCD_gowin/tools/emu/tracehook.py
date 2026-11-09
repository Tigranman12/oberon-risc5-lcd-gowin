#!/usr/bin/env python3
# tracehook.py - OBERON_RISC5_FAST O9r: add a trace hook to a copy of oberon-risc-emu's risc.c: risc_steps counts the
# instructions from the first fetch at address 0 (the inner core's start) on; if risc_trace is set, each one's PC.
import sys
p = sys.argv[1]
t = open(p).read()
o = """  risc->PC++;\n"""
assert t.count(o) == 1
t = t.replace(o, """  if (risc->PC == 0) risc_on = 1;                     /* tracehook.py */
  if (risc_on) { risc_steps++; if (risc_trace) fprintf(risc_trace, "%X\\n", risc->PC * 4);
    if (risc->PC * 4 == risc_stop) fprintf(stderr, "hook: PC %X at step %lld\\n", risc_stop, risc_steps); }
  risc->PC++;\n""")
o = "static void risc_single_step(struct RISC *risc) {\n"
assert t.count(o) == 1
t = t.replace(o, "int risc_on; long long risc_steps; FILE *risc_trace; unsigned risc_stop;     /* tracehook.py */\n" + o, 1)
open(p, "w").write(t)
