//============================================================================
//
//  Arcadia Systems for MiSTer: the Amiga 500 of the Arcadia Multi Select with its ROM cage.
//
//  Derived from Minimig-AGA's rtl/minimig.v (modules/minimig, see modules/VENDOR.md), cut down to the machine MAME 0.289's
//  arsystems.cpp describes: 68000 (outside, see ArcadiaSystems.sv), OCS Agnus / Denise / Paula reporting the NTSC 8372 Agnus ID,
//  512 KB chip RAM, no slow or fast RAM, no floppy drives, no keyboard, no RTC, no IDE, no Action Replay; plus arcadia_board.v.
//  The configuration Minimig gets from the HPS (userio.v's UIO commands) is fixed here, and the host bus that Main_MiSTer uses to
//  write the Kickstart comes from the core's ROM loader (arcadia_loader.v) instead.
//
//  Minimig is Copyright 2006, 2007 Dennis van Weeren, with the later work of Jakub Bednarski, Sascha Boing, Rok Krajnc,
//  Alastair M. Robinson, Alexey Melnikov (Sorgelig) and the other contributors named in modules/minimig.
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 3 of the License, or (at your option)
//  any later version.
//
//============================================================================

module arcadia_amiga
(
	//m68k pins
	input  [23:1] cpu_address, // m68k address bus
	output [15:0] cpu_data,    // m68k data bus
	input  [15:0] cpudata_in,  // m68k data in
	output  [2:0] _cpu_ipl,    // m68k interrupt request
	input         _cpu_as,     // m68k address strobe
	input         _cpu_uds,    // m68k upper data strobe
	input         _cpu_lds,    // m68k lower data strobe
	input         cpu_r_w,     // m68k read / write
	output        _cpu_dtack,  // m68k data acknowledge
	output        _cpu_reset,  // m68k reset
	input         _cpu_reset_in,//m68k reset in

	//sram pins
	output [15:0] ram_data,    // sram data bus
	input  [15:0] ramdata_in,  // sram data bus in
	output [23:1] ram_address, // sram address bus
	output        _ram_bhe,    // sram upper byte select
	output        _ram_ble,    // sram lower byte select
	output        _ram_we,     // sram write enable
	output        _ram_oe,     // sram output enable
	input  [47:0] chip48,      // big chipram read

	//system pins
	input         rst_ext,     // reset from ctrl block
	input         clk,         // 28 MHz clock
	input         clk7_en,     // 7MHz clock enable
	input         clk7n_en,    // 7MHz negedge clock enable
	input         c1,          // clock enable signal
	input         c3,          // clock enable signal
	input         cck,         // colour clock enable
	input   [9:0] eclk,        // ECLK enable (1/10th of CLK)

	// boot control and host bus (arcadia_loader.v; Main_MiSTer's reset control and memory write commands in Minimig)
	input         cpurst,      // hold the 68000 in reset
	input         cpuhlt,      // halt the 68000 and give the bus to the host
	input         usrrst,      // reset the machine
	input         host_cs,
	input  [23:1] host_adr,
	input         host_we,
	input  [15:0] host_wdat,
	output        host_ack,

	// Arcadia
	input         arc_argh,    // Aaargh's memory map
	input         coin1,
	input         coin2,
	input         start1,
	input         start2,
	input         service,
	input         dsw1_set,
	input  [13:0] nv_addr,
	input         nv_wr,
	input   [7:0] nv_din,
	output  [7:0] nv_dout,
	output        nv_written,
	input         nv_clear,

	//I/O
	input  [15:0] _joy1,       // game port 0 [fire2,fire,up,down,left,right], active low (player 1)
	input  [15:0] _joy2,       // game port 1 (player 2)
	output        pwr_led,     // power led

	//video
	output        _hsync,      // horizontal sync
	output        _vsync,      // vertical sync
	output        field1,
	output        lace,
	output        hblank,
	output        vblank,
	output  [7:0] red,
	output  [7:0] green,
	output  [7:0] blue,
	output  [1:0] res,
	output reg    ntsc = 1'b1,

	//audio
	output [14:0] ldata,       // left DAC data
	output [14:0] rdata,       // right DAC data
	output  [8:0] ldata_okk,   // left DAC data  (PWM volume)
	output  [8:0] rdata_okk    // right DAC data (PWM volume)
);

