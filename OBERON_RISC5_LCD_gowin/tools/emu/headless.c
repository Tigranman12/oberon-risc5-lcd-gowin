// headless.c - OBERON_RISC5_FAST O7/O9: run Peter De Wachter's oberon-risc-emu RISC5 core (risc.c, disk.c) with
// no SDL: the disk image on SPI 1, the RS232 on stdin/stdout, virtual time (1 ms = 25000 cycles per step).
//   headless DISK [SCRIPT [MAXMS [SCREEN.pbm]]]
// SCRIPT: lines to type; line k is sent after the k+1-th "OR> " prompt (TTY.Mod) has been printed. The run ends
// MAXMS (default 60000) virtual ms after the start, or 2 s after the last line's prompt. SCREEN.pbm: the 1024 x
// 768 frame buffer at the end (Oberon y = 0 is the bottom line; pixel 1 written black).
// LCD=1 (OBERON_RISC5_LCD_gowin L2): the board's screen instead: 480 x 272 at 400000H (needs the plain disk).
#define _POSIX_C_SOURCE 200809L
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "risc.h"
#include "risc-io.h"
#include "disk.h"

static char *lines[256];
static int nlines, sent, prompts;
static const char *cur;              // the line being typed (NULL: none)
static char tail[4];

static uint32_t ser_status(const struct RISC_Serial *s) {
  (void)s;
  if (!cur && sent < nlines && prompts > sent) cur = lines[sent++];
  return (cur ? 1u : 0u) | 2u;       // bit 0: a byte received, bit 1: transmitter ready
}
static uint32_t ser_read(const struct RISC_Serial *s) {
  (void)s;
  if (!cur) return 0;
  uint32_t c = (uint8_t)*cur++;
  if (*cur == 0) cur = NULL;
  return c;
}
static void ser_write(const struct RISC_Serial *s, uint32_t v) {
  (void)s;
  char c = (char)v;
  if (c != '\n') putchar(c == '\r' ? '\n' : c);
  memmove(tail, tail + 1, 3); tail[3] = c;
  if (memcmp(tail, "OR> ", 4) == 0) { prompts++; fflush(stdout); }
}
static const struct RISC_Serial serial = { ser_status, ser_read, ser_write };

int main(int argc, char **argv) {
  if (argc < 2) { fprintf(stderr, "usage: headless DISK [SCRIPT [MAXMS [SCREEN.pbm]]]\n"); return 2; }
  if (argc > 2) {
    FILE *f = fopen(argv[2], "r");
    if (!f) { perror(argv[2]); return 2; }
    char buf[512];
    while (nlines < 256 && fgets(buf, sizeof buf, f)) {
      size_t n = strcspn(buf, "\r\n");
      buf[n] = '\r'; buf[n + 1] = 0;
      lines[nlines++] = strdup(buf);
    }
    fclose(f);
  }
  long maxms = argc > 3 ? atol(argv[3]) : 60000;
  struct RISC *risc = risc_new();
  risc_set_serial(risc, &serial);
  risc_set_spi(risc, 1, disk_new(argv[1]));
  int lcd = getenv("LCD") != NULL, fbw = lcd ? 480 : 1024, fbh = lcd ? 272 : 768;
  if (lcd) {   /* OBERON_RISC5_LCD_gowin L2: the board's 480 x 272 screen at 400000H (risc_configure_memory writes
                  53697A67H, 480, 272, 400000H at 0E7F00H, as the monitor's o); MemLim and stackOrg back to the
                  board's monitor values (0E7EF0H, 80000H) in the emulator's boot ROM */
    risc_configure_memory(risc, 4, fbw, fbh);
    extern void headless_patch_rom(struct RISC *risc, uint32_t mem_lim, uint32_t stack_org);
    headless_patch_rom(risc, 0xE7EF0, 0x80000);
    fprintf(stderr, "headless: LCD 480 x 272 at 400000H, MemLim 0E7EF0H, stackOrg 80000H\n");
  }
  { extern FILE *risc_trace; extern unsigned risc_stop;      /* tools/emu/tracehook.py */
    if (getenv("TRACE")) risc_trace = fopen(getenv("TRACE"), "w");
    if (getenv("STOPAT")) risc_stop = (unsigned)strtoul(getenv("STOPAT"), NULL, 16); }
  const char *fill = getenv("FILLRAM");   /* O9r: RAM not zero at power-up, as the board's PSRAM (hex word) */
  if (fill) {
    uint32_t *ram = risc_get_framebuffer_ptr(risc) - 0xE7F00 / 4, v = (uint32_t)strtoul(fill, NULL, 16);
    for (uint32_t k = 0; k < 0x400000 / 4; k++) if (k < 0xE7F00 / 4 || k >= 0x100000 / 4) ram[k] = v;
    fprintf(stderr, "headless: RAM filled with %08X (not the display)\n", v);
  }
  const char *rd = getenv("RDISK");   /* O9r: the RAM-disk Kernel's disk at 100000H (needs risc.c with 4 MB) */
  if (rd) {
    uint32_t *ram = risc_get_framebuffer_ptr(risc) - 0xE7F00 / 4;   /* the display stays at 0E7F00H */
    FILE *f = fopen(rd, "rb");
    if (!f) { perror(rd); return 2; }
    size_t n = fread((char *)ram + 0x100000, 1, 0x300000, f);
    fclose(f);
    fprintf(stderr, "headless: RAM disk %s, %zu bytes at 100000H\n", rd, n);
  }
  long done_at = -1;
  for (long ms = 0; ms < maxms; ms++) {
    risc_set_time(risc, (uint32_t)ms);
    risc_run(risc, 25000);
    if (done_at < 0 && sent == nlines && !cur && prompts > nlines) done_at = ms;
    if (done_at >= 0 && ms - done_at > 2000) break;
  }
  fflush(stdout);
  fprintf(stderr, "headless: %d of %d lines sent, %d prompts\n", sent, nlines, prompts);
  if (argc > 4) {
    uint32_t *fb = risc_get_framebuffer_ptr(risc);
    FILE *p = fopen(argv[4], "wb");
    if (!p) { perror(argv[4]); return 2; }
    fprintf(p, "P4\n%d %d\n", fbw, fbh);
    for (int r = 0; r < fbh; r++) {
      uint32_t *row = fb + (fbh - 1 - r) * (fbw / 32);
      for (int b = 0; b < fbw / 8; b++) {
        uint32_t w = row[b / 4];
        uint8_t o = 0;
        for (int k = 0; k < 8; k++) o |= ((w >> ((b % 4) * 8 + k)) & 1u) << (7 - k);
        fputc(o, p);
      }
    }
    fclose(p);
  }
  return 0;
}
