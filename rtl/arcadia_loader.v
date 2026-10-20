//============================================================================
//
//  Arcadia Systems for MiSTer: the ROM loader.
//
//  Takes the MRA's ROM image (ioctl index 0) and writes it into the machine over Minimig's host bus with the 68000 halted, the
//  way Main_MiSTer uploads a Kickstart to Minimig, then lets the machine start.
//
//  Image layout (every MRA, see tools/make_mra.py):
//    $000000  16 bytes  header: bytes 0-7 the game's low-byte permutation (byte k = the scrambled bit that becomes bit 7-k),
//                       byte 8 flags (bit 0: Aaargh's memory map), bytes 9-15 zero
//    $000010  512 KB    Kickstart 1.3 (256 KB twice)            -> $F80000
//    $080010  512 KB    BIOS (MAME region user2)                 -> $F00000 (Gary also shows it at $980000)
//    $100010  1.5 MB    ROM board (MAME region user3)            -> $800000 (Gary keeps it at $200000 of the SDRAM)
//
//  Scrambling (MAME 0.289 arsystems.cpp, generic_decode): only the low byte of each word in the first 128 KB of a region:
//    - the ROM board, with the game's permutation from the header (the identity for unscrambled games);
//    - the BIOS, with 6,1,0,2,3,4,5,7, unless its first word reads $4AFC (TenPlay BIOSes are plain, OnePlay ones are not).
//
//  The 68000 is held in reset from power-on and during every download (the NVRAM file comes as a second download), and is let go
//  about 150 ms after the last one ends.
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 3 of the License, or (at your option)
//  any later version.
//
//============================================================================

module arcadia_loader
(
	input             clk,          // the machine clock (28 MHz)
	input             clk7_en,

	input             download,     // any ioctl download (ROM image or NVRAM file)
	input             rom_wr,       // ioctl_wr of the ROM image
	input      [24:0] rom_addr,
	input       [7:0] rom_data,
	output            busy,         // ioctl_wait

	// the machine
	output reg        cpurst = 1'b1,
	output reg        cpuhlt = 1'b1,
	output reg        usrrst = 1'b0,
	output reg        host_cs = 1'b0,
	output reg [23:1] host_adr = 23'd0,
	output reg [15:0] host_wdat = 16'd0,
	input             host_ack,

	output reg        argh = 1'b0,
	output reg        loaded = 1'b0
);

//--------------------------------------------------------------------------------------
// header and scrambling

reg  [2:0] perm [0:7];          // perm[k]: the source bit of plain bit 7-k
reg        bios_scr = 1'b0;     // the BIOS is scrambled (decided by its first word)
reg  [7:0] hi;                  // even byte of the current word

wire        in_img  = rom_addr >= 25'h10 && rom_addr < 25'h280010;
wire [21:0] off     = rom_addr[21:0] - 22'h10;   // offset in the image after the header
wire        is_kick = off < 22'h080000;
wire        is_bios = !is_kick && off < 22'h100000;
wire [21:0] boff    = off - 22'h080000;
wire [21:0] goff    = off - 22'h100000;

function [7:0] unscramble(input [7:0] d, input [2:0] s7, input [2:0] s6, input [2:0] s5, input [2:0] s4,
                          input [2:0] s3, input [2:0] s2, input [2:0] s1, input [2:0] s0);
	unscramble = {d[s7], d[s6], d[s5], d[s4], d[s3], d[s2], d[s1], d[s0]};
endfunction

wire        first_bios_word = is_bios && boff[21:1] == 21'd0;
wire        bios_scr_now    = first_bios_word ? ({hi, rom_data} != 16'h4AFC) : bios_scr;
wire  [7:0] lo_plain = (!is_kick && !is_bios && goff < 22'h020000) ?
                           unscramble(rom_data, perm[0], perm[1], perm[2], perm[3], perm[4], perm[5], perm[6], perm[7]) :
                       (is_bios && boff < 22'h020000 && bios_scr_now) ?
                           unscramble(rom_data, 3'd6, 3'd1, 3'd0, 3'd2, 3'd3, 3'd4, 3'd5, 3'd7) :
                           rom_data;
wire [23:1] target   = is_kick ? {5'b1111_1, off[18:1]} :
                       is_bios ? {5'b1111_0, boff[18:1]} :
                                 {3'b100, goff[20:1]};

//--------------------------------------------------------------------------------------
// host bus writes (as userio.v does for Main_MiSTer's memory write command)

reg mrx = 1'b0;                 // a word is waiting for the bus
reg pending = 1'b0;             // ... or still in flight
reg old_ack = 1'b0;

assign busy = pending;

always @(posedge clk) begin
	old_ack <= host_ack;
	if (old_ack && !host_ack) pending <= 1'b0;

	if (clk7_en) begin
		host_cs <= mrx;
		if (host_ack) mrx <= 1'b0;
	end

	if (rom_wr) begin
		if (rom_addr < 25'h10) begin
			if (rom_addr[3] == 1'b0) perm[rom_addr[2:0]] <= rom_data[2:0];
			if (rom_addr[3:0] == 4'h8) argh <= rom_data[0];
		end
		else if (in_img) begin
			if (!off[0]) hi <= rom_data;
			else begin
				if (first_bios_word) bios_scr <= bios_scr_now;
				host_adr  <= target;
				host_wdat <= {hi, lo_plain};
				mrx       <= 1'b1;
				pending   <= 1'b1;
			end
		end
	end
end

//--------------------------------------------------------------------------------------
// boot control (Main_MiSTer's reset control command in Minimig: halt + reset while writing, then a machine reset)

reg [22:0] hold = 23'd0;        // time since the last download ended
reg        dl_d = 1'b0;

always @(posedge clk) begin
	dl_d <= download;
	usrrst <= 1'b0;
	if (download) begin
		cpurst <= 1'b1;
		cpuhlt <= 1'b1;
		hold   <= 23'd0;
		if (!dl_d) loaded <= 1'b0;
	end
	else if (cpuhlt && !pending) begin
		if (dl_d) loaded <= 1'b1;
		if (loaded) begin
			if (!hold[22]) hold <= hold + 23'd1;
			else begin
				cpuhlt <= 1'b0;
				cpurst <= 1'b0;
				usrrst <= 1'b1;
			end
		end
	end
end

endmodule