// the fixed configuration (userio.v's UIO commands in Minimig)
localparam [5:0] CHIPSET_CONFIG = 6'b000_0_1_0;    // CDTV 0, AGA 0, ECS 0, A1000 0, NTSC 1, turbo 0
localparam [3:0] MEMORY_CONFIG  = 4'b00_00;        // slow RAM none, chip RAM 0.5 MB

//local signals for data bus
wire [15:0] cpu_data_in;		//cpu data bus in
wire [15:0] cpu_data_out;	   //cpu data bus out
wire [15:0] ram_data_in;		//ram data bus in
wire [15:0] ram_data_out;	   //ram data bus out
wire [15:0] custom_data_in;	//custom chips data bus in
wire [15:0] custom_data_out;	//custom chips data bus out
wire [15:0] agnus_data_out;	//agnus data out
wire [15:0] paula_data_out;	//paula data bus out
wire [15:0] denise_data_out;	//denise data bus out
wire [15:0] user_data_out;	   //user IO data out
wire [15:0] gary_data_out;	   //data out from memory bus multiplexer
wire [15:0] cia_data_out;	   //cia A+B data bus out
wire [15:0] arc_data_out;	   //Arcadia NVRAM data out

//local signals for address bus
wire [23:1] cpu_address_out;	//cpu address out
wire [20:1] dma_address_out;	//agnus address out
wire        bitplane_dma;
wire        bitplane_fetch_phase;
wire        bitplane_fetch_phase_valid;
wire        bitplane_fetch_unit_start;
wire [23:1] ram_address_out;	//ram address out

//local signals for control bus
wire        ram_rd;				//ram read enable
wire        ram_hwr;				//ram high byte write enable
wire        ram_lwr;				//ram low byte write enable
wire        cpu_rd; 				//cpu read enable
wire        rd_cyc;
wire        cpu_hwr;				//cpu high byte write enable
wire        cpu_lwr;				//cpu low byte write enable

//register address bus
wire  [8:1] reg_address; 		//main register address bus

//rest of local signals
wire        cpu_custom;
wire        dbr;					//data bus request, Agnus tells CPU that she is using the bus
wire        dbwe;					//data bus write enable, Agnus tells the RAM it's writing data
wire        dbs;					//data bus slow down, used for slowing down CPU access to chip, slow and custor register address space
wire        xbs;					//cross bridge access (memory and custom registers)
wire        _led;					//power led
wire  [3:0] sel_chip;			//chip ram select
wire  [2:0] sel_slow;			//slow ram select
wire        sel_kick;			//rom select
wire        sel_kick1mb;      // 1MB upper rom select
wire        sel_kick256kmirror;// mirror f8-fb to fc-ff in a1k mode
wire        sel_cia;				//CIA address space
wire        sel_reg;				//chip register select
wire        sel_cia_a;			//cia A select
wire        sel_cia_b;			//cia B select
wire        sel_arc;				//Arcadia ROM board / BIOS
wire        sel_arc_nvram;		//Arcadia NVRAM
wire        sel_arc_board;		//Arcadia ROM board switch
wire        arc_board_in;
wire        int2;					//intterrupt 2
wire        int3;					//intterrupt 3
wire        int6;					//intterrupt 6
wire        _fire0;				//joystick 1 fire signal to cia A
wire        _fire1;				//joystick 2 fire signal to cia A
wire        _fire0_dat;
wire        _fire1_dat;
wire  [3:0] audio_dmal;		   //audio dma data transfer request from Paula to Agnus
wire  [3:0] audio_dmas;		   //audio dma location pointer restart from Paula to Agnus
wire        disk_dmal;			//disk dma data transfer request from Paula to Agnus
wire        disk_dmas;			//disk dma special request from Paula to Agnus
wire        index;				//disk index interrupt
wire  [7:0] portb_drive;		//CIA-A port B as driven
wire  [7:0] portb_in;			//CIA-A port B pins

//local video signals
wire        sol;					//start of video line
wire        sof;					//start of video frame
wire        vbl_int;          // vertical blanking interrupt
wire        strhor_denise;		//horizontal strobe for Denise
wire        strhor_paula;		//horizontal strobe for Paula
wire  [8:0] htotal;			   //video line length (140ns units)
wire        harddis;
wire        varbeamen;

