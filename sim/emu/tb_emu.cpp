// The MiSTer top-level bench's driver (sim/emu/run_emu.sh): plays the HPS for ArcadiaSystems.sv.
//   Vtb_emu_top <image.rom> <frames after the load> <out prefix>
// The load:
//   streamed (default)  the image through the ioctl port a byte at a time, honouring ioctl_wait, as Main_MiSTer sends an MRA's ROM
//   FAST=1              the MRA's address= fast load: the image put into the DDR3 at byte 0x32000000, then a download that carries
//                       only the length (rtl/arcadia_fastload.v reads it back)
//   PRELOAD=1           only the 16-byte header through the port; the memory holds the rest from the start (the video-mode runs)
// After a load every word the loader wrote is compared with the layout computed here, independently (as sim/tb_arcadia.cpp's
// -checkload). Then the machine runs; every SNAPEVERY-th picture the scaler gets (VGA_* on CE_PIXEL with VGA_DE) is written as
// <prefix>.f<n>.ppm (n counted from the 68000 leaving reset) and the raster is checked: a vertical sync every frame, the frame
// period, the rows and lines of a frame, where the rows sit and how wide they are, and the size the core asks of the HDMI
// scaler (Scale).
// The OSD and the framework's settings:
//   FX=n          Scandoubler Fx (0 None, 1 HQ2x, 2-4 CRT 25/50/75 %); FSD=1 MiSTer.ini's forced_scandoubler
//   CRT=1 HSIZE=n HPOS=n VSHIFT=n   CRT Adjust and its values (signed, as the OSD shows them)
//   SCALE=n (0 Normal, 1 V-Integer, 2 HV-Integer, 3 Narrower HV-Integer, 4 HV-Integer+), AR=n (Aspect ratio), HW / HH the scaler's size
//   SETAT=f       the settings go in at frame f (default: before the load), so a run also switches modes while the picture runs
// SAVEAT=f SAVE=<file>: save the whole model at frame f and stop; RESTORE=<file>: start from such a save instead of loading (the
// video-mode runs, sim/emu/run_modes.sh, start from the OnePlay screen this way).
#include "Vtb_emu_top.h"
#include "Vtb_emu_top___024root.h"
#include "verilated.h"
#include "verilated_save.h"
#include <cstdio>
#include <cstdlib>
#include <cstdint>
#include <string>
#include <vector>
#include <map>

static Vtb_emu_top *t;
static uint64_t cyc = 0;                                  // 4x clock cycles (114.5 MHz)
static bool vclk_rise = false;                            // this tick ended with a rise of the video clock
static void tick() {
    bool v0 = t->CLK_VIDEO;
    t->CLK_50M = 1; t->eval();
    bool v1 = t->CLK_VIDEO;
    t->CLK_50M = 0; t->eval();
    vclk_rise = (!v0 && v1);
    cyc++;
}
#define HPSV(n) t->rootp->tb_emu_top__DOT__u_emu__DOT__hps_io__DOT__##n
#define EMU(n) t->rootp->tb_emu_top__DOT__u_emu__DOT__##n

static std::vector<uint8_t> slurp(const char *fn) {
    std::vector<uint8_t> v;
    FILE *f = fopen(fn, "rb");
    if (!f) { fprintf(stderr, "cannot open %s\n", fn); exit(2); }
    fseek(f, 0, SEEK_END); v.resize(ftell(f)); fseek(f, 0, SEEK_SET);
    if (fread(v.data(), 1, v.size(), f) != v.size()) exit(2);
    fclose(f);
    return v;
}
static int env(const char *n, int d = 0) { return getenv(n) ? atoi(getenv(n)) : d; }
static void set_status(int bit, int v) {
    int w = bit / 32, b = bit % 32;
    unsigned x = HPSV(r_status)[w];
    HPSV(r_status)[w] = v ? (x | (1u << b)) : (x & ~(1u << b));
}
static void set_field(int lo, int w, int v) { for (int i = 0; i < w; i++) set_status(lo + i, (v >> i) & 1); }

