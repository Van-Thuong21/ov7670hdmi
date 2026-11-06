# Rang buoc timing cho Gowin
create_clock -name clk27 -period 37.037 -waveform {0 18.518} [get_ports {clk27}]
create_clock -name pclk  -period 37.037 -waveform {0 18.518} [get_ports {cam_pclk}]

# Khoi tao clock noi bo tu PLL va CLKDIV (dung wildcard * de tranh loi duong dan hierarchy)
create_clock -name clk_mem_hs -period 12.346 -waveform {0 6.173}  [get_nets {*clk_mem_hs*}]
create_clock -name ser_clk    -period 7.937  -waveform {0 3.968}  [get_nets {*ser_clk*}]
create_clock -name pix_clk    -period 39.683 -waveform {0 19.841} [get_nets {*pix_clk*}]

# Phân nhóm các miền clock bất đồng bộ
set_clock_groups -asynchronous -group [get_clocks {clk27}] -group [get_clocks {pclk}] -group [get_clocks {clk_mem_hs}] -group [get_clocks {ser_clk pix_clk}]