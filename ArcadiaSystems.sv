//============================================================================
//
//  Arcadia Systems (Arcadia Multi Select, Arcadia Systems / Mastertronic, 1987-1990) for MiSTer.
//
//  An Amiga 500 with a ROM cage on the expansion port, written from MAME 0.289's driver (src/mame/amiga/arsystems.cpp) on top of
//  Minimig-AGA_MiSTer (modules/minimig, see modules/VENDOR.md). This file is derived from Minimig-AGA's Minimig.sv (the MiSTer
//  glue, 2017-2020 Alexey Melnikov), cut down to the A500 with the 68000 (fx68k, Jorge Cwik), and the HPS boot protocol replaced
//  by an MRA ROM loader (rtl/arcadia_loader.v). docs/hardware.md has the details.
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 3 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//
//============================================================================

module emu
(
	`include "sys/emu_ports.vh"
);

///////// Default values for ports not used in this core /////////

assign ADC_BUS  = 'Z;
assign USER_OUT = '1;
assign {UART_RTS, UART_TXD, UART_DTR} = 0;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;
assign BUTTONS = 0;
assign VGA_DISABLE = 0;
assign VGA_SCALER  = 0;
assign HDMI_FREEZE = 0;
assign HDMI_BLACKOUT = 0;
assign HDMI_BOB_DEINT = 0;

assign {DDRAM_CLK, DDRAM_BURSTCNT, DDRAM_ADDR, DDRAM_RD, DDRAM_DIN, DDRAM_BE, DDRAM_WE} = 0;

assign LED_DISK  = 0;
assign AUDIO_S   = 1;

//////////////////////////////////////////////////////////////////

wire [127:0] status;
wire   [1:0] buttons;
wire         forced_scandoubler;
wire  [21:0] gamma_bus;

`include "build_id.v"
localparam CONF_STR = {
	"ArcadiaSystems;;",
	"-;",
	"O[2:1],Aspect ratio,Original,Full Screen,[ARC1],[ARC2];",
	"O[5:3],Scandoubler Fx,None,HQ2x,CRT 25%,CRT 50%,CRT 75%;",
	"O[8:6],Scale,Normal,V-Integer,Narrower HV-Integer,Wider HV-Integer;",
	"-;",
	"O[10:9],Audio filter,A500 (power LED),Off,On;",
	"O[12:11],Stereo mix,None,25%,50%,100%;",
	"-;",
	"O[13],DSW1 1,Reset,Set;",
	"-;",
	"O[14],Autosave NVRAM,On,Off;",
	"T[15],Save NVRAM;",
	"-;",
	"R[0],Reset;",
	"J1,Button 1,Button 2,Start,Coin,Service;",
	"jn,A,B,Start,Select,R;",
	"V,v",`BUILD_DATE
};

////////////////////   CLOCKS   ///////////////////

// Minimig's PLL (rtl/pll): outclk_0 4x the machine clock (SDRAM, CPU phases, video), outclk_1 the machine clock. It is
// built for PAL (28.375160 MHz) and reconfigured to NTSC (28.636 MHz, MAME's CLK_28M_NTSC) once the machine reports NTSC,
// which here is right after power-on, as Minimig does (only the fractional multiplier changes). The timing constraints
// add the 0.9 % (ArcadiaSystems.sdc).
wire clk_114;
wire clk_sys;
wire clk_vid;           // the video clock: 2x the machine clock (OCS pixels are at most 14 MHz, hires; the scandoubler wants 4x)
wire locked;
wire ntsc;

pll pll
(
	.refclk(CLK_50M),
	.outclk_0(clk_114),
	.outclk_1(clk_sys),
	.outclk_2(clk_vid),
	.reconfig_to_pll(reconfig_to_pll),
	.reconfig_from_pll(reconfig_from_pll),
	.locked(locked)
);

wire [63:0] reconfig_to_pll;
wire [63:0] reconfig_from_pll;
wire        cfg_waitrequest;
reg         cfg_write;
reg   [5:0] cfg_address;
reg  [31:0] cfg_data;

pll_cfg pll_cfg
(
	.mgmt_clk(CLK_50M),
	.mgmt_reset(0),
	.mgmt_waitrequest(cfg_waitrequest),
	.mgmt_read(0),
	.mgmt_readdata(),
	.mgmt_write(cfg_write),
	.mgmt_address(cfg_address),
	.mgmt_writedata(cfg_data),
	.reconfig_to_pll(reconfig_to_pll),
	.reconfig_from_pll(reconfig_from_pll)
);

always @(posedge CLK_50M) begin
	reg ntscd = 0, ntscd2 = 0;
	reg [2:0] state = 0;
	reg ntsc_r;

	ntscd <= ntsc;
	ntscd2 <= ntscd;

	cfg_write <= 0;
	if(ntscd2 == ntscd && ntscd2 != ntsc_r) begin
		state <= 1;
		ntsc_r <= ntscd2;
	end

	if(!cfg_waitrequest) begin
		if(state) state<=state+1'd1;
		case(state)
			1: begin
					cfg_address <= 0;
					cfg_data <= 0;
					cfg_write <= 1;
				end
			3: begin
					cfg_address <= 7;
					cfg_data <= ntsc_r ? 702807747 : 343817200;
					cfg_write <= 1;
				end
			5: begin
					cfg_address <= 2;
					cfg_data <= 0;
					cfg_write <= 1;
				end
		endcase
	end
end

wire reset = ~locked | buttons[1] | RESET | status[0];

reg reset_d;
always @(posedge clk_sys, posedge reset) begin
	reg [7:0] reset_s;
	reg rs;

	if(reset) reset_s <= '1;
	else begin
		reset_s <= reset_s << 1;
		rs <= reset_s[7];
		reset_d <= rs;
	end
end

//// amiga clocks ////
wire       clk7_en;
wire       clk7n_en;
wire       c1;
wire       c3;
wire       cck;
wire [9:0] eclk;

amiga_clk amiga_clk
(
	.clk_28   ( clk_sys    ), // input  clock c1 ( 28.687500MHz)
	.clk7_en  ( clk7_en    ), // output clock 7 enable (on 28MHz clock domain)
	.clk7n_en ( clk7n_en   ), // 7MHz negedge output clock enable (on 28MHz clock domain)
	.c1       ( c1         ), // clk28m clock domain signal synchronous with clk signal
	.c3       ( c3         ), // clk28m clock domain signal synchronous with clk signal delayed by 90 degrees
	.cck      ( cck        ), // colour clock output (3.54 MHz)
	.eclk     ( eclk       ), // 0.709379 MHz clock enable output (clk domain pulse)
	.reset_n  ( locked     )  // not the machine reset: the ROM loader's host bus runs on these enables
);

///////////////////////////////////////////////////

wire         ioctl_download;
wire         ioctl_wr;
wire  [15:0] ioctl_index;
wire  [26:0] ioctl_addr;
wire   [7:0] ioctl_dout;
wire         ioctl_upload;
wire   [7:0] ioctl_din;
wire         ld_busy;
reg          nv_req = 1'b0;
localparam [7:0] NV_INDEX = 8'd4;    // the NVRAM's file: the MRA's <nvram index="4" .../>

wire  [31:0] joystick_0, joystick_1;
wire  [10:0] ps2_key;

hps_io #(.CONF_STR(CONF_STR)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),
	.EXT_BUS(),

	.buttons(buttons),
	.status(status),
	.status_menumask(16'd0),
	.forced_scandoubler(forced_scandoubler),
	.gamma_bus(gamma_bus),

	.ioctl_download(ioctl_download),
	.ioctl_index(ioctl_index),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),
	.ioctl_wait(ld_busy),
	.ioctl_upload(ioctl_upload),
	.ioctl_upload_req(nv_req),
	.ioctl_upload_index(NV_INDEX),
	.ioctl_din(ioctl_din),
	.ioctl_rd(),

	.joystick_0(joystick_0),
	.joystick_1(joystick_1),
	.ps2_key(ps2_key)
);

///////////////////////   CONTROLS   ///////////////////////

// keyboard: 1 / 2 start, 5 / 6 coin, F2 service (MAME's defaults)
reg key_start1, key_start2, key_coin1, key_coin2, key_service;
always @(posedge clk_sys) begin
	reg old_stb;
	old_stb <= ps2_key[10];
	if (old_stb != ps2_key[10]) begin
		case (ps2_key[8:0])
			9'h016: key_start1  <= ps2_key[9];
			9'h01E: key_start2  <= ps2_key[9];
			9'h02E: key_coin1   <= ps2_key[9];
			9'h036: key_coin2   <= ps2_key[9];
			9'h006: key_service <= ps2_key[9];      // F2
			default: ;
		endcase
	end
end

// joystick bits: 0 right, 1 left, 2 down, 3 up, 4 button 1, 5 button 2, 6 start, 7 coin, 8 service (the J1 line above).
// Player 1 is the Amiga's game port 0 and player 2 port 1, as in MAME (p1_joy -> JOY0DAT, button 1 -> /FIR0, button 2 -> DATLY).
wire [15:0] _joy0 = ~{10'd0, joystick_0[5:0]};    // [fire2,fire,up,down,left,right], active low
wire [15:0] _joy1 = ~{10'd0, joystick_1[5:0]};
wire start1  = joystick_0[6] | key_start1;
wire start2  = joystick_1[6] | key_start2;
wire coin1   = joystick_0[7] | key_coin1;
wire coin2   = joystick_1[7] | key_coin2;
wire service = joystick_0[8] | joystick_1[8] | key_service;

///////////////////////   ROM LOADER   ///////////////////////

wire        rom_dl = ioctl_download && (ioctl_index[7:0] == 8'd0);
wire        cpurst, cpuhlt, usrrst;
wire        host_cs, host_ack;
wire [23:1] host_adr;
wire [15:0] host_wdat;
wire        arc_argh;
wire        loaded;

arcadia_loader loader
(
	.clk(clk_sys),
	.clk7_en(clk7_en),
	.download(ioctl_download),
	.rom_wr(rom_dl && ioctl_wr),
	.rom_addr(ioctl_addr[24:0]),
	.rom_data(ioctl_dout),
	.busy(ld_busy),
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

///////////////////////   NVRAM   ///////////////////////

// The NVRAM to the SD card: the MRA's <nvram index="4" size="16384"/> (Aaargh 4096). Main_MiSTer sends the saved file after the
// ROMs (the 68000 is held meanwhile, see arcadia_loader.v) and reads it back when the core asks (ioctl_upload_req): when the OSD
// opens after the game wrote its NVRAM (Autosave NVRAM On) and on Save NVRAM. The file is MAME's nvram/<set>/nvram.
wire        nv_dl = ioctl_download && (ioctl_index[7:0] == NV_INDEX);
wire        nv_ul = ioctl_upload && (ioctl_index[7:0] == NV_INDEX);
wire        nv_wr = nv_dl && ioctl_wr && (ioctl_addr[26:14] == 13'd0);
wire        nv_written;
reg         nv_ul_d = 1'b0, osd_d = 1'b0, save_d = 1'b0;
always @(posedge clk_sys) begin
	nv_ul_d <= nv_ul;
	osd_d   <= OSD_STATUS;
	save_d  <= status[15];
	nv_req  <= (nv_written && !status[14] && OSD_STATUS && !osd_d) || (status[15] && !save_d);
end
wire        nv_clear = rom_dl || nv_dl || (nv_ul && !nv_ul_d);

///////////////////////   68000   ///////////////////////

wire        cpu_rst;            // the machine's reset to the 68000, active low
wire        cpu_nrst_out;       // the 68000's RESET instruction, active low
reg         cpu_ph1;
reg         cpu_ph2;

always @(posedge clk_114) begin
	reg [3:0] div;
	reg       c1d;

	div <= div + 1'd1;

	c1d <= c1;
	if (~c1d & c1) div <= 3;

	if (~cpu_rst) begin
		cpu_ph1 <= 0;
		cpu_ph2 <= 0;
	end
	else begin
		if (div[1] & ~div[0]) begin
			cpu_ph1 <= 0;
			cpu_ph2 <= 0;
			case (div[3:2])
				0: cpu_ph2 <= 1;
				2: cpu_ph1 <= 1;
			endcase
		end
	end
end

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
	.clk(clk_sys),
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

	.VPAn(~&cpu_fc),            // autovectored interrupts
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

///////////////////////   SDRAM   ///////////////////////

wire [15:0] ram_data;      // sram data bus
wire [15:0] ramdata_in;    // sram data bus in
wire [47:0] chip48;        // big chip read
wire [23:1] ram_address;   // sram address bus
wire        _ram_bhe;      // sram upper byte select
wire        _ram_ble;      // sram lower byte select
wire        _ram_we;       // sram write enable
wire        _ram_oe;       // sram output enable

sdram_ctrl ram1
(
	.sysclk       (clk_114         ),
	.reset_n      (locked          ),   // not the machine reset: the ROMs stay
	.c_7m         (c1              ),

	.cache_rst    (cpu_rst         ),
	.cache_inhibit(1'b1            ),
	.cpu_cache_ctrl(4'd0           ),
	.dcache_sw_en (1'b0            ),

	.sd_data      (SDRAM_DQ        ),
	.sd_addr      (SDRAM_A         ),
	.sd_dqm       ({SDRAM_DQMH, SDRAM_DQML}),
	.sd_cs        (SDRAM_nCS       ),
	.sd_ba        (SDRAM_BA        ),
	.sd_we        (SDRAM_nWE       ),
	.sd_ras       (SDRAM_nRAS      ),
	.sd_cas       (SDRAM_nCAS      ),
	.sd_cke       (SDRAM_CKE       ),
	.sd_clk       (SDRAM_CLK       ),

	.cpuWR        (16'd0           ),
	.cpuAddr      (24'd0           ),
	.cpuU         (1'b1            ),
	.cpuL         (1'b1            ),
	.cpustate     (2'b01           ),
	.cpuCS        (1'b0            ),
	.cpuRD        (                ),
	.ramready     (                ),

	.chipWR       (ram_data        ),
	.chipAddr     ({1'b0, ram_address}),
	.chipU        (_ram_bhe        ),
	.chipL        (_ram_ble        ),
	.chipRW       (_ram_we         ),
	.chipDMA      (_ram_oe         ),
	.chipRD       (ramdata_in      ),
	.chip48       (chip48          ),
	.chip32       (1'b0            ),
	.chipWR2      (16'd0           ),
	.chipRD2      (                )
);

///////////////////////   THE MACHINE   ///////////////////////

wire [14:0] ldata;         // left DAC data
wire [14:0] rdata;         // right DAC data
wire  [8:0] ldata_okk;     // left DAC data  (PWM vol version)
wire  [8:0] rdata_okk;     // right DAC data (PWM vol version)
wire        vs;
wire        hs;
wire        pwr_led;
wire  [1:0] res;
wire  [7:0] r, g, b;
wire        lace, field1;
wire        hblank, vbl;
wire [13:0] nv_addr = ioctl_addr[13:0];

arcadia_amiga minimig
(
	//m68k pins
	.cpu_address  (chip_addr        ), // M68K address bus
	.cpu_data     (chip_dout        ), // M68K data bus
	.cpudata_in   (chip_din         ), // M68K data in
	._cpu_ipl     (chip_ipl         ), // M68K interrupt request
	._cpu_as      (chip_as          ), // M68K address strobe
	._cpu_uds     (chip_uds         ), // M68K upper data strobe
	._cpu_lds     (chip_lds         ), // M68K lower data strobe
	.cpu_r_w      (chip_rw          ), // M68K read / write
	._cpu_dtack   (chip_dtack       ), // M68K data acknowledge
	._cpu_reset   (cpu_rst          ), // M68K reset
	._cpu_reset_in(cpu_nrst_out     ), // M68K reset out

	//sram pins
	.ram_data     (ram_data         ), // SRAM data bus
	.ramdata_in   (ramdata_in       ), // SRAM data bus in
	.ram_address  (ram_address      ), // SRAM address bus
	._ram_bhe     (_ram_bhe         ), // SRAM upper byte select
	._ram_ble     (_ram_ble         ), // SRAM lower byte select
	._ram_we      (_ram_we          ), // SRAM write enable
	._ram_oe      (_ram_oe          ), // SRAM output enable
	.chip48       (chip48           ), // big chipram read

	//system  pins
	.rst_ext      (reset_d          ), // reset from ctrl block
	.clk          (clk_sys          ), // output clock c1 ( 28.687500MHz)
	.clk7_en      (clk7_en          ), // 7MHz clock enable
	.clk7n_en     (clk7n_en         ), // 7MHz negedge clock enable
	.c1           (c1               ), // clk28m clock domain signal synchronous with clk signal
	.c3           (c3               ), // clk28m clock domain signal synchronous with clk signal delayed by 90 degrees
	.cck          (cck              ), // colour clock output (3.54 MHz)
	.eclk         (eclk             ), // 0.709379 MHz clock enable output (clk domain pulse)

	//boot control and host bus
	.cpurst       (cpurst           ),
	.cpuhlt       (cpuhlt           ),
	.usrrst       (usrrst           ),
	.host_cs      (host_cs          ),
	.host_adr     (host_adr         ),
	.host_we      (host_cs          ),
	.host_wdat    (host_wdat        ),
	.host_ack     (host_ack         ),

	//Arcadia
	.arc_argh     (arc_argh         ),
	.coin1        (coin1            ),
	.coin2        (coin2            ),
	.start1       (start1           ),
	.start2       (start2           ),
	.service      (service          ),
	.dsw1_set     (status[13]       ),
	.nv_addr      (nv_addr          ),
	.nv_wr        (nv_wr            ),
	.nv_din       (ioctl_dout       ),
	.nv_dout      (ioctl_din        ),
	.nv_written   (nv_written       ),
	.nv_clear     (nv_clear         ),

	//I/O
	._joy1        (_joy0            ), // game port 0: player 1
	._joy2        (_joy1            ), // game port 1: player 2
	.pwr_led      (pwr_led          ), // power led

	//video
	._hsync       (hs               ), // horizontal sync
	._vsync       (vs               ), // vertical sync
	.field1       (field1           ),
	.lace         (lace             ),
	.red          (r                ), // red
	.green        (g                ), // green
	.blue         (b                ), // blue
	.hblank       (hblank           ),
	.vblank       (vbl              ),
	.res          (res              ),
	.ntsc         (ntsc             ),

	//audio
	.ldata        (ldata            ), // left DAC data
	.rdata        (rdata            ), // right DAC data
	.ldata_okk    (ldata_okk        ), // 9bit
	.rdata_okk    (rdata_okk        )  // 9bit
);

// power led control (Minimig)
reg [5:0] led_cnt;
reg led_dim;

always @ (posedge clk_sys) begin
  led_cnt <= led_cnt + 1'd1;
  led_dim <= |led_cnt[5:2];
end

assign LED_POWER = {1'b1, pwr_led | ~led_dim};
assign LED_USER  = ~loaded;

///////////////////////   VIDEO   ///////////////////////
// Minimig's video path, without its keyboard-driven screen adjustment

wire [2:0] fx = status[5:3];
wire       scandoubler = (fx || forced_scandoubler) & ~lace;
wire [7:0] R,G,B;

reg        hde;
reg        fhbl, fvbl, shbl, svbl;
wire       vde = ~(fvbl | svbl);
wire       vblank = vbl | ~vs;
wire       hbl = fhbl | shbl | ~hs;

reg ce_out = 0;
always @(posedge CLK_VIDEO) begin
	reg [2:0] div;
	reg [3:0] add;
	reg [1:0] fs_res;
	reg old_vs;

	div <= div + add;
	if(~hblank & ~vblank) fs_res <= fs_res | res;

	old_vs <= vs;
	if(old_vs & ~vs) begin
		fs_res <= 0;
		div <= 0;
		add <= 1; // 7MHz (CLK_VIDEO / 8)
		if(fs_res[0]) add <= 2; // 14MHz
		if(fs_res[1] | ~scandoubler) add <= 4; // 28MHz
	end

	ce_out <= div[2] & !div[1:0];
end

video_mixer #(.LINE_LENGTH(2000), .HALF_DEPTH(0), .GAMMA(1)) video_mixer
(
	.*,
	.hq2x(fx==1),
	.ce_pix(ce_out),
	.freeze_sync(),

	.R(r),
	.G(g),
	.B(b),
	.HSync(~hs),
	.VSync(~vs),
	.HBlank(~hde),
	.VBlank(~vde),

	.VGA_R(R),
	.VGA_G(G),
	.VGA_B(B)
);

assign CLK_VIDEO = clk_vid;
assign VGA_F1    = field1;
assign VGA_R     = R;
assign VGA_G     = G;
assign VGA_B     = B;

wire [1:0] ar = status[2:1];

video_freak video_freak
(
	.*,
	.VGA_DE_IN(VGA_DE),
	.VGA_DE(),
	.ARX((!ar) ? 12'd4 : (ar - 1'd1)),
	.ARY((!ar) ? 12'd3 : 12'd0),
	.CROP_SIZE(0),
	.CROP_OFF(0),
	.SCALE(status[8:6])
);

wire [2:0] sl = fx ? fx - 1'd1 : 3'd0;
assign VGA_SL = sl[1:0];

reg  [11:0] hsta, hend, hmax, hcnt;
always @(posedge clk_sys) begin
	reg old_hs;
	reg old_hblank;

	old_hs <= hs;
	old_hblank <= hblank;

	hcnt <= hcnt + 1'd1;
	if(~hs) hcnt <= 0;

	if(old_hblank & ~hblank) hend <= hcnt;
	if(~old_hblank & hblank) hsta <= hcnt;
	if(old_hs & ~hs)         hmax <= hcnt;

	if(hcnt == hend-2'd2) shbl <= 0;
	if(hcnt == hsta-2'd2) shbl <= 1;

	//force hblank
	if(hcnt == 8)         fhbl <= 0;
	if(hcnt == hmax-4'd8) fhbl <= 1;
end

reg [11:0] vend, vmax, vcnt, vs_end;
always @(posedge clk_sys) begin
	reg old_vs;
	reg old_vblank, old_hs, old_hbl;

	old_vs <= vs;
	old_hs <= hs;
	old_vblank <= vblank;

	if(old_hs & ~hs) vcnt <= vcnt + 1'd1;
	if(~old_vblank & vblank) vcnt <= 0;

	if(~lace | ~field1) begin
		if(old_vblank & ~vblank) vend <= vcnt;
		if(~old_vs & vs)         vs_end <= vcnt;
		if(~old_vblank & vblank) vmax <= vcnt;
	end

	old_hbl <= hbl;
	if((old_hbl & ~hbl) | !vcnt) begin
		if(vcnt == vend) svbl <= 0;
		if(vcnt == 0)    svbl <= 1;

		//force vblank
		if(vcnt == vmax-1)    fvbl <= 1;
		if(vcnt == vs_end+2)  fvbl <= 0;
	end

	hde <= ~hbl;
end

///////////////////////   AUDIO   ///////////////////////
// Minimig's A500 output: the fixed 4.4 kHz low pass, and the 3.3 kHz filter that follows the power LED (or forced off / on)

wire flt_en = (status[10:9] == 2'd0) ? pwr_led : (status[10:9] == 2'd2);

assign AUDIO_MIX = status[12:11];

wire [15:0] paula_smp_l = {ldata[14:0], 1'b0};
wire [15:0] paula_smp_r = {rdata[14:0], 1'b0};

// LPF 4400Hz, 1st order, 6db/oct
wire [15:0] lpf4400_l, lpf4400_r;
IIR_filter #(0) lpf4400
(
	.clk(clk_sys),
	.reset(reset),

	.ce(clk7_en | clk7n_en),
	.sample_ce(1),

	.cx (40'd4304835800),
	.cx0(1),
	.cx1(0),
	.cx2(0),
	.cy0(-2088941),
	.cy1(0),
	.cy2(0),

	.input_l(paula_smp_l),
	.input_r(paula_smp_r),
	.output_l(lpf4400_l),
	.output_r(lpf4400_r)
);

// LPF 3000Hz 1st + 3400Hz 1st
wire [15:0] lpf3275_l, lpf3275_r;
IIR_filter #(0) lpf3275
(
	.clk(clk_sys),
	.reset(reset),

	.ce(clk7_en | clk7n_en),
	.sample_ce(1),

	.cx (40'd8536629),
	.cx0(2),
	.cx1(1),
	.cx2(0),
	.cy0(-4182432),
	.cy1(2085297),
	.cy2(0),

	.input_l(lpf4400_l),
	.input_r(lpf4400_r),
	.output_l(lpf3275_l),
	.output_r(lpf3275_r)
);

reg [15:0] aud_l, aud_r;
always @(posedge CLK_AUDIO) begin
	reg [15:0] old_l0, old_l1, old_r0, old_r1;

	old_l0 <= flt_en ? lpf3275_l : lpf4400_l;
	old_l1 <= old_l0;
	if(old_l0 == old_l1) aud_l <= old_l1;

	old_r0 <= flt_en ? lpf3275_r : lpf4400_r;
	old_r1 <= old_r0;
	if(old_r0 == old_r1) aud_r <= old_r1;
end

assign AUDIO_L = aud_l;
assign AUDIO_R = aud_r;

endmodule
