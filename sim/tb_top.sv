//============================================================================
//
//  Arcadia Systems for MiSTer: the whole machine for Verilator (tb_arcadia.cpp).
//
//  What ArcadiaSystems.sv puts around arcadia_amiga, at the machine clock only: amiga_clk, the 68000 (fx68k) with its phase
//  enables, the ROM loader, and the chip memory as Minimig's original asynchronous SRAM (combinational read) in place of the
//  SDRAM controller. In the core the phase enables come from the 4x clock (ArcadiaSystems.sv); seen by the machine clock they
//  are one clock long, PHI2 in the clock after c1 rises and PHI1 two clocks later, which is what is made here.
//
//============================================================================

module tb_top
(
	input             clk,          // 28.636 MHz
	input             reset,        // the core's reset (power-on / OSD)

	// the ROM image, as hps_io's ioctl
	input             dl,
	input             dl_wr,
	input      [24:0] dl_addr,
	input       [7:0] dl_data,
	output            dl_busy,

	// controls, active high (MiSTer joystick bits 0 right, 1 left, 2 down, 3 up, 4 button 1, 5 button 2)
	input       [5:0] joy0,
	input       [5:0] joy1,
	input             coin1,
	input             coin2,
	input             start1,
	input             start2,
	input             service,
	input             dsw1_set,

	// video
	output      [7:0] r,
	output      [7:0] g,
	output      [7:0] b,
	output            hs_n,
	output            vs_n,
	output            hblank,
	output            vblank,
	output            pix_en,       // 14 MHz sample points (hires pixels)
	output            loaded,
	output            cpu_running,

	// audio
	output     [14:0] ldata,
	output     [14:0] rdata,

	// debug
	output     [23:1] dbg_addr,
	output            dbg_as_n,
	output            dbg_rw,
	output     [15:0] dbg_din,      // data into the 68000
	output     [15:0] dbg_dout,     // data out of the 68000
	output            dbg_dtack_n,
	output      [2:0] dbg_fc
);

//// amiga clocks ////
wire       clk7_en;
wire       clk7n_en;
wire       c1;
wire       c3;
wire       cck;
wire [9:0] eclk;

amiga_clk amiga_clk
(
	.clk_28   ( clk        ),
	.clk7_en  ( clk7_en    ),
	.clk7n_en ( clk7n_en   ),
	.c1       ( c1         ),
	.c3       ( c3         ),
	.cck      ( cck        ),
	.eclk     ( eclk       ),
	.reset_n  ( ~reset     )
);

assign pix_en = clk7_en | clk7n_en;

reg reset_d;
always @(posedge clk) begin
	reg [7:0] reset_s;
	reg rs;
	if (reset) reset_s <= '1;
	else begin
		reset_s <= reset_s << 1;
		rs <= reset_s[7];
		reset_d <= rs;
	end
end

//// the loader ////
wire        cpurst, cpuhlt, usrrst;
wire        host_cs, host_ack;
wire [23:1] host_adr;
wire [15:0] host_wdat;
wire        arc_argh;

arcadia_loader loader
(
	.clk(clk),
	.clk7_en(clk7_en),
	.download(dl),
	.rom_wr(dl_wr),
	.rom_addr(dl_addr),
	.rom_data(dl_data),
	.busy(dl_busy),
	.cpurst(cpurst),
	.cpuhlt(cpuhlt),
	.usrrst(usrrst),
	.host_cs(host_cs),
	.host_adr(host_adr),
	.host_wdat(host_wdat),
	.host_ack(host_ack),
	.argh(arc_argh),
	.loaded(loaded)
);

//// the 68000 ////
wire        cpu_rst;
wire        cpu_nrst_out;
reg         c1_d;
always @(posedge clk) c1_d <= c1;
wire        cpu_ph2 = cpu_rst &  c1 & ~c1_d;
wire        cpu_ph1 = cpu_rst & ~c1 &  c1_d;

assign cpu_running = cpu_rst;

wire  [2:0] chip_ipl;
wire        chip_dtack;
wire        chip_as;
wire        chip_uds;
wire        chip_lds;
wire        chip_rw;
wire [15:0] chip_dout;
wire [15:0] chip_din;
wire [23:1] chip_addr;
wire  [2:0] cpu_fc;

