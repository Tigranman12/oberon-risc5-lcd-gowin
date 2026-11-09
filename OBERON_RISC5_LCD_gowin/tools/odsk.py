#!/usr/bin/env python3
# odsk.py - OBERON_RISC5_FAST O7: read a Project Oberon 2013 disk image (.dsk = FS sector 1 first, as Wirth's
# FileDir.Mod / Files.Mod lay it out): list the files, or extract them to a directory.
#   odsk.py IMAGE                 list: name, length
#   odsk.py IMAGE -x DIR [GLOB]   extract the files matching GLOB (default *) into DIR
# Layout: sector address a (multiple of 29) = sector a DIV 29, at byte (a DIV 29 - 1) * 1024 of the image.
# Directory: B-tree from DirRootAdr 29; page = mark 9B1EA38DH, m, p0, filler[52], 24 x {name[32], adr, p}.
# File header (mark 9BA71D86H): name[32], aleng, bleng, date, ext[12], sec[64]; data starts at byte 352 (HS) of
# the file's sector 0; length = aleng * 1024 + bleng - 352; sector i >= 64 is in index sector ext[(i-64) DIV 256].
import fnmatch
import os
import struct
import sys

SS, HS, DIRMARK, HDRMARK = 1024, 352, 0x9B1EA38D, 0x9BA71D86


class Disk:
    def __init__(self, path):
        self.b = open(path, "rb").read()

    def sec(self, a):
        assert a % 29 == 0 and a > 0, f"bad sector address {a}"
        o = (a // 29 - 1) * SS
        return self.b[o:o + SS]

    def entries(self, a=29):
        s = self.sec(a)
        mark, m, p0 = struct.unpack_from("<IiI", s, 0)
        assert mark == DIRMARK, f"no dir mark at {a}"
        if p0:
            yield from self.entries(p0)
        for k in range(m):
            o = 64 + 40 * k                      # mark, m, p0, filler[52]
            name = s[o:o + 32].split(b"\0")[0].decode("latin-1")
            adr, p = struct.unpack_from("<II", s, o + 32)
            yield name, adr
            if p:
                yield from self.entries(p)

    def read(self, adr):
        h = self.sec(adr)
        mark = struct.unpack_from("<I", h, 0)[0]
        assert mark == HDRMARK, f"no header mark at {adr}"
        aleng, bleng = struct.unpack_from("<ii", h, 36)
        ext = struct.unpack_from("<12I", h, 48)
        secs = struct.unpack_from("<64I", h, 96)
        n = aleng * SS + bleng - HS
        out = bytearray()
        for i in range(aleng + 1):
            if i < 64:
                a = secs[i]
            else:
                x = self.sec(ext[(i - 64) // 256])
                a = struct.unpack_from("<I", x, 4 * ((i - 64) % 256))[0]
            out += self.sec(a)
        return bytes(out[HS:HS + n])


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__ or "usage: odsk.py IMAGE [-x DIR [GLOB]]")
    d = Disk(sys.argv[1])
    files = list(d.entries())
    if len(sys.argv) >= 4 and sys.argv[2] == "-x":
        pat = sys.argv[4] if len(sys.argv) > 4 else "*"
        os.makedirs(sys.argv[3], exist_ok=True)
        for name, adr in files:
            if fnmatch.fnmatch(name, pat):
                with open(os.path.join(sys.argv[3], name), "wb") as f:
                    f.write(d.read(adr))
                print("x", name)
    else:
        for name, adr in files:
            print(f"{name:32s} {len(d.read(adr)):8d}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
