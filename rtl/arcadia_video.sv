//============================================================================
//
//  Arcadia Systems for MiSTer: the video output.
//
//  Minimig's picture (rtl/arcadia_amiga.v) to the framework: Minimig-AGA's video path (Minimig.sv: the pixel rate, the blanking
//  the scandoubler needs, video_mixer, video_freak) without its keyboard-driven screen adjustment, plus
//    - CRT Adjust (rmonic79's MiSTer-CRT-Adjust, modules/crt-adjust): the picture's size, horizontal position and vertical
//      position on a 15 kHz analog output, sync untouched;
//    - Scale with the framework's five integer scaling modes.
//
//  Clocks: Minimig's signals come on the machine clock (clk_sys, 28.64 MHz); everything here past them runs on the video clock
//  (clk_vid, twice that, from the same PLL).
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 3 of the License, or (at your option)
//  any later version.
//
//============================================================================

module arcadia_video #(parameter GAMMA = 1)
(
	input         clk_sys,
	input         clk_vid,

	// Minimig's picture
	input   [7:0] r,
	input   [7:0] g,
	input   [7:0] b,
	input         hs,                 // _hsync, active low
	input         vs,                 // _vsync, active low
	input         hblank,
	input         vbl,
	input   [1:0] res,                // the frame's resolution (bit 0 hires)
	input         lace,
	input         field1,

	// the OSD
	input   [2:0] fx,                 // Scandoubler Fx: None, HQ2x, CRT 25 / 50 / 75 %
	input         forced_scandoubler, // MiSTer.ini
	input   [1:0] ar,                 // Aspect ratio
	input   [2:0] scale,              // Scale: Normal, V-Integer, HV-Integer, Narrower HV-Integer, HV-Integer+
	input         crt_en,             // CRT Adjust
	input   [4:0] crt_hsize_osd,      // H-Size, as the OSD counts it
	input   [6:0] crt_hpos_osd,       // H-Position
	input   [4:0] crt_vshift_osd,     // V-Shift

	inout  [21:0] gamma_bus,
	input  [11:0] HDMI_WIDTH,
	input  [11:0] HDMI_HEIGHT,

	output        CE_PIXEL,
	output  [7:0] VGA_R,
	output  [7:0] VGA_G,
	output  [7:0] VGA_B,
	output        VGA_HS,
	output        VGA_VS,
	output        VGA_DE,
	output  [1:0] VGA_SL,
	output        VGA_F1,
	output [12:0] VIDEO_ARX,
	output [12:0] VIDEO_ARY
);

wire       scandoubler = (fx || forced_scandoubler) & ~lace;

//--------------------------------------------------------------------------------------
// blanking (Minimig.sv): the horizontal blank toggles on every line, vertical blank lines included, which the scandoubler needs
// for its line timing; the vertical blank is taken at the start of a line's picture

reg        hde;
reg        fhbl, fvbl, shbl, svbl;
wire       vde = ~(fvbl | svbl);
wire       vblank = vbl | ~vs;
wire       hbl = fhbl | shbl | ~hs;

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