// what rtl/arcadia_loader.v and gary.v make of the image, in the SRAM bridge's space (word addresses): Kickstart at $780000, the
// BIOS at $700000, the ROM board at $200000, the scrambled low bytes fixed (MAME's generic_decode)
template <class F> static void layout(const std::vector<uint8_t> &img, F put) {
    auto unscr = [](uint8_t d, const uint8_t *p) {
        uint8_t o = 0;
        for (int k = 0; k < 8; k++) o |= ((d >> p[k]) & 1) << (7 - k);
        return o;
    };
    static const uint8_t bios_perm[8] = {6, 1, 0, 2, 3, 4, 5, 7};
    const uint8_t *perm = &img[0];
    bool bios_scr = !(img[0x80010] == 0x4a && img[0x80011] == 0xfc);
    for (uint32_t o = 0; o + 1 < 0x280000; o += 2) {
        uint8_t hi = img[0x10 + o], lo = img[0x10 + o + 1];
        uint32_t a;
        if (o < 0x80000) a = 0x780000 + o;
        else if (o < 0x100000) { a = 0x700000 + (o - 0x80000); if (bios_scr && o - 0x80000 < 0x20000) lo = unscr(lo, bios_perm); }
        else { a = 0x200000 + (o - 0x100000); if (o - 0x100000 < 0x20000) lo = unscr(lo, perm); }
        put(a >> 1, (uint16_t)((hi << 8) | lo));
    }
}