//local floppy signals (CIA<-->Paula)
wire        _step;				//step heads of disk
wire        direc;				//step heads direction
wire        _sel0;				//disk0 select
wire        _sel1;				//disk1 select
wire        _sel2;				//disk2 select
wire        _sel3;				//disk3 select
wire        side;					//upper/lower disk head
wire        _motor;				//disk motor control
wire        _track0;				//track zero detect
wire        _change;				//disk has been removed from drive
wire        _ready;				//disk is ready
wire        _wprot;				//disk is write-protected

wire        hde;

wire        bls;					//blitter slowdown - required for sharing bus cycles between Blitter and CPU

wire  [2:0] _iplx;			   //interrupt request lines from Paula

wire	[7:0] bank;					//memory bank select

wire        sys_reset;    		//reset output from minimig_syscontrol.v
wire        rom_readonly; 		//writeprotect $f8-ff in gary.v

wire        reset = sys_reset | ~_cpu_reset_in; // both the 68000 and minimig_syscontrol hold the reset signal for some clicks

reg         ovl;              //kickstart overlay enable
reg         _rst;             //68000 reset, active low

//--------------------------------------------------------------------------------------

assign pwr_led = ~_led;

// NTSC/PAL switching, as Minimig (the configuration is fixed to NTSC)
always @(posedge clk) if (clk7_en && reset) ntsc <= CHIPSET_CONFIG[1];

//--------------------------------------------------------------------------------------

wire 			floppy_speed;

