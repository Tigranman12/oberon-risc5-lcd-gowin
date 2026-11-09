#!/usr/bin/env python3
"""r5asm.py - a small assembler for Wirth's RISC5 (Project Oberon 2013), for the test programs of OBERON_RISC5.

Real Oberon code comes from Wirth's compiler (ORP/ORG); this tool only makes small boot-ROM test programs
(PROM: 512 words at FFE000H, the CPU starts there after reset). Instruction formats (PO.Computer.pdf, RISC5.v,
and the emulator's risc.c):
  F0  00uv aaaa bbbb oooo .... .... .... cccc    register op:   OP Ra, Rb, Rc
  F1  01uv aaaa bbbb oooo iiii iiii iiii iiii    immediate op:  OP Ra, Rb, imm  (v = 1: imm sign-extended)
  F2  10uv aaaa bbbb ffff ffff ffff ffff ffff    memory:        LDR/STR Ra, Rb, off (u = store, v = byte)
  F3  11uv cccc .... .... .... .... .... cccc    branch:        B<cond> label | Rc (u = PC-relative, v = link R15)
Ops: MOV LSL ASR ROR AND ANN IOR XOR ADD SUB MUL DIV FAD FSB FML FDV (0..15).

Syntax (one instruction per line, ';' starts a comment, operands separated by commas):
  label:                    MOV Ra, Rc | imm      MOVH Ra, imm (imm << 16)
  ADD Ra, Rb, Rc | imm      (also SUB AND ANN IOR XOR LSL ASR ROR MUL DIV)
  FLT Ra, Rb, Rc    FLR Ra, Rb, Rc   (Rc = 4B000000H: integer -> float, float -> integer, Wirth's FLT/FLOOR)
  GETH Ra           Ra := H (the high word after MUL, the remainder after DIV)
  LDR Ra, Rb, off   LDB   STR   STB
  B label | Rc      BL label | Rc      B<cc> / BL<cc>: cc = MI EQ CS VS LS LT LE, PL NE CC VC HI GE GT
  PUTS "text"       one 'MOV R1, char' + 'BL putc' per character (the program defines putc); \\r \\n allowed;
                    'text' also works (the form tools/r5/r5asm.meta accepts)
  .equ NAME, value
Usage: r5asm.py prog.s -o prom.mem [--words 512]     -> hex words for $readmemh, plus prog.lst
"""
import argparse
import re
import sys

OPS = ["MOV", "LSL", "ASR", "ROR", "AND", "ANN", "IOR", "XOR",
       "ADD", "SUB", "MUL", "DIV", "FAD", "FSB", "FML", "FDV"]
CC = {"MI": 0, "EQ": 1, "CS": 2, "VS": 3, "LS": 4, "LT": 5, "LE": 6, "": 7,
      "PL": 8, "NE": 9, "CC": 10, "VC": 11, "HI": 12, "GE": 13, "GT": 14}


class AsmError(Exception):
    pass


def reg(s):
    m = re.fullmatch(r"R(\d+)", s.strip().upper())
    if not m or int(m.group(1)) > 15:
        raise AsmError("not a register: %r" % s)
    return int(m.group(1))


def is_reg(s):
    return re.fullmatch(r"R\d+", s.strip().upper()) is not None


def split_ops(text):
    return [t.strip() for t in text.split(",")] if text.strip() else []


def strip_comment(line):
    """Remove a ';' comment, but not a ';' inside a "string" or a 'c' character."""
    quote = None
    for i, ch in enumerate(line):
        if quote:
            if ch == "\\":
                continue
            if ch == quote and line[i - 1] != "\\":
                quote = None
        elif ch in "\"'":
            quote = ch
        elif ch == ";":
            return line[:i].rstrip()
    return line.rstrip()


def expand(lines):
    """PUTS macro -> list of (line number, source text, mnemonic, operand text)."""
    out = []
    for n, raw in enumerate(lines, 1):
        line = strip_comment(raw)
        while True:                           # labels
            m = re.match(r"\s*(\w+):(.*)", line)
            if not m:
                break
            out.append((n, raw, "LABEL", m.group(1)))
            line = m.group(2)
        line = line.strip()
        if not line:
            continue
        mn, _, rest = line.partition(" ")
        mn = mn.upper()
        if mn == "PUTS":
            m = re.fullmatch(r'"((?:[^"\\]|\\.)*)"|\'([^\']*)\'', rest.strip())
            if not m:
                raise AsmError("line %d: PUTS needs a string" % n)
            text = (m.group(1) if m.group(1) is not None else m.group(2)).encode().decode("unicode_escape")
            for ch in text:
                out.append((n, "PUTS %r" % ch, "MOV", "R1, %d" % ord(ch)))
                out.append((n, "", "BL", "putc"))
        else:
            out.append((n, raw, mn, rest))
    return out


def value(s, sym):
    s = s.strip()
    if s in sym:
        return sym[s]
    if re.fullmatch(r"'.'", s):
        return ord(s[1])
    return int(s, 0)