static void apply_settings() {
    set_field(3, 3, env("FX"));                                     // Scandoubler Fx
    HPSV(r_fsd) = env("FSD") ? 1 : 0;                               // MiSTer.ini's forced_scandoubler
    set_status(19, env("CRT") ? 1 : 0);                             // CRT Adjust: [24:20] H-Size, [31:25] H-Position, [36:32] V-Shift
    { int v = env("HSIZE"); set_field(20, 5, v >= 0 ? v : 23 + v); }   // the OSD lists 0..+6, -16..-1
    { int v = env("HPOS");  set_field(25, 7, v >= 0 ? v : 81 + v); }   // the OSD lists 0..+32, -48..-1
    set_field(32, 5, env("VSHIFT") & 31);
    set_field(16, 3, env("SCALE"));                                 // Scale
    set_field(1, 2, env("AR"));                                     // Aspect ratio
}

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    if (argc < 4) { fprintf(stderr, "usage: Vtb_emu_top <image.rom> <frames> <prefix>\n"); return 2; }
    std::vector<uint8_t> img = slurp(argv[1]);
    if (img.size() < 0x280010) { fprintf(stderr, "short image\n"); return 2; }
    int frames = atoi(argv[2]);
    std::string prefix = argv[3];
    const bool fast = env("FAST"), preload = env("PRELOAD");
    const int snapevery = env("SNAPEVERY", 10);
    int setat = env("SETAT", -1);
    unsigned errors = 0;
    t = new Vtb_emu_top;
    auto &R = *t->rootp;
    t->HDMI_WIDTH = env("HW", 1920); t->HDMI_HEIGHT = env("HH", 1080);
    t->eval();   // the first evaluation applies the initial values (the stub's status word among them): the settings go in after it

    const int fx = env("FX"); const bool fsd = env("FSD");
    const bool sd_on = fx || fsd, crt = env("CRT") && !sd_on, vshift = crt && env("VSHIFT");
    if (setat < 0) apply_settings();
    printf("settings%s: Scandoubler Fx %d, forced_scandoubler %d, CRT Adjust %s (H-Size %d, H-Position %d, V-Shift %d), Scale %d, Aspect %d, scaler %d x %d\n",
           setat >= 0 ? (" from frame " + std::to_string(setat)).c_str() : "", fx, (int)fsd, env("CRT") ? "On" : "Off",
           env("HSIZE"), env("HPOS"), env("VSHIFT"), env("SCALE"), env("AR"), (int)t->HDMI_WIDTH, (int)t->HDMI_HEIGHT);

    auto &mem = R.tb_emu_top__DOT__u_emu__DOT__ram1__DOT__mem;
    const char *restore = getenv("RESTORE");
    if (restore) {
        VerilatedRestore is;
        is.open(restore);
        is >> *t;
        is.close();
        printf("restored %s\n", restore);
        if (setat < 0) apply_settings();       // the restored model has the saved settings
    }
    else {
    if (preload) layout(img, [&](uint32_t w, uint16_t v) { mem[w] = v; });

    t->RESET = 1;
    for (int i = 0; i < 256; i++) tick();
    t->RESET = 0;
    for (int i = 0; i < 8000; i++) tick();

    // ---------------------------------------------------------------- the load
    uint64_t t0 = cyc;
    HPSV(r_index) = 0;
    auto stream = [&](size_t n) {
        HPSV(r_download) = 1;
        HPSV(r_addr) = 0;
        for (int i = 0; i < 80; i++) tick();
        for (size_t i = 0; i < n; i++) {
            while (HPSV(r_wait_seen)) tick();
            HPSV(r_addr) = i;
            HPSV(r_dout) = img[i];
            HPSV(r_wr) = 1; for (int k = 0; k < 4; k++) tick();     // one machine clock edge
            HPSV(r_wr) = 0; for (int k = 0; k < 8; k++) tick();     // ioctl_wait, as the stub registers it, settles
            if ((i & 0x7ffff) == 0 && i) { printf("load %zu KB\n", i >> 10); fflush(stdout); }
        }
        for (int i = 0; i < 4; i++) tick();                     // Main_MiSTer ends the download right after the last byte
        HPSV(r_download) = 0;
        HPSV(r_addr) = n;
    };
    if (preload) stream(16);
    else if (fast) {
        auto &dm = R.tb_emu_top__DOT__ddr__DOT__mem;
        for (size_t i = 0; i < img.size(); i += 8) {
            uint64_t w = 0;
            for (int b = 0; b < 8 && i + b < img.size(); b++) w |= (uint64_t)img[i + b] << (8 * b);
            dm[i / 8] = w;                                            // byte 0x32000000: the start of the model's window
        }
        HPSV(r_addr) = img.size();                                    // Main_MiSTer: user_io_set_download(1, len)
        HPSV(r_download) = 1;
        for (int i = 0; i < 400; i++) tick();
        HPSV(r_download) = 0;
        HPSV(r_addr) = img.size() + 1;
    }
    else stream(img.size());
    uint64_t t1 = cyc;
    // the loader lets the 68000 go about 150 ms after the load (arcadia_loader.v)
    uint64_t t_data = 0;
    while (EMU(cpuhlt)) {
        tick();
        if (!t_data && !EMU(fast_dl) && !EMU(ld_busy) && !EMU(ld_own)) t_data = cyc;
        if (((cyc - t0) & 0xffffff) == 0) {
            printf("  %.3f s: fast_dl %d, replay state %d left %d, loader busy %d own %d\n", (cyc - t0) / 114.5e6, (int)EMU(fast_dl),
                   (int)EMU(fastload__DOT__state), (int)EMU(fastload__DOT__left), (int)EMU(ld_busy), (int)EMU(ld_own));
            fflush(stdout);
        }
        if (cyc - t0 > 400000000ull) { printf("  FAIL: the load does not end\n"); errors++; break; }
    }
    printf("load: %s, the HPS's part %.3f s, the image in memory %.3f s after the start, the 68000 runs %.3f s after the start (machine time)\n",
           preload ? "preloaded" : fast ? "fast (DDR3)" : "streamed", (t1 - t0) / 114.5e6, (t_data - t0) / 114.5e6, (cyc - t0) / 114.5e6);
    if (fast) printf("DDR3: %d read bursts, %d protocol errors\n", (int)R.tb_emu_top__DOT__ddr__DOT__rd_cmds,
                     (int)R.tb_emu_top__DOT__ddr__DOT__protocol_errors);
    if (fast && R.tb_emu_top__DOT__ddr__DOT__protocol_errors) errors++;
    if (!preload) {
        uint32_t bad = 0, n = 0;
        layout(img, [&](uint32_t w, uint16_t v) {
            n++;
            if (mem[w] != v) {
                if (bad < 10) printf("  word %06x: loader %04x, expected %04x\n", w << 1, (unsigned)mem[w], v);
                bad++;
            }
        });
        printf("memory: %u of %u words differ from the layout\n", bad, n);
        if (bad) errors++;
    }
    }
    const int saveat = env("SAVEAT", -1);

    // ---------------------------------------------------------------- the pictures and the raster
    // on each rise of the video clock: VGA_* as the scaler takes them (CE_PIXEL), the raster at clock level
    const int MAXW = 2048, MAXH = 640;
    std::vector<uint8_t> fb(MAXW * MAXH * 3, 0);
    int row = -1, col = 0, maxcol = 0;
    int frame = 0;
    bool pvs = false, phs = false, pde = false;
    uint64_t last_vs = 0, vs_t = 0, hs_t = 0, de_t = 0;
    std::vector<uint64_t> periods;
    int lines = 0, rows = 0; long first = -1, smin = 1L << 30, smax = -1, wmin = 1L << 30, wmax = -1;
    int g_rows = 0, g_lines = 0, g_w = 0; long g_first = -1, g_smin = 0, g_smax = 0, g_wmin = 0, g_wmax = 0;
    std::map<int, int> rowpix;                                       // pixels per row -> rows (CE_PIXEL with DE)
    std::map<int, int> g_rowpix;
    const uint64_t run0 = cyc;
    const uint64_t NOVS = 4 * 1900000ull;                            // four frames' worth of 4x clocks
    while (frame < frames) {
        tick();
        if (setat >= 0 && frame == setat) { apply_settings(); setat = -1; printf("settings in at frame %d\n", frame); }
        if (saveat >= 0 && frame == saveat && getenv("SAVE")) {
            VerilatedSave os;
            os.open(getenv("SAVE"));
            os << *t;
            os.close();
            printf("saved at frame %d to %s\n", frame, getenv("SAVE"));
            break;
        }
        if (cyc - (last_vs ? last_vs : run0) > NOVS) {   // a scandoubler that lost the line timing stops the vertical sync
            printf("  FAIL: no vertical sync for %llu clocks after frame %d\n", (unsigned long long)NOVS, frame); errors++;
            break;
        }
        if (!vclk_rise) continue;
        bool hs = t->VGA_HS, vs = t->VGA_VS, de = t->VGA_DE;
        if (hs && !phs) { lines++; hs_t = cyc; }
        if (de && !pde) {
            long s = (long)(cyc - hs_t); de_t = cyc; rows++;
            if (first < 0) first = (long)(cyc - vs_t);
            if (s < smin) smin = s;
            if (s > smax) smax = s;
            row++; col = 0;
        }
        if (!de && pde) {
            long w = (long)(cyc - de_t); if (w < wmin) wmin = w; if (w > wmax) wmax = w;
            rowpix[col]++;
        }
        if (vs && !pvs) {                       // a frame starts
            g_rows = rows; g_lines = lines; g_first = first; g_smin = smin; g_smax = smax; g_wmin = wmin; g_wmax = wmax;
            g_rowpix = rowpix; g_w = maxcol;
            if (frame % snapevery == 0 && row >= 0) {
                char fn[64]; snprintf(fn, sizeof fn, ".f%04d.ppm", frame);
                FILE *o = fopen((prefix + fn).c_str(), "wb");
                int h = row + 1 > MAXH ? MAXH : row + 1, w = maxcol > MAXW ? MAXW : maxcol;
                fprintf(o, "P6\n%d %d\n255\n", w, h);
                for (int y = 0; y < h; y++) fwrite(&fb[(size_t)y * MAXW * 3], 1, (size_t)w * 3, o);
                fclose(o);
            }
            if (frame % 50 == 0) { printf("frame %d\n", frame); fflush(stdout); }
            vs_t = cyc; lines = 0; first = -1; rows = 0; smin = 1L << 30; smax = -1; wmin = 1L << 30; wmax = -1;
            rowpix.clear();
            if (last_vs) periods.push_back(cyc - last_vs);
            last_vs = cyc;
            frame++;
            std::fill(fb.begin(), fb.end(), 0);
            row = -1; col = 0; maxcol = 0;
        }
        if (t->CE_PIXEL && de && row >= 0 && row < MAXH) {
            if (col < MAXW) { uint8_t *p = &fb[((size_t)row * MAXW + col) * 3]; p[0] = t->VGA_R; p[1] = t->VGA_G; p[2] = t->VGA_B; }
            col++;
            if (col > maxcol) maxcol = col;
        }
        phs = hs; pvs = vs; pde = de;
    }
    printf("done: %d frames after the load\n", frame);
    {   // the frame period: the same every frame; V-Shift moves the vertical sync by whole lines, so the frame in which it takes
        // effect is another length, and so is the one a mode switch (SETAT) lands in
        std::map<uint64_t, int> hist;
        for (size_t i = 1; i < periods.size(); i++) hist[periods[i]]++;
        uint64_t common = 0; int cn = 0;
        for (auto &kv : hist) if (kv.second > cn) { common = kv.first; cn = kv.second; }
        int other = (int)periods.size() - 1 - cn, allowed = (vshift ? 2 : 0) + ((env("SETAT", -1) >= 0 || getenv("RESTORE")) ? 2 : 0);
        printf("frame period: %llu clocks of 114.5 MHz (%.4f Hz at NTSC) in %d of %d frames", (unsigned long long)common,
               114.545e6 / (double)(common ? common : 1), cn, (int)periods.size() - 1);
        for (auto &kv : hist) if (kv.first != common) printf("; %llu x%d", (unsigned long long)kv.first, kv.second);
        printf("\n");
        for (size_t i = 1; i < periods.size(); i++)
            if (periods[i] != common) printf("  frame %zu: %llu clocks (%.3f lines)\n", i + 1,
                                             (unsigned long long)periods[i], periods[i] / 7264.0);
        if (cn == 0 || other > allowed) { printf("  FAIL: frames of another length\n"); errors++; }
    }
    printf("raster (last whole frame): %d lines, %d rows with picture; first row %ld clocks after the vsync; rows start %ld..%ld clocks after"
           " hsync, %ld..%ld clocks wide; pixels a row:", g_lines, g_rows, g_first, g_smin, g_smax, g_wmin, g_wmax);
    for (auto &kv : g_rowpix) printf(" %d (x%d)", kv.first, kv.second);
    printf("\n");
    {   // every row the same: where it starts, how wide, how many pixels
        if (g_smin != g_smax || g_wmin != g_wmax || g_rowpix.size() != 1) { printf("  FAIL: rows differ\n"); errors++; }
        if (g_lines < 200) { printf("  FAIL: too few lines\n"); errors++; }
    }
    if (getenv("EXPECT_LINES") && g_lines != env("EXPECT_LINES")) { printf("  FAIL: %d lines, expected %d\n", g_lines, env("EXPECT_LINES")); errors++; }
    if (getenv("EXPECT_ROWS") && g_rows != env("EXPECT_ROWS")) { printf("  FAIL: %d rows, expected %d\n", g_rows, env("EXPECT_ROWS")); errors++; }
    {   // Scale: the size the core asks the scaler for, worked out from the picture (rows, pixels in a row), the OSD settings and the
        // scaler's size by the framework's rule (video_freak): the picture scaled up by the largest whole factor that fits the
        // scaler's height; its width follows the aspect ratio (V-Integer) or is a whole multiple of the pixel row (narrower = the
        // multiple below the aspect width, wider = the one above it, HV-Integer = whichever is nearer, the wider one only if it fits)
        const int menu = env("SCALE"), ar = env("AR");
        const int HW = t->HDMI_WIDTH, HH = t->HDMI_HEIGHT;
        const int nrows = g_rows, w = g_rowpix.empty() ? 0 : g_rowpix.begin()->first;
        static const int map[5] = {0, 1, 4, 2, 3};                    // the OSD's order -> video_freak's SCALE
        const int sel = (menu >= 0 && menu <= 4) ? map[menu] : 0;
        const bool fs_int = ar == 1 && sel != 0 && HW != 0 && HH != 0;
        const int arx_in = fs_int ? HW : (ar == 0 ? 4 : ar - 1), ary_in = fs_int ? HH : (ar == 0 ? 3 : 0);
        int ex = arx_in, ey = ary_in; bool eabs = false, checked = true;
        if (sel && !(!ary_in && arx_in) && nrows && HH / nrows > 0 && w) {
            int oh = nrows * (HH / nrows), ht = 0, hi, dn;
            if (!ary_in) { int m = HW / w ? HW / w : 1; hi = w * m; oh = nrows * m; dn = HW; checked = false; }
            else {
                ht = (int)((long)oh * arx_in / ary_in); int m0 = ht / w ? ht / w : 1; hi = w * m0; dn = ht;
                if (hi > HW) { int m1 = HW / w ? HW / w : 1; hi = w * m1; oh = nrows * m1; dn = HW; }
            }
            const int wide = hi + w;
            const bool narrow = (((ht - hi) & 0xfff) <= ((wide - ht) & 0xfff)) || wide > HW;
            const int wres = hi == ht ? hi : wide;
            switch (sel) {
                case 2: ex = hi; break;
                case 3: ex = wres > HW ? hi : wres; break;
                case 4: ex = narrow ? hi : wres; break;
                default: ex = dn;
            }
            ey = oh; eabs = true;
        }
        const int gx = t->VIDEO_ARX & 0xfff, gy = t->VIDEO_ARY & 0xfff, gax = (t->VIDEO_ARX >> 12) & 1, gay = (t->VIDEO_ARY >> 12) & 1;
        printf("scale: Scale %d (SCALE %d) Aspect %d, picture %d rows of %d pixels, scaler %d x %d: core asks for %s%d x %s%d; rule gives %s%d x %s%d%s\n",
               menu, sel, ar, nrows, w, HW, HH, gax ? "" : "ratio ", gx, gay ? "" : "ratio ", gy, eabs ? "" : "ratio ", ex, eabs ? "" : "ratio ", ey,
               checked ? "" : " (not checked)");
        if (checked && (gx != ex || gy != ey || gax != (int)eabs || gay != (int)eabs)) { printf("  FAIL: the size asked of the scaler\n"); errors++; }
    }
    printf("%s: %u errors\n", errors ? "FAIL" : "PASS", errors);
    t->final();
    delete t;
    return errors ? 1 : 0;
}
