// Simulation model of Minimig's denise_colortable_ram_mf (an altsyncram: dual port, 256 x 32 with byte enables, both ports on
// clock0 gated by clocken0, the read address registered, the output not, old data on a read during a write).
module denise_colortable_ram_mf
(
	input  [3:0] byteena_a,
	input        clock,
	input [31:0] data,
	input        enable,
	input  [7:0] rdaddress,
	input  [7:0] wraddress,
	input        wren,
	output [31:0] q
);

reg [31:0] mem [0:255];
reg [31:0] q_r;

always @(posedge clock) begin
	if (enable) begin
		if (wren) begin
			if (byteena_a[0]) mem[wraddress][ 7: 0] <= data[ 7: 0];
			if (byteena_a[1]) mem[wraddress][15: 8] <= data[15: 8];
			if (byteena_a[2]) mem[wraddress][23:16] <= data[23:16];
			if (byteena_a[3]) mem[wraddress][31:24] <= data[31:24];
		end
		q_r <= mem[rdaddress];
	end
end

assign q = q_r;

endmodule
