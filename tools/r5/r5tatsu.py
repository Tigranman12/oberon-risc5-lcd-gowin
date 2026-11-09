#!/usr/bin/env python3
"""r5tatsu.py - the RISC5 assembler written as a TatSu (PEG, OMeta-like) grammar: tools/r5/r5asm.ebnf.

TatSu (pip install TatSu) compiles the grammar into a PEG parser with backtracking and memoization.
The semantic actions below turn each statement into an item; addresses and bit fields come from
r5meta.assemble() and r5asm.encode(), so the three assemblers (r5asm.py, r5meta.py, r5tatsu.py) make the
same ROM (tests/run_all.sh, R5META).

Debugging: --trace prints every rule TatSu tries, with the input it stands on (<, entering; >, matched;
!, failed), so a syntax error can be followed rule by rule. --ast prints the parse tree as JSON.

Usage: r5tatsu.py prog.s -o prom.mem [--trace] [--ast] [--words 512]
"""
import argparse
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import r5asm    # noqa: E402
import r5meta   # noqa: E402

try:
    import tatsu
    from tatsu.exceptions import FailedParse
except ImportError:
    sys.exit("r5tatsu: TatSu is not installed (pip3 install TatSu)")

GRAMMAR = os.path.join(HERE, "r5asm.ebnf")


class Semantics:
    """One method per grammar rule; each gets the rule's result (ast) and returns what the rule gives."""

    def start(self, ast):
        return list(ast.stmts or [])

    def label(self, ast):
        return ("LABEL", ast.name)

    def puts(self, ast):
        s = ast.text
        return ("PUTS", s[1:-1].encode().decode("unicode_escape"))

    def regop(self, ast):
        ops = [ast.a] + ([ast.b] if ast.b is not None else []) + [ast.c]
        return (ast.op, ops)

    def geth(self, ast):
        return (ast.op, [ast.a])

    def memop(self, ast):
        return (ast.op, [ast.a, ast.b, ast.c])

    def branch(self, ast):
        return (ast.op, [ast.t])

    def char(self, ast):
        return str(ord(ast[1]))

    def imm(self, ast):
        return str(int(ast, 0))

    def _default(self, ast):
        return ast


def parse(text, trace=False):
    model = tatsu.compile(open(GRAMMAR).read())
    return model.parse(text, start="start", semantics=Semantics(), trace=trace, colorize=False)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("src")
    ap.add_argument("-o", "--out", required=True)
    ap.add_argument("--trace", action="store_true", help="print TatSu's rule-by-rule trace (to stderr)")
    ap.add_argument("--ast", action="store_true", help="print the statements as JSON")
    ap.add_argument("--words", type=int, default=512)
    a = ap.parse_args()
    try:
        items = parse(open(a.src).read(), trace=a.trace)
        if a.ast:
            print(json.dumps(items, indent=1))
        words, lst = r5meta.assemble(items)
    except FailedParse as e:
        sys.exit("r5tatsu: %s" % e)
    except (r5asm.AsmError, ValueError, KeyError) as e:
        sys.exit("r5tatsu: %s" % e)
    r5asm.write_rom(words, lst, a.out, a.words, "r5tatsu: " + a.src)


if __name__ == "__main__":
    main()
