#!/usr/bin/env python3
"""r5meta.py - the RISC5 assembler written in META II (tools/r5/r5asm.meta), with a small Python back end.

How it works (the classic META II split: the grammar reads and translates, the target does the rest):
  1. META II (tools/r5/meta2.py, which compiles itself from tools/r5/meta2.meta) compiles the grammar
     tools/r5/r5asm.meta into order codes.
  2. Those order codes read the assembly program and write it out as a short Python program: one call
     per line, e.g.  OP("ADD") REG(3) REG(3) NUM(1)  or  LBL("loop")  or  PUTS('text').
     ';' comments and 0x numbers are META II extensions switched on here (meta2.py: comment, hexnum).
  3. This file runs that Python program: it collects the instructions, then gives every instruction
     its address (pass 1) and its 32-bit code (pass 2). The bit formats are those of tools/r5/r5asm.py
     (encode()), so both assemblers make the same ROM; tests/run_all.sh compares them.
META II has no arithmetic, so addresses and bit fields cannot be computed in the grammar itself.

Syntax: as tools/r5/r5asm.py, with two limits of META II: strings use single quotes ('text', no ' inside),
and labels must not start like a mnemonic (use lower case: loop, putc). No .equ.

Usage: r5meta.py prog.s -o prom.mem [--py prog.py] [--trace] [--words 512]
"""
import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import meta2   # noqa: E402
import r5asm   # noqa: E402

GRAMMAR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "r5asm.meta")


def translate(src_text, trace=None):
    """Assembly -> the Python program written by the META II grammar (a list of lines)."""
    codes = meta2.compile_grammar(open(GRAMMAR).read())
    return meta2.run(codes, src_text, comment=";", hexnum=True, trace=trace)


def collect(py_lines):
    """Run the translated program; returns items: ("LABEL", name) / ("PUTS", text) / (mnemonic, [operands])."""
    items = []

    def op(mn):
        items.append((mn, []))

    def operand(s):
        if not items or items[-1][0] in ("LABEL", "PUTS"):
            raise r5asm.AsmError("operand without an instruction")
        items[-1][1].append(s)

    env = {
        "__builtins__": {},
        "OP": op,
        "REG": lambda n: operand("R%d" % n),
        "NUM": lambda v: operand(str(v)),
        "CHR": lambda c: operand(str(ord(c))),
        "LAB": lambda name: operand(name),
        "LBL": lambda name: items.append(("LABEL", name)),
        "PUTS": lambda text: items.append(("PUTS", text)),
        "END": lambda: None,
    }
    exec("\n".join(line.strip() for line in py_lines), env)
    return items


def assemble(items):
    expanded = []                             # PUTS -> MOV R1, char / BL putc (as r5asm.py)
    for mn, ops in items:
        if mn == "PUTS":
            for ch in ops:
                expanded.append(("MOV", ["R1", str(ord(ch))]))
                expanded.append(("BL", ["putc"]))
        else:
            expanded.append((mn, ops))
    labels, pc = {}, 0                        # pass 1: addresses
    for mn, ops in expanded:
        if mn == "LABEL":
            labels[ops] = pc
        else:
            pc += 1
    words, lst, pc = [], [], 0                # pass 2: codes
    for mn, ops in expanded:
        if mn == "LABEL":
            continue
        w = r5asm.encode(mn, ops, pc, labels, {})
        words.append(w)
        lst.append("%03X  %08X  %s %s" % (pc, w, mn, ", ".join(ops)))
        pc += 1
    return words, lst


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("src")
    ap.add_argument("-o", "--out", required=True)
    ap.add_argument("--py", help="also save the Python program written by the grammar")
    ap.add_argument("--words", type=int, default=512)
    ap.add_argument("--trace", action="store_true", help="META II rule trace (to stderr)")
    a = ap.parse_args()
    try:
        py_lines = translate(open(a.src).read(), trace=sys.stderr if a.trace else None)
        if a.py:
            open(a.py, "w").write("\n".join(py_lines) + "\n")
        words, lst = assemble(collect(py_lines))
    except (meta2.MetaError, r5asm.AsmError, ValueError, KeyError) as e:
        sys.exit("r5meta: %s" % e)
    r5asm.write_rom(words, lst, a.out, a.words, "r5meta: " + a.src)


if __name__ == "__main__":
    main()
