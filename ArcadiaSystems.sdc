derive_pll_clocks
derive_clock_uncertainty

# The PLL is built for PAL (113.500640 / 28.375160 MHz, Minimig's) and runs at NTSC, 0.92 % faster (ArcadiaSystems.sv
# reconfigures it): the periods shrink by 0.081 ns (counter 0, 8.811 ns) and 0.324 ns (counter 1, 35.24 ns). The setup
# checks get that as extra uncertainty, so they hold at the clock that runs.
set clk0 [get_clocks {emu|pll|pll_inst|altera_pll_i|cyclonev_pll|counter[0].output_counter|divclk}]
set clk1 [get_clocks {emu|pll|pll_inst|altera_pll_i|cyclonev_pll|counter[1].output_counter|divclk}]
set_clock_uncertainty -add -setup -from $clk0 -to $clk0 0.100
set_clock_uncertainty -add -setup -from $clk1 -to $clk0 0.100
set_clock_uncertainty -add -setup -from $clk1 -to $clk1 0.350
set_clock_uncertainty -add -setup -from $clk0 -to $clk1 0.350

# Minimig-AGA's constraints (Minimig.sdc) for the parts this core keeps: the 68000's and the chipset's paths into the SDRAM
# controller (clk_114, four times the machine clock) have two of its clocks.
set_multicycle_path -from {emu|cpu_inst*} -to {emu|ram*} -setup 2
set_multicycle_path -from {emu|cpu_inst*} -to {emu|ram*} -hold 1

set_multicycle_path -from {emu|amiga_clk|cck*} -to {emu|ram1|*} -setup 2
set_multicycle_path -from {emu|amiga_clk|cck*} -to {emu|ram1|*} -hold 1
set_multicycle_path -from {emu|minimig|*} -to {emu|ram1|*} -setup 2
set_multicycle_path -from {emu|minimig|*} -to {emu|ram1|*} -hold 1
set_multicycle_path -from {emu|amiga_clk|c1*} -to {emu|ram1|*} -setup 2
set_multicycle_path -from {emu|amiga_clk|c1*} -to {emu|ram1|*} -hold 1
set_multicycle_path -from {emu|amiga_clk|c3*} -to {emu|ram1|*} -setup 2
set_multicycle_path -from {emu|amiga_clk|c3*} -to {emu|ram1|*} -hold 1

set_false_path -from {emu|minimig|CPU1|halt}

# emu PLL cross-clock: counter[1] -> counter[0]
set_multicycle_path -setup 2 -from [get_clocks "emu|pll|pll_inst|altera_pll_i|cyclonev_pll|counter\[1\].output_counter|divclk"] -to [get_clocks "emu|pll|pll_inst|altera_pll_i|cyclonev_pll|counter\[0\].output_counter|divclk"]
set_multicycle_path -hold 1 -from [get_clocks "emu|pll|pll_inst|altera_pll_i|cyclonev_pll|counter\[1\].output_counter|divclk"] -to [get_clocks "emu|pll|pll_inst|altera_pll_i|cyclonev_pll|counter\[0\].output_counter|divclk"]

# as Minimig: not strictly right, but they help fitting (the 28 MHz pixel clock with the scandoubler effects)
set_multicycle_path -to {*Hq2x*} -setup 2
set_multicycle_path -to {*Hq2x*} -hold 1
set_multicycle_path -from [get_clocks { *|pll|pll_inst|altera_pll_i|*[0].*|divclk}] -to {ascal|*} -setup 2
set_multicycle_path -from [get_clocks { *|pll|pll_inst|altera_pll_i|*[0].*|divclk}] -to {ascal|*} -hold 1

if {[string equal "quartus_fit" $::TimeQuestInfo(nameofexecutable)]} {
	set_clock_uncertainty -add -setup -from [get_clocks {emu|pll|pll_inst|altera_pll_i|cyclonev_pll|counter[0].output_counter|divclk}] -to [get_clocks {emu|pll|pll_inst|altera_pll_i|cyclonev_pll|counter[0].output_counter|divclk}] 0.4
	set_clock_uncertainty -add -setup -from [get_clocks {emu|pll|pll_inst|altera_pll_i|cyclonev_pll|counter[1].output_counter|divclk}] -to [get_clocks {emu|pll|pll_inst|altera_pll_i|cyclonev_pll|counter[0].output_counter|divclk}] 0.4
	set_clock_uncertainty -add -setup -from [get_clocks {pll_hdmi|pll_hdmi_inst|altera_pll_i|cyclonev_pll|counter[0].output_counter|divclk}] -to [get_clocks {pll_hdmi|pll_hdmi_inst|altera_pll_i|cyclonev_pll|counter[0].output_counter|divclk}] 0.1
}
