//============================================================================
//
//  Arcadia Systems for MiSTer: the parts of the Arcadia Multi Select that are not an Amiga 500.
//
//  Written from MAME 0.289's driver (src/mame/amiga/arsystems.cpp):
//   - the NVRAM ($9FC000-$9FFFFD; Aaargh: $9FF000-$9FFFFF), battery-backed, zero when new (DEFAULT_ALL_0)
//   - the ROM board switch at $9FFFFE (arcadia_multibios_change_game): 0 puts the board in at $800000, anything else takes it out
//   - CIA-A port B (the parallel port) as the coin / start / service / DIP input, with the two 2-bit coin counters:
//       bit 0 DSW1 (1 = Reset, the default; 0 = Set), 1 service, 2 start 2, 3 start 1 (all three active low),
//       5:4 coin 1 counter, 7:6 coin 2 counter.
//     A coin's rising edge adds one (up to 3). Each time the value the CIA drives on port B changes to one with bit 0 clear, one
//     coin is taken away, from coin 1 if it has any, otherwise from coin 2 (arcadia_cia_0_portb_w, called by MAME's mos6526 on
//     every change of its port B output).
//
//  The NVRAM's file side uses MAME's nvram file layout (little-endian words), so a file from MAME's nvram/<set>/nvram can be
//  copied to the MiSTer and back.
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 3 of the License, or (at your option)
//  any later version.
//
//============================================================================

module arcadia_board
(
	input             clk,
	input             hard_reset,   // power-on / OSD reset (not the 68000's RESET instruction)
	input             argh,         // Aaargh's map

	// CPU bus, selected by gary.v
	input             sel_nvram,
	input             sel_board,
	input      [13:1] address,
	input      [15:0] data_in,
	output     [15:0] data_out,
	input             rd,
	input             hwr,
	input             lwr,

	output reg        board_in = 1'b1,
	output reg        nv_written = 1'b0, // the CPU has written the NVRAM (cleared by nv_clear)
	input             nv_clear,

	// CIA-A port B
	input       [7:0] portb_drive,
	output      [7:0] portb_in,

	// controls, active high
	input             coin1,
	input             coin2,
	input             start1,
	input             start2,
	input             service,
	input             dsw1_set,

	// the NVRAM file (byte address, MAME's layout)
	input      [13:0] nv_addr,
	input             nv_wr,
	input       [7:0] nv_din,
	output      [7:0] nv_dout
);

//--------------------------------------------------------------------------------------
// NVRAM: 8K words as two byte-wide true dual-port RAMs (CPU / file)

// (Quartus's true dual-port template: a port that writes reads back the new data)
reg  [7:0] nv_hi [0:8191];
reg  [7:0] nv_lo [0:8191];

wire [12:0] cpu_idx = argh ? {2'b00, address[11:1]} : address[13:1];
reg   [7:0] cpu_q_hi, cpu_q_lo;

always @(posedge clk) begin
	if (sel_nvram && hwr) begin
		nv_hi[cpu_idx] <= data_in[15:8];
		cpu_q_hi <= data_in[15:8];
	end
	else cpu_q_hi <= nv_hi[cpu_idx];
end

always @(posedge clk) begin
	if (sel_nvram && lwr) begin
		nv_lo[cpu_idx] <= data_in[7:0];
		cpu_q_lo <= data_in[7:0];
	end
	else cpu_q_lo <= nv_lo[cpu_idx];
end

assign data_out = (sel_nvram && rd) ? {cpu_q_hi, cpu_q_lo} : 16'h0000;

// file side: byte 2n is word n's low byte, 2n+1 its high byte
reg   [7:0] f_q_hi, f_q_lo;
reg         f_odd;

always @(posedge clk) begin
	if (nv_wr && nv_addr[0]) begin
		nv_hi[nv_addr[13:1]] <= nv_din;
		f_q_hi <= nv_din;
	end
	else f_q_hi <= nv_hi[nv_addr[13:1]];
end

always @(posedge clk) begin
	if (nv_wr && !nv_addr[0]) begin
		nv_lo[nv_addr[13:1]] <= nv_din;
		f_q_lo <= nv_din;
	end
	else f_q_lo <= nv_lo[nv_addr[13:1]];
end

always @(posedge clk) f_odd <= nv_addr[0];

assign nv_dout = f_odd ? f_q_hi : f_q_lo;

always @(posedge clk) begin
	if (sel_nvram && (hwr || lwr)) nv_written <= 1'b1;
	else if (nv_clear)             nv_written <= 1'b0;
end

//--------------------------------------------------------------------------------------
// ROM board switch

always @(posedge clk) begin
	if (hard_reset)                    board_in <= 1'b1;
	else if (sel_board && (hwr || lwr)) board_in <= (data_in == 16'h0000);
end

//--------------------------------------------------------------------------------------
// coin counters

reg  [1:0] coin_cnt1, coin_cnt2;
reg        coin1_d, coin2_d;
reg  [7:0] pb_d;

wire       take = (portb_drive != pb_d) && !portb_drive[0];
reg  [1:0] n1, n2;

always @(*) begin
	n1 = coin_cnt1;
	n2 = coin_cnt2;
	if (take) begin
		if (n1 != 2'd0)      n1 = n1 - 2'd1;
		else if (n2 != 2'd0) n2 = n2 - 2'd1;
	end
	if (coin1 && !coin1_d && n1 != 2'd3) n1 = n1 + 2'd1;
	if (coin2 && !coin2_d && n2 != 2'd3) n2 = n2 + 2'd1;
end

always @(posedge clk) begin
	coin1_d <= coin1;
	coin2_d <= coin2;
	if (hard_reset) begin
		coin_cnt1 <= 2'd0;
		coin_cnt2 <= 2'd0;
		pb_d      <= 8'hFF;      // MAME's m_pb after reset
	end
	else begin
		coin_cnt1 <= n1;
		coin_cnt2 <= n2;
		pb_d      <= portb_drive;
	end
end

assign portb_in = {coin_cnt2, coin_cnt1, ~start1, ~start2, ~service, ~dsw1_set};

endmodule