def assemble(src):
    items = expand(src.splitlines())
    labels, equ, pc = {}, {}, 0
    for n, raw, mn, rest in items:            # pass 1: addresses
        if mn == "LABEL":
            labels[rest] = pc
        elif mn == ".EQU":
            name, v = split_ops(rest)
            equ[name] = value(v, equ)
        else:
            pc += 1
    sym = dict(equ)
    words, lst = [], []
    pc = 0
    for n, raw, mn, rest in items:            # pass 2: code
        if mn in ("LABEL", ".EQU"):
            continue
        try:
            w = encode(mn, split_ops(rest), pc, labels, sym)
        except (AsmError, ValueError, KeyError) as e:
            raise AsmError("line %d: %s: %s" % (n, raw.strip(), e))
        words.append(w)
        lst.append("%03X  %08X  %s %s" % (pc, w, mn, rest.strip()))
        pc += 1
    return words, lst, labels


def encode(mn, ops, pc, labels, sym):
    if mn == "MOVH":                          # F1, u = 1: Ra := imm << 16
        a, imm = reg(ops[0]), value(ops[1], sym)
        return 0x40000000 | (1 << 29) | (a << 24) | (imm & 0xFFFF)
    if mn in ("FLT", "FLR"):                  # FAD with u = 1 (integer -> float) or v = 1 (FLOOR), c = 4B000000H,
        a, b, c = reg(ops[0]), reg(ops[1]), reg(ops[2])   # as Wirth's ORG.Float / ORG.Floor
        uv = (1 << 29) if mn == "FLT" else (1 << 28)
        return uv | (a << 24) | (b << 20) | (12 << 16) | c
    if mn == "GETH":                          # MOV Ra, H (F0, u = 1, v = 0): high word of MUL, remainder of DIV
        return (1 << 29) | (reg(ops[0]) << 24)
    if mn in OPS:
        op = OPS.index(mn)
        if mn == "MOV":
            a, b, c = reg(ops[0]), 0, ops[1]
        else:
            a, b, c = reg(ops[0]), reg(ops[1]), ops[2]
        if is_reg(c):                         # F0
            return (a << 24) | (b << 20) | (op << 16) | reg(c)
        imm = value(c, sym)                   # F1
        if not -0x8000 <= imm <= 0xFFFF:
            raise AsmError("immediate %d does not fit 16 bits" % imm)
        v = 1 if imm < 0 else 0
        return 0x40000000 | (v << 28) | (a << 24) | (b << 20) | (op << 16) | (imm & 0xFFFF)
    if mn in ("LDR", "LDB", "STR", "STB"):    # F2
        u = 1 if mn[0] == "S" else 0
        v = 1 if mn[2] == "B" else 0
        a, b, off = reg(ops[0]), reg(ops[1]), value(ops[2] if len(ops) > 2 else "0", sym)
        if not -0x80000 <= off < 0x80000:
            raise AsmError("offset does not fit 20 bits")
        return 0x80000000 | (u << 29) | (v << 28) | (a << 24) | (b << 20) | (off & 0xFFFFF)
    # F3: B[L]<cc>. Try "BL" + cc first, then "B" + cc: BLT/BLE/BLS are B + LT/LE/LS, BLEQ is BL + EQ
    split = [(1, mn[2:]), (0, mn[1:])] if mn.startswith("BL") else [(0, mn[1:])] if mn.startswith("B") else []
    split = [(lk, cc) for lk, cc in split if cc in CC]
    if split:
        link, cond = split[0][0], CC[split[0][1]]
        t = ops[0]
        if is_reg(t):
            return 0xC0000000 | (link << 28) | (cond << 24) | reg(t)
        if t not in labels:
            raise AsmError("unknown label %r" % t)
        off = labels[t] - (pc + 1)
        return 0xC0000000 | (1 << 29) | (link << 28) | (cond << 24) | (off & 0xFFFFFF)
    raise AsmError("unknown instruction %r" % mn)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("src")
    ap.add_argument("-o", "--out", required=True)
    ap.add_argument("--words", type=int, default=512)
    args = ap.parse_args()
    try:
        words, lst, _ = assemble(open(args.src).read())
    except AsmError as e:
        sys.exit("r5asm: %s" % e)
    write_rom(words, lst, args.out, args.words, "r5asm: " + args.src)


def write_rom(words, lst, out, nwords, who):
    """The ROM image for $readmemh (nwords lines) and the listing next to it (.lst)."""
    if len(words) > nwords:
        sys.exit("%s: %d words do not fit the %d-word ROM" % (who, len(words), nwords))
    with open(out, "w") as f:
        for i in range(nwords):
            f.write("%08X\n" % (words[i] if i < len(words) else 0))
    with open(re.sub(r"\.\w+$", "", out) + ".lst", "w") as f:
        f.write("\n".join(lst) + "\n")
    print("%s -> %s (%d of %d words)" % (who, out, len(words), nwords))


if __name__ == "__main__":
    main()
