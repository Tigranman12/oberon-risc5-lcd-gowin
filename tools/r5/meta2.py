#!/usr/bin/env python3
"""meta2.py - D. V. Schorre's META II (1964) in Python: the META II machine and a bootstrap.

META II is a compiler-writing language. A grammar with output actions (.OUT, .LABEL) is compiled into
"order codes" for a small machine; running those codes on a source text parses it and writes the
translation. META II is written in itself (meta2.meta, from Schorre's paper), so it compiles itself.

The machine (Schorre's order codes):
  TST 's'  skip blanks; if the input starts with s, take it; switch := found
  ID       skip blanks; take an identifier (letter {letter | digit}) as the token; switch := found
  NUM      skip blanks; take a number (digits) as the token; switch := found
  SR       skip blanks; take a string in single quotes, quotes included, as the token; switch := found
  CLL l    call l (a new frame with two empty generated labels)       R    return
  SET      switch := true    B l  branch    BT l / BF l  branch if switch true / false
  BE       stop with a syntax error if switch is false
  CL 's'   copy s to the output line    CI  copy the token    GN1 / GN2  this frame's label 1 / 2
  LB       the output line starts in column 1 (a label line)      OUT  end the output line
  ADR l    start at l                   END  end of the program
Output lines that are not label lines are indented by 8 blanks (Schorre's card column 8).

Debugging: trace= (--trace) prints every rule call (>) and return (< matched, ! not matched) with the
line:column and the next input characters, indented by call depth.

Extensions (named, off unless asked): comment=';' skips ';' to the end of the line wherever blanks are
skipped; hex=True lets NUM also take 0x... numbers. Neither is used when META II compiles itself.

The first order codes for META II come from boot(): a hand-written Python compiler of the META II
language. selftest() checks the fixed point: META II compiled by the boot codes, compiled again by
itself, gives the same codes both times.

Usage:
  meta2.py --selftest                         fixed point of META II (prints "META II: fixed point OK")
  meta2.py GRAMMAR.meta INPUT [-o OUT]        compile GRAMMAR with META II, run it on INPUT
"""
import argparse
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
META2_SRC = os.path.join(HERE, "meta2.meta")


class MetaError(Exception):
    pass


# ---------------------------------------------------------------- the machine

def load(codes):
    """Order-code lines -> (program list, label -> index)."""
    prog, labels = [], {}
    for line in codes:
        if not line.strip():
            continue
        if not line[0].isspace():
            labels[line.strip()] = len(prog)
            continue
        op, _, arg = line.strip().partition(" ")
        arg = arg.strip()
        if arg.startswith("'") and arg.endswith("'") and len(arg) >= 2:
            arg = arg[1:-1]
        prog.append((op, arg))
    return prog, labels


