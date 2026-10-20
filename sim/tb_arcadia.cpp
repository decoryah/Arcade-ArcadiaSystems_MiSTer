// Arcadia Systems for MiSTer: the Verilator harness for sim/tb_top.sv.
//
//   tb_arcadia <image.rom> <frames> <out prefix> [options]
//     -snap N,M,...     write frames N, M, ... as <prefix>_NNNNN.ppm (frames count from the 68000 leaving reset)
//     -snapevery K      write every K-th frame
//     -sched FILE       scripted inputs: lines "<frame> <coin1|coin2|start1|start2|service|b1|b2|up|down|left|right|p2b1|...> <0|1>"
//     -bus A,B          log every 68000 bus cycle of frames A..B to <prefix>_bus.txt
//     -dsw              DSW1 1 set
//     -watch            log accesses to the Arcadia areas and CIA-A port B to <prefix>_watch.txt
//     -dumpchip N,M,..  write the 512 KB of chip RAM at frames N, M, ... as <prefix>_chip_N.bin (MAME's chip_N.bin layout)
//     -regs A,B         log the register bus (CPU and DMA writes to the custom chips, data registers left out) of frames
//                       A..B to <prefix>_regs.txt
//     -checkload        after the download, compare what the loader wrote with the layout computed here
//     -preload          put the ROMs straight into the memory (only the header goes through the loader): no download time
//
// The image is the MRA's (tools/arcadia_rom.py). Frames are the raw beam: 14 MHz samples (hires pixels) from hsync to hsync and
// lines from vsync to vsync, blanking included; tools/cmp_frame.py crops them to MAME's visible area.

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cstdint>
#include <string>
#include <vector>
#include <set>
#include <map>
#include "Vtb_top.h"
#include "Vtb_top___024root.h"
#include "Vtb_top_tb_top.h"
#include "verilated.h"

struct Ev { int frame; std::string sig; int val; };

static std::vector<uint8_t> read_file(const char *path) {
	std::vector<uint8_t> v;
	FILE *f = fopen(path, "rb");
	if (!f) { fprintf(stderr, "can't open %s\n", path); exit(1); }
	fseek(f, 0, SEEK_END); long n = ftell(f); fseek(f, 0, SEEK_SET);
	v.resize(n);
	if (fread(v.data(), 1, n, f) != (size_t)n) { fprintf(stderr, "short read %s\n", path); exit(1); }
	fclose(f);
	return v;
}