fx68k cpu_inst
(
	.clk(clk),
	.enPhi1(cpu_ph1),
	.enPhi2(cpu_ph2),
	.extReset(~cpu_rst),
	.pwrUp(~cpu_rst),
	.oRESETn(cpu_nrst_out),
	.HALTn(1'b1),
	.eRWn(chip_rw),
	.ASn(chip_as),
	.LDSn(chip_lds),
	.UDSn(chip_uds),
	.DTACKn(chip_dtack),
	.FC0(cpu_fc[0]),
	.FC1(cpu_fc[1]),
	.FC2(cpu_fc[2]),
	.VPAn(~&cpu_fc),
	.BERRn(1'b1),
	.BRn(1'b1),
	.BGACKn(1'b1),
	.IPL0n(chip_ipl[0]),
	.IPL1n(chip_ipl[1]),
	.IPL2n(chip_ipl[2]),
	.iEdb(chip_dout),
	.oEdb(chip_din),
	.eab(chip_addr),
	.oHALTEDn(),
	.E(),
	.VMAn(),
	.BGn()
);

assign dbg_addr    = chip_addr;
assign dbg_as_n    = chip_as;
assign dbg_rw      = chip_rw;
assign dbg_din     = chip_dout;
assign dbg_dout    = chip_din;
assign dbg_dtack_n = chip_dtack;
assign dbg_fc      = cpu_fc;

//// the chip memory: 8 MB, as the SRAM bridge addresses it ////
wire [15:0] ram_data;
wire [15:0] ramdata_in;
wire [23:1] ram_address;
wire        _ram_bhe, _ram_ble, _ram_we, _ram_oe;

reg  [15:0] mem [0:4194303] /* verilator public */;

// sdram_ctrl's timing, seen from the machine clock: it takes the chip bus (address, _oe / _we, byte selects, write data) in its
// state 0, half a machine clock after the first machine clock edge that sees c1 high, and its read register (chipRD) changes in
// state 9, seen from the third edge on; it holds until the next chip access. (Its clock is 4x the machine clock, its state 0
// follows c1's rise; sdram_ctrl.v.)
reg  [22:1] s_adr;
reg         s_rd, s_wr, s_bhe, s_ble;
reg  [15:0] s_wdat;
reg  [15:0] rd_q;
reg         c1_m1, c1_m2;

always @(posedge clk) begin
	c1_m1 <= c1;
	c1_m2 <= c1_m1;
	if (c1 && !c1_m1) begin
		s_adr  <= ram_address[22:1];
		s_rd   <= !_ram_oe && _ram_we;
		s_wr   <= !_ram_we;
		s_bhe  <= !_ram_bhe;
		s_ble  <= !_ram_ble;
		s_wdat <= ram_data;
	end
	if (c1_m1 && !c1_m2) begin
		if (s_rd) rd_q <= mem[s_adr];
		if (s_wr) begin
			if (s_bhe) mem[s_adr][15:8] <= s_wdat[15:8];
			if (s_ble) mem[s_adr][ 7:0] <= s_wdat[ 7:0];
		end
	end
end

assign ramdata_in = rd_q;

//// the machine ////
wire _hsync, _vsync;
wire field1, lace;
wire [1:0] res;
wire ntsc, pwr_led;

arcadia_amiga minimig
(
	.cpu_address  (chip_addr        ),
	.cpu_data     (chip_dout        ),
	.cpudata_in   (chip_din         ),
	._cpu_ipl     (chip_ipl         ),
	._cpu_as      (chip_as          ),
	._cpu_uds     (chip_uds         ),
	._cpu_lds     (chip_lds         ),
	.cpu_r_w      (chip_rw          ),
	._cpu_dtack   (chip_dtack       ),
	._cpu_reset   (cpu_rst          ),
	._cpu_reset_in(cpu_nrst_out     ),

	.ram_data     (ram_data         ),
	.ramdata_in   (ramdata_in       ),
	.ram_address  (ram_address      ),
	._ram_bhe     (_ram_bhe         ),
	._ram_ble     (_ram_ble         ),
	._ram_we      (_ram_we          ),
	._ram_oe      (_ram_oe          ),
	.chip48       (48'd0            ),

	.rst_ext      (reset_d          ),
	.clk          (clk              ),
	.clk7_en      (clk7_en          ),
	.clk7n_en     (clk7n_en         ),
	.c1           (c1               ),
	.c3           (c3               ),
	.cck          (cck              ),
	.eclk         (eclk             ),

	.cpurst       (cpurst           ),
	.cpuhlt       (cpuhlt           ),
	.usrrst       (usrrst           ),
	.host_cs      (host_cs          ),
	.host_adr     (host_adr         ),
	.host_we      (host_cs          ),
	.host_wdat    (host_wdat        ),
	.host_ack     (host_ack         ),

	.arc_argh     (arc_argh         ),
	.coin1        (coin1            ),
	.coin2        (coin2            ),
	.start1       (start1           ),
	.start2       (start2           ),
	.service      (service          ),
	.dsw1_set     (dsw1_set         ),
	.nv_addr      (14'd0            ),
	.nv_wr        (1'b0             ),
	.nv_din       (8'd0             ),
	.nv_dout      (                 ),
	.nv_written   (                 ),
	.nv_clear     (1'b0             ),

	._joy1        (~{10'd0, joy0}   ),
	._joy2        (~{10'd0, joy1}   ),
	.pwr_led      (pwr_led          ),

	._hsync       (_hsync           ),
	._vsync       (_vsync           ),
	.field1       (field1           ),
	.lace         (lace             ),
	.red          (r                ),
	.green        (g                ),
	.blue         (b                ),
	.hblank       (hblank           ),
	.vblank       (vblank           ),
	.res          (res              ),
	.ntsc         (ntsc             ),

	.ldata        (ldata            ),
	.rdata        (rdata            ),
	.ldata_okk    (                 ),
	.rdata_okk    (                 )
);

assign hs_n = _hsync;
assign vs_n = _vsync;

endmodule