def run(codes, text, comment=None, hexnum=False, trace=None):
    """Run order codes on text; returns the output lines. Raises MetaError on a syntax error.
    trace: a file (e.g. sys.stderr) that gets one line per rule call and return, with the input position."""
    prog, labels = load(codes)
    pos, token, switch = 0, "", False
    out, line, is_label = [], "", False
    stack = []                                # frames: [return pc, label 1, label 2]
    gen = [0]

    def skip():
        nonlocal pos
        while pos < len(text):
            if text[pos].isspace():
                pos += 1
            elif comment and text.startswith(comment, pos):
                while pos < len(text) and text[pos] != "\n":
                    pos += 1
            else:
                break

    def where():
        ln = text.count("\n", 0, pos) + 1
        start = text.rfind("\n", 0, pos) + 1
        end = text.find("\n", pos)
        src = text[start:end if end >= 0 else len(text)]
        return "line %d: %s\n%s^" % (ln, src, " " * (8 + len(str(ln)) + pos - start))

    def show(mark, rule):
        if trace:
            ln = text.count("\n", 0, pos) + 1
            col = pos - text.rfind("\n", 0, pos)
            ahead = text[pos:pos + 24].replace("\n", "\\n")
            trace.write("%s%s %s  @%d:%d  %r\n" % ("  " * (len(stack) - 1), mark, rule, ln, col, ahead))

    def label(k):
        frame = stack[-1]
        if frame[k] is None:
            gen[0] += 1
            frame[k] = "L%d" % gen[0]
        return frame[k]

    pc = None
    for i, (op, arg) in enumerate(prog):      # ADR: the first order code
        if op == "ADR":
            pc = labels[arg]
            stack.append([None, None, None])
            break
    if pc is None:
        raise MetaError("no ADR in the order codes")
    while True:
        op, arg = prog[pc]
        pc += 1
        if op == "TST":
            skip()
            switch = text.startswith(arg, pos)
            if switch:
                pos += len(arg)
        elif op == "ID":
            skip()
            switch = pos < len(text) and text[pos].isalpha()
            if switch:
                e = pos + 1
                while e < len(text) and text[e].isalnum():
                    e += 1
                token, pos = text[pos:e], e
        elif op == "NUM":
            skip()
            e = pos
            if hexnum and text.startswith(("0x", "0X"), pos):
                e = pos + 2
                while e < len(text) and text[e] in "0123456789abcdefABCDEF":
                    e += 1
                if e == pos + 2:
                    e = pos
            if e == pos:
                while e < len(text) and text[e].isdigit():
                    e += 1
            switch = e > pos
            if switch:
                token, pos = text[pos:e], e
        elif op == "SR":
            skip()
            switch = pos < len(text) and text[pos] == "'"
            if switch:
                e = text.find("'", pos + 1)
                if e < 0:
                    raise MetaError("string without its closing quote at " + where())
                token, pos = text[pos:e + 1], e + 1
        elif op == "CLL":
            stack.append([pc, None, None, arg])
            show(">", arg)
            pc = labels[arg]
        elif op == "R":
            if len(stack[-1]) > 3:
                show("<" if switch else "!", stack[-1][3])
            ret = stack.pop()[0]
            if ret is None:                   # return from the start rule: done
                break
            pc = ret
        elif op == "SET":
            switch = True
        elif op == "B":
            pc = labels[arg]
        elif op == "BT":
            if switch:
                pc = labels[arg]
        elif op == "BF":
            if not switch:
                pc = labels[arg]
        elif op == "BE":
            if not switch:
                raise MetaError("syntax error at " + where())
        elif op == "CL":
            line += arg
        elif op == "CI":
            line += token
        elif op == "GN1":
            line += label(1)
        elif op == "GN2":
            line += label(2)
        elif op == "LB":
            is_label = True
        elif op == "OUT":
            out.append(line if is_label else " " * 8 + line)
            line, is_label = "", False
        elif op == "END":
            break
        elif op == "ADR":
            pass
        else:
            raise MetaError("unknown order code %r" % op)
    skip()
    if pos < len(text):
        raise MetaError("not all input was read; stopped at " + where())
    return out


# ---------------------------------------------------------------- bootstrap

