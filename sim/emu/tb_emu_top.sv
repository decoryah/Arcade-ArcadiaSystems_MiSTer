// The real MiSTer top level (ArcadiaSystems.sv's `emu`) with its framework and IP dependencies stubbed (hps_io_stub.sv, stubs.sv:
// the PLL, its reconfiguration port, Minimig's SDRAM controller with the memory behind it) and a behavioural Avalon DDR3 for fast
// loading. sim/emu/tb_emu.cpp plays the HPS: it loads the ROM image through the ioctl port or the DDR3, sets the OSD, and checks
// the video as the scaler gets it (VGA_*). After the owner's Rabbit core's sim/emu bench.
`default_nettype none
module tb_emu_top #(
    parameter int DDR_LAT      = 24,
    parameter int DDR_BUSY_PCT = 10
) (
    input  logic        CLK_50M,        // driven at the 4x clock (stubs.sv)
    input  logic        RESET,
    output logic        CLK_VIDEO, CE_PIXEL,
    output logic  [7:0] VGA_R, VGA_G, VGA_B,
    output logic        VGA_HS, VGA_VS, VGA_DE,
    output logic  [1:0] VGA_SL,
    output logic [15:0] AUDIO_L, AUDIO_R,
    output logic [12:0] VIDEO_ARX, VIDEO_ARY,
    input  logic [11:0] HDMI_WIDTH, HDMI_HEIGHT
);
    wire  [45:0] HPS_BUS;
    wire         VGA_F1, VGA_SCALER, VGA_DISABLE, HDMI_FREEZE, HDMI_BLACKOUT, HDMI_BOB_DEINT;
    wire   [1:0] LED_POWER, LED_DISK, BUTTONS, AUDIO_MIX;
    wire         LED_USER, AUDIO_S;
    wire   [3:0] ADC_BUS;
    wire         SD_SCK, SD_MOSI, SD_CS;
    wire         DDRAM_CLK, DDRAM_BUSY, DDRAM_DOUT_READY, DDRAM_RD, DDRAM_WE;
    wire   [7:0] DDRAM_BURSTCNT, DDRAM_BE;
    wire  [28:0] DDRAM_ADDR;
    wire  [63:0] DDRAM_DOUT, DDRAM_DIN;
    wire         SDRAM_CLK, SDRAM_CKE, SDRAM_DQML, SDRAM_DQMH, SDRAM_nCS, SDRAM_nCAS, SDRAM_nRAS, SDRAM_nWE;
    wire  [12:0] SDRAM_A; wire [1:0] SDRAM_BA; wire [15:0] SDRAM_DQ;
    wire         UART_RTS, UART_TXD, UART_DTR;
    wire   [6:0] USER_OUT;
    wire         CLK_AUDIO = 1'b0, SD_MISO = 1'b0, SD_CD = 1'b0, UART_CTS = 1'b0, UART_RXD = 1'b0, UART_DSR = 1'b0, OSD_STATUS = 1'b0;
    wire   [6:0] USER_IN = 7'h7f;

    emu u_emu (.*);

    ddr_model #(.AW(19), .LAT(DDR_LAT), .BUSY_PCT(DDR_BUSY_PCT)) ddr (
        .clk(DDRAM_CLK), .DDRAM_BUSY(DDRAM_BUSY), .DDRAM_BURSTCNT(DDRAM_BURSTCNT), .DDRAM_ADDR(DDRAM_ADDR),
        .DDRAM_DOUT(DDRAM_DOUT), .DDRAM_DOUT_READY(DDRAM_DOUT_READY),
        .DDRAM_RD(DDRAM_RD), .DDRAM_DIN(DDRAM_DIN), .DDRAM_BE(DDRAM_BE), .DDRAM_WE(DDRAM_WE)
    );
    /* verilator lint_off UNUSEDSIGNAL */
    wire unused = ^{VGA_F1, VGA_SCALER, VGA_DISABLE, HDMI_FREEZE, HDMI_BLACKOUT, HDMI_BOB_DEINT, LED_POWER, LED_DISK,
                    BUTTONS, AUDIO_MIX, LED_USER, AUDIO_S, ADC_BUS, SD_SCK, SD_MOSI, SD_CS, SDRAM_CLK, UART_RTS, UART_TXD, UART_DTR, USER_OUT,
                    SDRAM_CKE, SDRAM_DQML, SDRAM_DQMH, SDRAM_nCS, SDRAM_nCAS, SDRAM_nRAS, SDRAM_nWE, SDRAM_A, SDRAM_BA};
    /* verilator lint_on UNUSEDSIGNAL */
endmodule
`default_nettype wire