//instantiate agnus
agnus AGNUS1
(
	.clk(clk),
	.clk7_en(clk7_en),
	.cck(cck),
	.reset(reset),
	.aen(sel_reg),
	.rd(cpu_rd),
	.hwr(cpu_hwr),
	.lwr(cpu_lwr),
	.data_in(custom_data_in),
	.data_out(agnus_data_out),
	.address_in(cpu_address_out[8:1]),
	.address_out(dma_address_out),
	.reg_address_out(reg_address),
	.bitplane_dma(bitplane_dma),
	.bitplane_fetch_phase(bitplane_fetch_phase),
	.bitplane_fetch_phase_valid(bitplane_fetch_phase_valid),
	.bitplane_fetch_unit_start(bitplane_fetch_unit_start),
	.cpu_custom(cpu_custom),
	.dbr(dbr),
	.dbwe(dbwe),
	._hsync(_hsync),
	._vsync(_vsync),
	._csync(),
	.hde(hde),
	.field1(field1),
	.lace(lace),
	.hblank(hblank),
	.vblank(vblank),
	.sol(sol),
	.sof(sof),
	.vbl_int(vbl_int),
	.strhor_denise(strhor_denise),
	.strhor_paula(strhor_paula),
	.htotal(htotal),
	.harddis(harddis),
	.varbeamen(varbeamen),
	.int3(int3),
	.audio_dmal(audio_dmal),
	.audio_dmas(audio_dmas),
	.disk_dmal(disk_dmal),
	.disk_dmas(disk_dmas),
	.bls(bls),
	.ntsc(ntsc),
	.a1k(CHIPSET_CONFIG[2]),
	.ecs(|CHIPSET_CONFIG[4:3]),
	.ecs_id(1'b1),
	.aga(CHIPSET_CONFIG[4]),
	.floppy_speed(floppy_speed)
);

//instantiate paula (no floppy drives: the selects are held off, as Minimig's floppy_disabled)
paula PAULA1
(
	.clk(clk),
	.clk7_en (clk7_en),
	.clk7n_en (clk7n_en),
	.cck(cck),
	.reset(reset),
	.reg_address_in(reg_address),
	.data_in(custom_data_in),
	.data_out(paula_data_out),
	.txd(),
	.rxd(1'b1),
	.ntsc(ntsc),
	.sof(sof),
	.strhor(strhor_paula),
	.vblint(vbl_int),
	.int2(int2),
	.int3(int3),
	.int6(int6),
	._ipl(_iplx),
	.audio_dmal(audio_dmal),
	.audio_dmas(audio_dmas),
	.disk_dmal(disk_dmal),
	.disk_dmas(disk_dmas),
	._step(_step),
	.direc(direc),
	._sel(4'b1111),
	.side(side),
	._motor(_motor),
	._track0(_track0),
	._change(_change),
	._ready(_ready),
	._wprot(_wprot),
	.index(index),
	.fdd_led(),
	.IO_ENA(1'b0),
	.IO_STROBE(1'b0),
	.IO_WAIT(),
	.IO_DIN(16'h0000),
	.IO_DOUT(),
	.ldata(ldata),
	.rdata(rdata),
	.ldata_okk(ldata_okk),
	.rdata_okk(rdata_okk),

	.floppy_drives(2'd0),
	.floppy_zero_active(1'b1),
	.floppy_ext_drive(12'd0),
	.floppy_speed_allowed(1'b0),
	.floppy_speed(floppy_speed),

	.enable_mister_floppy(1'b0),
	.trackdisp(),
	.secdisp(),
	.floppy_fwr(),
	.floppy_frd(),
	.mister_floppy_status(),
	.drive_snd(),

	.USER_IN(7'h7F),
	.USER_OUT()
);

//instantiate user IO (game ports and POTGO; its UIO command side is idle, no mouse)
userio USERIO1
(
	.clk(clk),
	.clk7_en(clk7_en),
	.reset(reset),
	.reg_address_in(reg_address),
	.data_in(custom_data_in),
	.data_out(user_data_out),
	.pot_cnt_en(sol & ~c1 & ~c3),
	._fire0(_fire0),
	._fire1(_fire1),
	._fire0_dat(_fire0_dat),
	._fire1_dat(_fire1_dat),
	// userio's game port 0 (JOY0DAT, /FIR0, POTGO DATLX/DATLY) takes its _joy2 input and port 1 its _joy1 (joy_swap off:
	// Minimig puts MiSTer's first joystick in the Amiga's joystick port). The Arcadia has player 1 in port 0 (MAME:
	// p1_joy -> joy_0_dat, button 1 -> /FIR0, button 2 -> DATLY), so this module's _joy1 (player 1) goes to userio's _joy2.
	._joy1(_joy2),
	._joy2(_joy1),
	.joy_ana1(16'h0000),
	.joy_ana2(16'h0000),
	.mouse_btn(3'b000),
	.kbd_mouse_type(2'd0),
	.kms_level(1'b0),
	.kbd_mouse_data(8'h00),
	.aud_mix(),
	.IO_ENA(1'b0),
	.IO_STROBE(1'b0),
	.IO_WAIT(),
	.IO_DIN(16'h0000),
	.memory_config(),
	.chipset_config(),
	.floppy_config(),
	.floppy_ext_drive(),
	.user_port_mode(),
	.scanline(),
	.ar(),
	.blver(),
	.ide_config(),
	.cpu_config(),
	.cache_config(),
	.bootrom(),
	.usrrst(),
	.cpurst(),
	.cpuhlt(),
	.host_cs(),
	.host_adr(),
	.host_we(),
	.host_bs(),
	.host_wdat(),
	.host_rdat(16'h0000),
	.host_ack(1'b0)
);

wire hires, shres;
assign res = {shres & |CHIPSET_CONFIG[4:3], hires};

//instantiate Denise
denise DENISE1
(
	.clk(clk),
	.clk7_en(clk7_en),
	.c1(c1),
	.c3(c3),
	.cck(cck),
	.reset(reset),
	.strhor(strhor_denise),
	.bitplane_dma(bitplane_dma),
	.bitplane_fetch_phase(bitplane_fetch_phase),
	.bitplane_fetch_phase_valid(bitplane_fetch_phase_valid),
	.bitplane_fetch_unit_start(bitplane_fetch_unit_start),
	.reg_address_in(reg_address),
	.data_in(custom_data_in),
	.chip48(chip48),
	.data_out(denise_data_out),
	.blank(~_hsync|vblank),
	.red(red),
	.green(green),
	.blue(blue),
	.a1k(CHIPSET_CONFIG[2]),
	.ecs(|CHIPSET_CONFIG[4:3]),
	.aga(CHIPSET_CONFIG[4]),
	.hires(hires),
	.shres(shres)
);

//instantiate cia A
wire [3:0] porta_out;
assign {_fire1_dat,_fire0_dat,_led} = porta_out[3:1];

ciaa CIAA1
(
	.clk(clk),
	.clk7_en(clk7_en),
	.clk7n_en(clk7n_en),
	.aen(sel_cia_a),
	.rd(cpu_rd),
	.wr(cpu_lwr|cpu_hwr),
	.reset(reset),
	.rs(cpu_address_out[11:8]),
	.data_in(cpu_data_out[7:0]),
	.data_out(cia_data_out[7:0]),
	.tick(_vsync),
	.eclk(eclk[8]),
	.cnt_in(1'b1),
	.irq(int2),
	.porta_in({_fire1,_fire0,_ready,_track0,_wprot,_change}),
	.porta_out(porta_out),
	.portb_in(portb_in),
	.portb_drive(portb_drive),
	.kbd_mouse_type(2'd0),
	.kms_level(1'b0),
	.kbd_mouse_data(8'h00),
	.freeze(),
	.hrtmon_en(1'b0)
);

//instantiate cia B
ciab CIAB1
(
	.clk(clk),
	.clk7_en(clk7_en),
	.aen(sel_cia_b),
	.rd(cpu_rd),
	.wr(cpu_hwr|cpu_lwr),
	.reset(reset),
	.rs(cpu_address_out[11:8]),
	.data_in(cpu_data_out[15:8]),
	.data_out(cia_data_out[15:8]),
	.tick(_hsync),
	.eclk(eclk[8]),
	.cnt_in(1'b1),
	.irq(int6),
	.flag(index),
	.porta_in(6'b111111),
	.porta_out(),
	.portb_out({_motor,_sel3,_sel2,_sel1,_sel0,side,direc,_step})
);

//instantiate cpu bridge
minimig_m68k_bridge CPU1
(
	.clk(clk),
	.clk7_en(clk7_en),
	.clk7n_en(clk7n_en),
	.c1(c1),
	.c3(c3),
	.cck(cck),
	.eclk(eclk),
	.vpa(sel_cia),
	.dbr(dbr),
	.dbs(dbs),
	.xbs(xbs),
	.nrdy(1'b0),
	.bls(bls),
	.memory_config(MEMORY_CONFIG),
	._as(_cpu_as),
	._lds(_cpu_lds),
	._uds(_cpu_uds),
	.r_w(cpu_r_w),
	.cpu_long(1'b0),
	.long_en(),
	._dtack(_cpu_dtack),
	.rd(cpu_rd),
	.rd_cyc(rd_cyc),
	.hwr(cpu_hwr),
	.lwr(cpu_lwr),
	.address(cpu_address),
	.address_out(cpu_address_out),
	.cpudatain(cpudata_in),
	.data(cpu_data),
	.data_out(cpu_data_out),
	.data_in(cpu_data_in),
	._cpu_reset (_cpu_reset),
	.cpu_halt (cpuhlt),
	.host_cs (host_cs),
	.host_adr (host_adr),
	.host_we (host_we),
	.host_bs (2'b11),
	.host_wdat (host_wdat),
	.host_rdat (),
	.host_ack (host_ack)
);

//instantiate RAM banks mapper
minimig_bankmapper BMAP1
(
	.chip0((~ovl|~cpu_rd|dbr|cpuhlt) & sel_chip[0]),
	.chip1(sel_chip[1]),
	.chip2(sel_chip[2]),
	.chip3(sel_chip[3]),
	.slow0(sel_slow[0]),
	.slow1(sel_slow[1]),
	.slow2(sel_slow[2]),
	.kick(sel_kick),
	.kick1mb(sel_kick1mb),
	.kick256kmirror(sel_kick256kmirror),
	.cart(1'b0),
	.arc(sel_arc),
	.memory_config(MEMORY_CONFIG[1:0]),
	.bank(bank)
);

//instantiate sram bridge
minimig_sram_bridge RAM1
(
	.clk(clk),
	.c1(c1),
	.c3(c3),
	.bank(bank),
	.address_in(ram_address_out),
	.data_in(ram_data_in),
	.data_out(ram_data_out),
	.rd(ram_rd),
	.hwr(ram_hwr),
	.lwr(ram_lwr),
	._bhe(_ram_bhe),
	._ble(_ram_ble),
	._we(_ram_we),
	._oe(_ram_oe),
	.address(ram_address[22:1]),
	.data(ram_data),
	.ramdata_in(ramdata_in)
);
assign ram_address[23] = 1'b0;

//level 7 interrupt for CPU (no Action Replay)
assign _cpu_ipl = _iplx;

//instantiate gary
gary GARY1
(
	.cpu_address_in(cpu_address_out),
	.dma_address_in(dma_address_out),
	.ram_address_out(ram_address_out),
	.cpu_data_out(cpu_data_out),
	.cpu_data_in(gary_data_out),
	.custom_data_out(custom_data_out),
	.custom_data_in(custom_data_in),
	.ram_data_out(ram_data_out),
	.ram_data_in(ram_data_in),
	.cpu_rd(cpu_rd),
	.cpu_hwr(cpu_hwr),
	.cpu_lwr(cpu_lwr),
	.cpu_hlt(cpuhlt),
	.ovl(ovl),
	.dbr(dbr),
	.dbwe(dbwe),
	.dbs(dbs),
	.xbs(xbs),
	.memory_config(MEMORY_CONFIG),
	.hdc_ena(1'b0),
	.toccata_ena(1'b0),
	.toccata_base(8'h00),
	.cdtv_base(8'h00),
	.a2065_ena(1'b0),
	.a2065_base(8'h00),
	.cdtv_mode(CHIPSET_CONFIG[5]),
	.arc_argh(arc_argh),
	.arc_board_in(arc_board_in),
	.sel_arc(sel_arc),
	.sel_arc_nvram(sel_arc_nvram),
	.sel_arc_board(sel_arc_board),
	.ram_rd(ram_rd),
	.ram_hwr(ram_hwr),
	.ram_lwr(ram_lwr),
	.ecs(|CHIPSET_CONFIG[4:3]),
	.a1k(CHIPSET_CONFIG[2]),
	.sel_chip(sel_chip),
	.sel_slow(sel_slow),
	.sel_kick(sel_kick),
	.sel_kick1mb(sel_kick1mb),
	.sel_kick256kmirror(sel_kick256kmirror),
	.sel_cia(sel_cia),
	.sel_reg(sel_reg),
	.sel_cia_a(sel_cia_a),
	.sel_cia_b(sel_cia_b),
	.sel_rtg(),
	.sel_rtc(),
	.sel_ide(),
	.sel_gayle(),
	.sel_toccata(),
	.sel_a2065(),
	.sel_cdtv(),
	.sel_cdtv_nvram(),
	.sel_cdtv_card(),
	.reset(reset),
	.clk(clk),
	.rom_readonly(rom_readonly),
	.bootrom(1'b0)
);

//instantiate the Arcadia board
arcadia_board ARCADIA1
(
	.clk(clk),
	.hard_reset(sys_reset),
	.argh(arc_argh),
	.sel_nvram(sel_arc_nvram),
	.sel_board(sel_arc_board),
	.address(cpu_address_out[13:1]),
	.data_in(cpu_data_out),
	.data_out(arc_data_out),
	.rd(cpu_rd),
	.hwr(cpu_hwr),
	.lwr(cpu_lwr),
	.board_in(arc_board_in),
	.nv_written(nv_written),
	.nv_clear(nv_clear),
	.portb_drive(portb_drive),
	.portb_in(portb_in),
	.coin1(coin1),
	.coin2(coin2),
	.start1(start1),
	.start2(start2),
	.service(service),
	.dsw1_set(dsw1_set),
	.nv_addr(nv_addr),
	.nv_wr(nv_wr),
	.nv_din(nv_din),
	.nv_dout(nv_dout)
);

//instantiate system control
minimig_syscontrol CONTROL1
(
	.clk(clk),
	.clk7_en(clk7_en),
	.cnt(sof),
	.mrst(usrrst | rst_ext),
	.reset(sys_reset)
);

always @(posedge clk) begin
	if(~_cpu_reset | ~_cpu_reset_in)       ovl <= 1;
	else if(sel_cia_a & (cpu_lwr|cpu_hwr)) ovl <= 0;
end

//-------------------------------------------------------------------------------------

//data multiplexer
assign cpu_data_in[15:0] = gary_data_out[15:0]
                         | cia_data_out[15:0]
                         | arc_data_out[15:0];

assign custom_data_out[15:0] = agnus_data_out[15:0]
                             | paula_data_out[15:0]
                             | denise_data_out[15:0]
                             | user_data_out[15:0];

//--------------------------------------------------------------------------------------

assign _cpu_reset = _rst;

always @(posedge clk) begin
	reg r;
	r <= ~(cpurst || sys_reset);
	_rst <= r;
end

endmodule