class _Boot:
    """META II's own grammar, compiled by hand: the same rules as meta2.meta, written in Python."""

    def __init__(self, text):
        self.t, self.p, self.out, self.n = text, 0, [], 0

    def skip(self):
        while self.p < len(self.t) and self.t[self.p].isspace():
            self.p += 1

    def tst(self, s):
        self.skip()
        if self.t.startswith(s, self.p):
            self.p += len(s)
            return True
        return False

    def need(self, s):
        if not self.tst(s):
            raise MetaError("boot: %r expected at %d" % (s, self.p))

    def ident(self):
        self.skip()
        if self.p < len(self.t) and self.t[self.p].isalpha():
            e = self.p + 1
            while e < len(self.t) and self.t[e].isalnum():
                e += 1
            s, self.p = self.t[self.p:e], e
            return s
        return None

    def string(self):
        self.skip()
        if self.p < len(self.t) and self.t[self.p] == "'":
            e = self.t.index("'", self.p + 1)
            s, self.p = self.t[self.p:e + 1], e + 1
            return s
        return None

    def gen(self):
        self.n += 1
        return "B%d" % self.n

    def emit(self, op, arg=None):
        self.out.append(" " * 8 + op + (" " + arg if arg else ""))

    def program(self):                        # '.SYNTAX' .ID .OUT('ADR ' *) $ ST '.END' .OUT('END')
        self.need(".SYNTAX")
        self.emit("ADR", self.ident())
        while self.st():
            pass
        self.need(".END")
        self.emit("END")
        return self.out

    def st(self):                             # .ID .LABEL * '=' EX1 '.,' .OUT('R')
        name = self.ident()
        if name is None:
            return False
        self.out.append(name)
        self.need("=")
        if not self.ex1():
            raise MetaError("boot: rule %s is empty" % name)
        self.need(".,")
        self.emit("R")
        return True

    def ex1(self):                            # EX2 $('/' .OUT('BT ' *1) EX2) .LABEL *1
        if not self.ex2():
            return False
        lab = self.gen()
        while self.tst("/"):
            self.emit("BT", lab)
            if not self.ex2():
                raise MetaError("boot: alternative expected at %d" % self.p)
        self.out.append(lab)
        return True

    def ex2(self):                            # (EX3 .OUT('BF ' *1) / OUTPUT) $(EX3 .OUT('BE') / OUTPUT) .LABEL *1
        lab = self.gen()
        if self.ex3():
            self.emit("BF", lab)
        elif not self.output():
            return False
        while True:
            if self.ex3():
                self.emit("BE")
            elif not self.output():
                break
        self.out.append(lab)
        return True

    def ex3(self):
        name = self.ident()
        if name is not None:
            self.emit("CLL", name)
            return True
        s = self.string()
        if s is not None:
            self.emit("TST", s)
            return True
        for kw, op in ((".ID", "ID"), (".NUMBER", "NUM"), (".STRING", "SR")):
            if self.tst(kw):
                self.emit(op)
                return True
        if self.tst("("):
            if not self.ex1():
                raise MetaError("boot: expression expected at %d" % self.p)
            self.need(")")
            return True
        if self.tst(".EMPTY"):
            self.emit("SET")
            return True
        if self.tst("$"):
            lab = self.gen()
            self.out.append(lab)
            if not self.ex3():
                raise MetaError("boot: item expected after $ at %d" % self.p)
            self.emit("BT", lab)
            self.emit("SET")
            return True
        return False

    def output(self):                         # ('.OUT' '(' $OUT1 ')' / '.LABEL' .OUT('LB') OUT1) .OUT('OUT')
        if self.tst(".OUT"):
            self.need("(")
            while self.out1():
                pass
            self.need(")")
        elif self.tst(".LABEL"):
            self.emit("LB")
            if not self.out1():
                raise MetaError("boot: label item expected at %d" % self.p)
        else:
            return False
        self.emit("OUT")
        return True

    def out1(self):                           # '*1' / '*2' / '*' / .STRING
        for s, op in (("*1", "GN1"), ("*2", "GN2"), ("*", "CI")):
            if self.tst(s):
                self.emit(op)
                return True
        s = self.string()
        if s is not None:
            self.emit("CL", s)
            return True
        return False


def boot(text):
    return _Boot(text).program()


def meta2_codes():
    """META II's order codes, made by META II itself (from the boot codes)."""
    src = open(META2_SRC).read()
    return run(boot(src), src)


def compile_grammar(grammar_text):
    return run(meta2_codes(), grammar_text)


def selftest():
    src = open(META2_SRC).read()
    b = run(boot(src), src)                   # META II compiled by the boot compiler's codes
    c = run(b, src)                           # ... and by its own codes
    if b != c:
        sys.exit("META II: NOT a fixed point (%d / %d lines)" % (len(b), len(c)))
    print("META II: fixed point OK (%d order codes)" % len(b))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--selftest", action="store_true")
    ap.add_argument("grammar", nargs="?")
    ap.add_argument("input", nargs="?")
    ap.add_argument("-o", "--out")
    ap.add_argument("--comment")
    ap.add_argument("--hex", action="store_true")
    ap.add_argument("--trace", action="store_true", help="rule calls and returns of the INPUT run, to stderr")
    a = ap.parse_args()
    try:
        if a.selftest:
            selftest()
            return
        if not (a.grammar and a.input):
            ap.error("give GRAMMAR and INPUT, or --selftest")
        codes = compile_grammar(open(a.grammar).read())
        result = run(codes, open(a.input).read(), comment=a.comment, hexnum=a.hex,
                     trace=sys.stderr if a.trace else None)
    except MetaError as e:
        sys.exit("meta2: %s" % e)
    text = "\n".join(result) + "\n"
    if a.out:
        open(a.out, "w").write(text)
    else:
        sys.stdout.write(text)


if __name__ == "__main__":
    main()
