//============================================================================
//
//  Arcadia Systems for MiSTer: fast loading.
//
//  With address="0x32000000" on the MRA's <rom>, a Main_MiSTer that knows the attribute copies the assembled ROM image into the
//  DDR3 at that byte address in one go, and sends a download with no data bytes whose start address is the image's length
//  (support/arcade/mra_loader.cpp, rom_finish). When that download ends, this reads the image back from the DDR3 in 256-byte
//  bursts and hands it to rtl/arcadia_loader.v a byte at a time, as the ioctl port would, honouring the loader's busy. The loader
//  does the rest (the header, the unscrambling, the writes over the host bus), so a fast load leaves the machine exactly as a
//  streamed one. A Main_MiSTer that ignores the attribute streams the image as before (ioctl_addr is 0 at the start of such a
//  download), so one RBF and one set of MRAs serve both.
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 3 of the License, or (at your option)
//  any later version.
//
//============================================================================

module arcadia_fastload
(
	input             clk,
	input             go,             // a pulse: the image is in the DDR3
	input      [24:0] len,            // its length in bytes
	output reg        active = 1'b0,
	output reg        done = 1'b0,    // a pulse at the end

	// to the loader, as the ioctl port
	output reg        wr = 1'b0,
	output reg [24:0] addr = 25'd0,
	output reg  [7:0] data = 8'd0,
	input             busy,

	// the DDR3 (DDRAM_*), reads only
	input             ddr_busy,
	output      [7:0] ddr_burstcnt,
	output     [28:0] ddr_addr,
	output reg        ddr_rd = 1'b0,
	input      [63:0] ddr_dout,
	input             ddr_dout_ready
);

localparam [28:0] BASE = 29'h6400000;   // byte 0x32000000, in 64-bit words
localparam  [7:0] BURST = 8'd32;        // 256 bytes

reg  [23:0] blk = 24'd0;                // the burst being read: 256-byte blocks from BASE
assign ddr_addr     = BASE + {blk, 5'd0};
assign ddr_burstcnt = BURST;

// a burst's 32 words (one block RAM)
reg  [63:0] buffer [0:31];
reg  [63:0] q;
reg   [4:0] wbeat = 5'd0;
reg   [7:0] rbyte = 8'd0;               // the next byte of the block to hand over
always @(posedge clk) begin
	if (ddr_dout_ready) buffer[wbeat] <= ddr_dout;
	q <= buffer[rbyte[7:3]];
end

localparam S_IDLE = 3'd0, S_REQ = 3'd1, S_RECV = 3'd2, S_SEND = 3'd3, S_END = 3'd4;
reg   [2:0] state = S_IDLE;
reg         phase = 1'b0;               // S_SEND: 0 read the word, 1 hand over its byte
reg  [24:0] pos = 25'd0;                // the next byte's place in the image
reg  [24:0] left = 25'd0;               // bytes still to hand over

always @(posedge clk) begin
	wr   <= 1'b0;
	done <= 1'b0;

	case (state)
	S_IDLE:
		if (go) begin
			active <= 1'b1;
			blk    <= 24'd0;
			pos    <= 25'd0;
			left   <= len;
			state  <= len ? S_REQ : S_IDLE;
			done   <= !len;
			if (!len) active <= 1'b0;
		end

	S_REQ: begin
		// the read is presented until the DDR3 takes it (Avalon: held while busy)
		ddr_rd <= 1'b1;
		if (ddr_rd && !ddr_busy) begin
			ddr_rd <= 1'b0;
			wbeat  <= 5'd0;
			state  <= S_RECV;
		end
	end

	S_RECV:
		if (ddr_dout_ready) begin
			wbeat <= wbeat + 5'd1;
			if (wbeat == 5'd31) begin
				rbyte <= 8'd0;
				phase <= 1'b0;
				state <= S_SEND;
			end
		end

	S_SEND:
		// a byte every other clock at most, and only while the loader is not busy: it raises busy the clock after it takes the
		// second byte of a word (until the word has its SDRAM slot), which the clock in between lets this see
		if (!phase) begin
			if (!busy && !wr) phase <= 1'b1;        // q has buffer[rbyte[7:3]] from this clock on
		end
		else begin
			phase <= 1'b0;
			wr    <= 1'b1;
			data  <= q[{rbyte[2:0], 3'b000} +: 8];
			addr  <= pos;
			pos   <= pos + 25'd1;
			left  <= left - 25'd1;
			rbyte <= rbyte + 8'd1;
			if (left == 25'd1) state <= S_END;     // active stays up while the loader takes this last byte
			else if (rbyte == 8'd255) begin
				blk   <= blk + 24'd1;
				state <= S_REQ;
			end
		end
	S_END: begin
		active <= 1'b0;
		done   <= 1'b1;
		state  <= S_IDLE;
	end

	default: state <= S_IDLE;
	endcase
end

endmodule