int main(int argc, char **argv) {
	Verilated::commandArgs(argc, argv);
	if (argc < 4) { fprintf(stderr, "usage: tb_arcadia <image> <frames> <prefix> [options]\n"); return 1; }
	std::vector<uint8_t> img = read_file(argv[1]);
	int frames = atoi(argv[2]);
	std::string prefix = argv[3];
	std::set<int> snaps;
	int snapevery = 0, bus_a = -1, bus_b = -1, regs_a = -1, regs_b = -1;
	bool dsw = false, watch = false, preload = false, checkload = false;
	std::set<int> dumps;
	std::vector<Ev> sched;
	for (int i = 4; i < argc; i++) {
		std::string a = argv[i];
		if (a == "-snap" && i + 1 < argc) {
			char *s = argv[++i];
			for (char *t = strtok(s, ","); t; t = strtok(nullptr, ",")) snaps.insert(atoi(t));
		} else if (a == "-snapevery" && i + 1 < argc) snapevery = atoi(argv[++i]);
		else if (a == "-bus" && i + 1 < argc) { sscanf(argv[++i], "%d,%d", &bus_a, &bus_b); }
		else if (a == "-dsw") dsw = true;
		else if (a == "-watch") watch = true;
		else if (a == "-preload") preload = true;
		else if (a == "-checkload") checkload = true;
		else if (a == "-regs" && i + 1 < argc) { sscanf(argv[++i], "%d,%d", &regs_a, &regs_b); }
		else if (a == "-dumpchip" && i + 1 < argc) {
			char *s = argv[++i];
			for (char *t = strtok(s, ","); t; t = strtok(nullptr, ",")) dumps.insert(atoi(t));
		}
		else if (a == "-sched" && i + 1 < argc) {
			FILE *f = fopen(argv[++i], "r");
			if (!f) { fprintf(stderr, "can't open %s\n", argv[i]); return 1; }
			char line[256];
			while (fgets(line, sizeof line, f)) {
				int fr, v; char sig[64];
				if (line[0] == '#') continue;
				if (sscanf(line, "%d %63s %d", &fr, sig, &v) == 3) sched.push_back({fr, sig, v});
			}
			fclose(f);
		}
	}

	Vtb_top *top = new Vtb_top;
	top->clk = 0; top->reset = 1; top->dl = 0; top->dl_wr = 0;
	top->joy0 = 0; top->joy1 = 0; top->coin1 = 0; top->coin2 = 0;
	top->start1 = 0; top->start2 = 0; top->service = 0; top->dsw1_set = dsw;

	uint64_t cyc = 0;
	auto tick = [&]() {
		top->clk = 1; top->eval();
		top->clk = 0; top->eval();
		cyc++;
	};

	for (int i = 0; i < 64; i++) tick();
	top->reset = 0;
	for (int i = 0; i < 64; i++) tick();

	// download, as hps_io: a byte, then wait for ioctl_wait to drop
	top->dl = 1;
	for (int i = 0; i < 16; i++) tick();
	auto &mem = top->rootp->tb_top->mem;
	// what rtl/arcadia_loader.v and gary.v make of the image, computed here independently: -preload writes it, -checkload
	// compares the loader's work with it
	auto layout = [&](auto put) {
		// in the SRAM bridge's space: Kickstart at $780000, the BIOS at $700000, the ROM board at $200000, the scrambled low
		// bytes fixed
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
	};
	if (preload) layout([&](uint32_t w, uint16_t v) { mem[w] = v; });
	for (size_t a = 0; a < (preload ? 16 : img.size()); a++) {
		while (top->dl_busy) tick();
		top->dl_addr = (uint32_t)a; top->dl_data = img[a]; top->dl_wr = 1;
		tick();
		top->dl_wr = 0;
		tick(); tick();
	}
	while (top->dl_busy) tick();
	for (int i = 0; i < 16; i++) tick();
	top->dl = 0;
	fprintf(stderr, "download done at cycle %llu\n", (unsigned long long)cyc);
	if (checkload) {
		uint32_t bad = 0, n = 0;
		layout([&](uint32_t w, uint16_t v) {
			n++;
			if (mem[w] != v) {
				if (bad < 10) fprintf(stderr, "  word %06x: loader %04x, expected %04x\n", w << 1, (unsigned)mem[w], v);
				bad++;
			}
		});
		fprintf(stderr, "checkload: %u of %u words differ\n", bad, n);
	}

	// run
	const int MAXW = 1024, MAXH = 320;
	std::vector<uint8_t> fb(MAXW * MAXH * 3), last(MAXW * MAXH * 3);
	int x = 0, y = 0, maxx = 0, lasth = 0, lastw = 0;
	int frame = -1;             // frames since the 68000 left reset
	int vframe = 0;             // all frames
	bool old_hs = true, old_vs = true;
	uint32_t last_fetch = 0, bus_cycles = 0;
	bool old_as = true;
	FILE *busf = nullptr;
	FILE *watchf = watch ? fopen((prefix + "_watch.txt").c_str(), "w") : nullptr;
	std::set<std::string> watched;
	uint32_t last_blk = 0xff;
	std::map<std::string, int> in;
	size_t si = 0;

	auto apply = [&]() {
		while (si < sched.size() && sched[si].frame <= frame) { in[sched[si].sig] = sched[si].val; si++; }
		top->coin1 = in["coin1"]; top->coin2 = in["coin2"];
		top->start1 = in["start1"]; top->start2 = in["start2"];
		top->service = in["service"];
		top->joy0 = (in["right"] << 0) | (in["left"] << 1) | (in["down"] << 2) | (in["up"] << 3) | (in["b1"] << 4) | (in["b2"] << 5);
		top->joy1 = (in["p2right"] << 0) | (in["p2left"] << 1) | (in["p2down"] << 2) | (in["p2up"] << 3) | (in["p2b1"] << 4) | (in["p2b2"] << 5);
	};

	auto write_ppm = [&](int n) {
		char name[512];
		snprintf(name, sizeof name, "%s_%05d.ppm", prefix.c_str(), n);
		FILE *f = fopen(name, "wb");
		if (!f) return;
		fprintf(f, "P6\n%d %d\n255\n", lastw, lasth);
		for (int yy = 0; yy < lasth; yy++) fwrite(&last[yy * MAXW * 3], 1, lastw * 3, f);
		fclose(f);
	};

	while (frame < frames) {
		tick();

		if (top->pix_en) {
			if (x < MAXW && y < MAXH) {
				uint8_t *p = &fb[(y * MAXW + x) * 3];
				p[0] = top->r; p[1] = top->g; p[2] = top->b;
			}
			x++;
		}
		bool hs = top->hs_n, vs = top->vs_n;
		if (old_hs && !hs) { if (x > maxx) maxx = x; x = 0; y++; }
		if (old_vs && !vs) {
			last.swap(fb);
			lasth = y < MAXH ? y : MAXH; lastw = maxx < MAXW ? maxx : MAXW;
			std::fill(fb.begin(), fb.end(), 0);
			y = 0; maxx = 0;
			vframe++;
			if (top->cpu_running) frame++;
			if (frame >= 0) {
				auto *t = top->rootp->tb_top;
				auto &clut = t->__PVT__minimig__DOT__DENISE1__DOT__clut0__DOT__clut__DOT__mem;
				fprintf(stderr, "frame %5d  pc~%06x  bus %u  clut %06x %06x %06x %06x  cop1 %04x%04x cop2 %04x%04x dmacon %04x\n", frame, last_fetch, bus_cycles,
				        (unsigned)clut[0] & 0xffffff, (unsigned)clut[1] & 0xffffff, (unsigned)clut[2] & 0xffffff, (unsigned)clut[3] & 0xffffff,
				        (unsigned)t->__PVT__minimig__DOT__AGNUS1__DOT__cp1__DOT__cop1lch, (unsigned)t->__PVT__minimig__DOT__AGNUS1__DOT__cp1__DOT__cop1lcl,
				        (unsigned)t->__PVT__minimig__DOT__AGNUS1__DOT__cp1__DOT__cop2lch, (unsigned)t->__PVT__minimig__DOT__AGNUS1__DOT__cp1__DOT__cop2lcl,
				        (unsigned)t->__PVT__minimig__DOT__AGNUS1__DOT__dmacon);
				if (snaps.count(frame) || (snapevery && frame % snapevery == 0)) write_ppm(frame);
				if (dumps.count(frame)) {
					char name[512];
					snprintf(name, sizeof name, "%s_chip_%d.bin", prefix.c_str(), frame);
					FILE *f = fopen(name, "wb");
					for (int i = 0; f && i < 0x40000; i++) { uint8_t b[2] = {(uint8_t)(mem[i] >> 8), (uint8_t)mem[i]}; fwrite(b, 1, 2, f); }
					if (f) fclose(f);
				}
				apply();
				if (frame == bus_a) {
					std::string n = prefix + "_bus.txt";
					busf = fopen(n.c_str(), "w");
				}
				if (busf && frame > bus_b) { fclose(busf); busf = nullptr; }
			}
			bus_cycles = 0;
		}
		old_hs = hs; old_vs = vs;

		// bus cycles: logged when DTACK comes with AS
		bool as = top->dbg_as_n;
		if (!as && old_as) {
			bus_cycles++;
			if ((top->dbg_fc & 3) == 2) last_fetch = top->dbg_addr << 1;
		}
		// watch (-watch): the Arcadia areas and CIA-A port B, each distinct access once, and the first program fetch of each
		// 64 KB block outside Kickstart in each frame
		if (watchf && !as && !top->dbg_dtack_n) {
			uint32_t a = top->dbg_addr << 1;
			bool fetch = (top->dbg_fc & 3) == 2;
			uint32_t d = top->dbg_rw ? top->dbg_din : top->dbg_dout;
			char key[64];
			if (fetch) {
				uint32_t blk = a >> 16;
				if (blk < 0xf8 && blk != last_blk) {
					snprintf(key, sizeof key, "F%d:%02x", frame, blk);
					if (!watched.count(key)) { watched.insert(key); fprintf(watchf, "f%d fetch %06x\n", frame, a); }
				}
				last_blk = blk;
			} else if ((a >= 0x9fc000 && a <= 0x9fffff) || (a >= 0xbfe100 && a <= 0xbfe3ff)) {
				snprintf(key, sizeof key, "%06x%c%04x", a, top->dbg_rw ? 'R' : 'W', d);
				if (!watched.count(key)) { watched.insert(key); fprintf(watchf, "f%d %c %06x=%04x pc~%06x\n", frame, top->dbg_rw ? 'R' : 'W', a, d, last_fetch); }
			}
		}
		if (busf && !as && !top->dbg_dtack_n && top->pix_en) {
			// one line per cycle at the first DTACK sample
			static uint32_t logged_addr = 0xffffffff; static uint64_t logged_cyc = 0;
			uint32_t a = top->dbg_addr << 1;
			if (a != logged_addr || cyc - logged_cyc > 8) {
				fprintf(busf, "%d %06x %c %04x fc%d\n", frame, a, top->dbg_rw ? 'R' : 'W',
				        top->dbg_rw ? top->dbg_din : top->dbg_dout, top->dbg_fc);
				logged_addr = a; logged_cyc = cyc;
			}
		}
		if (as) { }
		old_as = as;
		if (frame >= regs_a && frame <= regs_b) {
			static FILE *rf = nullptr;
			if (!rf) rf = fopen((prefix + "_regs.txt").c_str(), "w");
			auto *t = top->rootp->tb_top;
			// every clock around the copper's instruction fetches: a ring of the last 24 clocks, dumped when COPINS shows
			{
				static char ring[24][160]; static int rp = 0, after = 0;
				snprintf(ring[rp % 24], 160, "  cyc%llu cnt%d c1%d c3%d e7%d dbr%d reg%03x srd%d adr%06x rdq%04x rdo%04x cdi%04x",
				         (unsigned long long)cyc, (int)t->__PVT__amiga_clk__DOT__clk7_cnt, (int)t->__PVT__c1, (int)t->__PVT__c3,
				         (int)t->__PVT__amiga_clk__DOT__clk7_en_reg, (int)t->__PVT__minimig__DOT__dbr,
				         (unsigned)t->__PVT__minimig__DOT__reg_address << 1, (int)t->__PVT__s_rd,
				         (unsigned)t->__PVT__minimig__DOT__ram_address_out << 1, (unsigned)t->__PVT__rd_q,
				         (unsigned)t->__PVT__minimig__DOT__ram_data_out, (unsigned)t->__PVT__minimig__DOT__custom_data_in);
				rp++;
				if (((unsigned)t->__PVT__minimig__DOT__reg_address << 1) == 0x08c && after == 0) {
					fprintf(rf, "-- COPINS at f%d y%d x%d\n", frame, y, x);
					for (int k = 0; k < 24; k++) fprintf(rf, "%s\n", ring[(rp + k) % 24]);
					after = 24;
				} else if (after > 0) {
					fprintf(rf, "%s\n", ring[(rp - 1) % 24]);
					if (--after == 0) fprintf(rf, "--\n");
				}
			}
			if (t->__PVT__amiga_clk__DOT__clk7_en_reg) {
				unsigned r = (unsigned)t->__PVT__minimig__DOT__reg_address << 1;
				bool data = (r >= 0x110 && r <= 0x11e) || (r >= 0x140 && r <= 0x17e) || (r >= 0x0a0 && r <= 0x0da) || r == 0x1fe || r == 0x026;
				if (!data) fprintf(rf, "f%d y%d x%d %c %03x=%04x\n", frame, y, x, t->__PVT__minimig__DOT__dbr ? 'D' : 'C', r,
				                   (unsigned)t->__PVT__minimig__DOT__custom_data_in);
			}
		}
	}

	if (busf) fclose(busf);
	if (watchf) fclose(watchf);
	top->final();
	delete top;
	return 0;
}
