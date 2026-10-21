// Bench stand-ins for what the MiSTer top level (ArcadiaSystems.sv) takes from Quartus IP and from Minimig's SDRAM controller.
`default_nettype none

// The PLL: the bench drives CLK_50M at the 4x clock (114.5 MHz), and the stub divides it, so the three clocks keep the real
// PLL's ratios and rising edges: outclk_0 4x, outclk_1 the machine clock (1x), outclk_2 the video clock (2x).
module pll (
    input  wire        refclk,
    input  wire        rst,
    output wire        outclk_0,
    output wire        outclk_1,
    output wire        outclk_2,
    input  wire [63:0] reconfig_to_pll,
    output wire [63:0] reconfig_from_pll,
    output reg         locked = 1'b0
);
    reg [1:0] div = 2'd0;
    reg [5:0] n = 6'd0;
    always @(posedge refclk) begin
        div <= div + 2'd1;
        if (n != 6'd63) n <= n + 6'd1;
        else locked <= 1'b1;
    end
    assign outclk_0 = refclk;
    assign outclk_1 = div[1];
    assign outclk_2 = div[0];
    assign reconfig_from_pll = 64'd0;
    /* verilator lint_off UNUSEDSIGNAL */
    wire unused = ^{rst, reconfig_to_pll};
    /* verilator lint_on UNUSEDSIGNAL */
endmodule

// The PLL's reconfiguration port: takes every write at once (the bench's clocks are NTSC from the start).
module pll_cfg (
    input  wire        mgmt_clk,
    input  wire        mgmt_reset,
    output wire        mgmt_waitrequest,
    input  wire        mgmt_read,
    output wire [31:0] mgmt_readdata,
    input  wire        mgmt_write,
    input  wire  [5:0] mgmt_address,
    input  wire [31:0] mgmt_writedata,
    output wire [63:0] reconfig_to_pll,
    input  wire [63:0] reconfig_from_pll
);
    assign mgmt_waitrequest = 1'b0;
    assign mgmt_readdata = 32'd0;
    assign reconfig_to_pll = 64'd0;
    /* verilator lint_off UNUSEDSIGNAL */
    wire unused = ^{mgmt_clk, mgmt_reset, mgmt_read, mgmt_write, mgmt_address, mgmt_writedata, reconfig_from_pll};
    /* verilator lint_on UNUSEDSIGNAL */
endmodule

// Minimig's SDRAM controller (modules/minimig/sdram_ctrl.v) at its chip port, with the memory behind it: the same 16-state cycle
// on the 4x clock, restarted by the rise of c_7m; the chip bus is taken in state 0 (a write lands then), and a read's data
// appears on chipRD in state 9, as the controller's own register does. The CPU port is unused in this core. 8 MB: the window the
// SRAM bridge addresses (chipAddr bits 22:1).
module sdram_ctrl (
    input  wire        sysclk,
    input  wire        c_7m,
    input  wire        reset_n,
    input  wire        cache_rst,
    input  wire        cache_inhibit,
    input  wire  [3:0] cpu_cache_ctrl,
    input  wire        dcache_sw_en,
    inout  wire [15:0] sd_data,
    output wire [12:0] sd_addr,
    output wire  [1:0] sd_ba,
    output wire        sd_cs,
    output wire        sd_we,
    output wire        sd_ras,
    output wire        sd_cas,
    output wire  [1:0] sd_dqm,
    output wire        sd_clk,
    output wire        sd_cke,
    input  wire [24:1] chipAddr,
    input  wire        chipL,
    input  wire        chipU,
    input  wire        chipRW,
    input  wire        chipDMA,
    input  wire [15:0] chipWR,
    output reg  [15:0] chipRD,
    output wire [47:0] chip48,
    input  wire        chip32,
    input  wire [15:0] chipWR2,
    output wire [15:0] chipRD2,
    input  wire [24:1] cpuAddr,
    input  wire        cpuCS,
    input  wire  [1:0] cpustate,
    input  wire        cpuL,
    input  wire        cpuU,
    input  wire [15:0] cpuWR,
    output wire [15:0] cpuRD,
    output wire        ramready
);
    reg  [15:0] mem [0:4194303] /*verilator public_flat_rw*/;

    reg   [3:0] sdram_state = 4'd0;
    reg         old_7m = 1'b0;
    reg  [22:1] adr;
    reg         rd = 1'b0;
    integer     writes /*verilator public_flat_rw*/ = 0;
    always @(posedge sysclk) begin
        sdram_state <= sdram_state + 4'd1;
        old_7m <= c_7m;
        if (~old_7m & c_7m) sdram_state <= 4'd0;

        if (sdram_state == 4'd0) begin
            rd <= 1'b0;
            if (~chipDMA | ~chipRW) begin
                adr <= chipAddr[22:1];
                rd  <= chipRW;
                if (!chipRW) begin
                    if (!chipU) mem[chipAddr[22:1]][15:8] <= chipWR[15:8];
                    if (!chipL) mem[chipAddr[22:1]][7:0]  <= chipWR[7:0];
                    writes <= writes + 1;
                end
            end
        end
        if (sdram_state == 4'd9 && rd) chipRD <= mem[adr];
    end

    assign chip48 = 48'd0;
    assign chipRD2 = 16'd0;
    assign cpuRD = 16'd0;
    assign ramready = 1'b1;
    assign sd_data = 16'hZZZZ;
    assign {sd_addr, sd_ba, sd_cs, sd_we, sd_ras, sd_cas, sd_dqm, sd_clk, sd_cke} = '0;
    /* verilator lint_off UNUSEDSIGNAL */
    wire unused = ^{reset_n, cache_rst, cache_inhibit, cpu_cache_ctrl, dcache_sw_en, chip32, chipWR2, cpuAddr, cpuCS, cpustate,
                    cpuL, cpuU, cpuWR, chipAddr[24:23]};
    /* verilator lint_on UNUSEDSIGNAL */
endmodule

`default_nettype wire