// CRT Adjust takes a line's vertical blank at the line's hsync, before the picture starts and svbl / fvbl take their new
// values: vbn is what they will be (the same conditions, on the line count the hsync has just advanced)
wire       svbl_n = (vcnt == 0) ? 1'b1 : (vcnt == vend) ? 1'b0 : svbl;
wire       fvbl_n = (vcnt == vs_end+2'd2) ? 1'b0 : (vcnt == vmax-1'd1) ? 1'b1 : fvbl;
reg        vbn;

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
	vbn <= svbl_n | fvbl_n;
end

//--------------------------------------------------------------------------------------
// the pixel rate (Minimig.sv): 28 MHz (Minimig's dot) without the scandoubler, else the frame's own resolution, so the
// scandoubler's line holds one line: 7 MHz (lores) or 14 MHz (hires) from the previous frame's pixels. CRT Adjust takes 14 MHz
// (any OCS dot), which keeps a line (910 dots) inside its line buffer. The rate changes at the vertical sync.

reg        crt_on = 1'b0;         // CRT Adjust in use: on, and the scandoubler off (it is a 15 kHz adjustment)
reg        ce_out = 0;
always @(posedge clk_vid) begin
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
		crt_on <= crt_en & ~scandoubler;
		add <= 1; // 7MHz (CLK_VIDEO / 8)
		if(fs_res[0]) add <= 2; // 14MHz
		if(fs_res[1] | ~scandoubler) add <= 4; // 28MHz
		if(crt_en & ~scandoubler) add <= 2; // 14MHz
	end

	ce_out <= div[2] & !div[1:0];
end

//--------------------------------------------------------------------------------------
// CRT Adjust (modules/crt-adjust): the picture goes through a line buffer and is read out at another pixel rate (H-Size) and
// another place in the line (H-Position); the vertical sync is delayed by whole lines (V-Shift). The sync pulses keep their
// rate, so the monitor stays locked. Off, or with the scandoubler on, the picture takes the path it always had.
//
// The picture into it, three machine clocks later, so the vertical blank it takes at a line's hsync (vbn, from the line count
// the hsync advances) is already the new line's.

reg  [23:0] cq_rgb [0:2];
reg   [2:0] cq_hs, cq_vs, cq_hb;
always @(posedge clk_sys) begin
	cq_rgb[0] <= {r, g, b};  cq_rgb[1] <= cq_rgb[0]; cq_rgb[2] <= cq_rgb[1];
	cq_hs <= {cq_hs[1:0], ~hs};
	cq_vs <= {cq_vs[1:0], ~vs};
	cq_hb <= {cq_hb[1:0], ~hde};
end

// the OSD values, as the menu counts them: H-Size 0..+HS_POS then -HS_NEG..-1, H-Position in lores dots (two of the module's
// 14 MHz dots) 0..+HP_POS then -HP_NEG..-1, V-Shift signed 5-bit. A line is 7264 clocks of the 4x clock from hsync to hsync; a
// 320-dot picture usually starts about 93 lores dots after the hsync pulse starts (DIWSTRT $81) and ends about 41 before the next.
// A size step is 1/64 of a dot (five dots across 320): +6 still keeps such a picture inside the line; H-Position goes as far as
// the room on either side, past it the picture's edge is cut (by the hsync pulse on the left, the line's end on the right).
localparam             HS_POS = 6, HS_NEG = 16, HP_POS = 32, HP_NEG = 48;
localparam       [5:0] HS_WRAP = HS_POS + HS_NEG + 1;    // the number of H-Size entries
localparam       [7:0] HP_WRAP = HP_POS + HP_NEG + 1;    // the number of H-Position entries
localparam signed [9:0] CRT_HBIAS = -10'sd1;    // cancels the module's own one-dot delay of the picture
wire       [5:0] crt_hsz  = (crt_hsize_osd <= HS_POS) ? {1'b0, crt_hsize_osd} : {1'b0, crt_hsize_osd} - HS_WRAP;
wire       [7:0] crt_hp   = (crt_hpos_osd <= HP_POS)  ? {1'b0, crt_hpos_osd}  : {1'b0, crt_hpos_osd} - HP_WRAP;
wire signed [9:0] crt_hpos = {crt_hp[7], crt_hp, 1'b0};
// the picture is read a line after it is written, so the sync is delayed a line to keep its place; a positive V-Shift moves
// the picture down, which is the sync coming earlier
wire signed [6:0] crt_vs_t = 7'sd1 - $signed({crt_vshift_osd[4], crt_vshift_osd[4], crt_vshift_osd});
reg  signed [4:0] crt_hsize;
reg  signed [9:0] crt_hoff;
reg  signed [5:0] crt_voff;
always @(posedge clk_vid) if (ce_out) begin
	crt_hsize <= crt_hsz[4:0];
	crt_hoff  <= crt_hpos + CRT_HBIAS;
	crt_voff  <= crt_vs_t[5:0];
end

// the read enable: one every (64 + H-Size) sixteenths of a video clock (four clocks a 14 MHz dot), counted from the module's
// line reference
wire       crt_hs_ref;
reg        crt_hs_ref_d;
wire [8:0] crt_period = 9'd64 + {{4{crt_hsize[4]}}, crt_hsize};
reg  [8:0] crt_acc;
wire       crt_tick = (crt_acc + 9'd16) >= crt_period;
always @(posedge clk_vid) begin
	crt_hs_ref_d <= crt_hs_ref;
	if      (crt_hs_ref & ~crt_hs_ref_d) crt_acc <= 9'd0;
	else if (crt_tick)                   crt_acc <= crt_acc + 9'd16 - crt_period;
	else                                 crt_acc <= crt_acc + 9'd16;
end
wire       crt_rd_en = crt_on ? crt_tick : ce_out;

wire [7:0] crt_r, crt_g, crt_b;
wire       crt_hs, crt_vs, crt_hb, crt_vb_unused;
// a line is 227 colour clocks, 908 of these dots (Minimig leaves out NTSC's alternating 228); a frame 263 lines
crt_adjust #(.VTOTAL(263), .HTOTAL(912), .HPOS_MODE(1), .AW(11)) crt
(
	.clk(clk_vid), .pxl_cen(ce_out), .pxl2_cen(crt_rd_en), .active(crt_on),
	.hsize(crt_hsize), .hoffset(crt_hoff[8:0]), .voffset(crt_voff),
	.r_in(cq_rgb[2][23:16]), .g_in(cq_rgb[2][15:8]), .b_in(cq_rgb[2][7:0]),
	.hs_in(cq_hs[2]), .vs_in(cq_vs[2]), .hb_in(cq_hb[2]), .vb_in(vbn),
	.r_out(crt_r), .g_out(crt_g), .b_out(crt_b),
	.hs_out(crt_hs), .vs_out(crt_vs), .hb_out(crt_hb), .vb_out(crt_vb_unused),
	.hs_ref_out(crt_hs_ref)
);

//--------------------------------------------------------------------------------------
// the framework

video_mixer #(.LINE_LENGTH(2000), .HALF_DEPTH(0), .GAMMA(GAMMA)) video_mixer
(
	.CLK_VIDEO(clk_vid),
	.CE_PIXEL(CE_PIXEL),
	.ce_pix(crt_on ? crt_rd_en : ce_out),
	.scandoubler(scandoubler),
	.hq2x(fx==1),
	.gamma_bus(gamma_bus),
	.HDMI_FREEZE(1'b0),
	.freeze_sync(),

	.R(crt_on ? crt_r : r),
	.G(crt_on ? crt_g : g),
	.B(crt_on ? crt_b : b),
	.HSync(crt_on ? crt_hs : ~hs),
	.VSync(crt_on ? crt_vs : ~vs),
	.HBlank(crt_on ? (crt_hb | crt_hs) : ~hde),     // CRT Adjust: nothing of the picture inside the hsync pulse
	.VBlank(crt_on ? 1'b0 : ~vde),                  // CRT Adjust: the module's blank includes the vertical one

	.VGA_R(VGA_R),
	.VGA_G(VGA_G),
	.VGA_B(VGA_B),
	.VGA_VS(VGA_VS),
	.VGA_HS(VGA_HS),
	.VGA_DE(VGA_DE)
);

assign VGA_F1 = field1;

wire [2:0] sl = fx ? fx - 1'd1 : 3'd0;
assign VGA_SL = sl[1:0];

// Scale: the OSD's order to video_freak's (0 normal, 1 V-integer, 2 HV-integer-, 3 HV-integer+, 4 HV-integer)
wire [2:0] scale_sel = (scale == 3'd2) ? 3'd4 : (scale == 3'd3) ? 3'd2 : (scale == 3'd4) ? 3'd3 : (scale > 3'd4) ? 3'd0 : scale;
// Aspect ratio Full Screen (ARX = ARY = 0) makes video_freak size the height from the width, more rows than the screen has; with an
// integer Scale the screen's own width and height are given as the proportions instead (as the owner's Monster Maulers core does)
wire       fs_int = (ar == 2'd1) && (scale_sel != 3'd0) && (HDMI_WIDTH != 12'd0) && (HDMI_HEIGHT != 12'd0);

video_freak video_freak
(
	.CLK_VIDEO(clk_vid),
	.CE_PIXEL(CE_PIXEL),
	.VGA_VS(VGA_VS),
	.HDMI_WIDTH(HDMI_WIDTH),
	.HDMI_HEIGHT(HDMI_HEIGHT),
	.VGA_DE(),
	.VIDEO_ARX(VIDEO_ARX),
	.VIDEO_ARY(VIDEO_ARY),

	.VGA_DE_IN(VGA_DE),
	.ARX(fs_int ? HDMI_WIDTH  : (!ar) ? 12'd4 : {10'd0, ar - 2'd1}),
	.ARY(fs_int ? HDMI_HEIGHT : (!ar) ? 12'd3 : 12'd0),
	.CROP_SIZE(0),
	.CROP_OFF(0),
	.SCALE(scale_sel)
);

endmodule
