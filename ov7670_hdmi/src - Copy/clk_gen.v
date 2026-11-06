// =============================================================================
// clk_gen.v : tao clock tu thach anh 27 MHz (Tang Nano 9K, GW1NR-9)
//
//   PLL bo nho : 27 * 3 / 1      = 81 MHz   (VCO 648 MHz, ODIV 8)  -> memory_clk cua IP PSRAM
//   PLL HDMI   : 27 * 14 / 3     = 126 MHz  (VCO 504 MHz, ODIV 4)  -> ser_clk (5x pixel)
//   CLKDIV /5  : 126 / 5         = 25.2 MHz                        -> pix_clk (640x480@60Hz)
// =============================================================================
module clk_gen (
    input  wire clk27,
    output wire clk_mem_hs,
    output wire lock_mem,
    output wire ser_clk,
    output wire pix_clk,
    output wire lock_hdmi
);
    // ------------------------------------------------------------ 81 MHz
    rPLL u_pll_mem (
        .CLKOUT(clk_mem_hs), .LOCK(lock_mem), .CLKOUTP(), .CLKOUTD(), .CLKOUTD3(),
        .RESET(1'b0), .RESET_P(1'b0), .CLKIN(clk27), .CLKFB(1'b0),
        .FBDSEL(6'b000000), .IDSEL(6'b000000), .ODSEL(6'b000000),
        .PSDA(4'b0000), .DUTYDA(4'b0000), .FDLY(4'b0000)
    );
    defparam u_pll_mem.FCLKIN          = "27";
    defparam u_pll_mem.DYN_IDIV_SEL    = "false";
    defparam u_pll_mem.IDIV_SEL        = 0;
    defparam u_pll_mem.DYN_FBDIV_SEL   = "false";
    defparam u_pll_mem.FBDIV_SEL       = 2;
    defparam u_pll_mem.DYN_ODIV_SEL    = "false";
    defparam u_pll_mem.ODIV_SEL        = 8;
    defparam u_pll_mem.PSDA_SEL        = "0000";
    defparam u_pll_mem.DYN_DA_EN       = "false";
    defparam u_pll_mem.DUTYDA_SEL      = "1000";
    defparam u_pll_mem.CLKOUT_FT_DIR   = 1'b1;
    defparam u_pll_mem.CLKOUTP_FT_DIR  = 1'b1;
    defparam u_pll_mem.CLKOUT_DLY_STEP = 0;
    defparam u_pll_mem.CLKOUTP_DLY_STEP = 0;
    defparam u_pll_mem.CLKFB_SEL       = "internal";
    defparam u_pll_mem.CLKOUT_BYPASS   = "false";
    defparam u_pll_mem.CLKOUTP_BYPASS  = "false";
    defparam u_pll_mem.CLKOUTD_BYPASS  = "false";
    defparam u_pll_mem.DYN_SDIV_SEL    = 2;
    defparam u_pll_mem.CLKOUTD_SRC     = "CLKOUT";
    defparam u_pll_mem.CLKOUTD3_SRC    = "CLKOUT";
    defparam u_pll_mem.DEVICE          = "GW1NR-9C";

    // ------------------------------------------------------------ 126 MHz
    rPLL u_pll_hdmi (
        .CLKOUT(ser_clk), .LOCK(lock_hdmi), .CLKOUTP(), .CLKOUTD(), .CLKOUTD3(),
        .RESET(1'b0), .RESET_P(1'b0), .CLKIN(clk27), .CLKFB(1'b0),
        .FBDSEL(6'b000000), .IDSEL(6'b000000), .ODSEL(6'b000000),
        .PSDA(4'b0000), .DUTYDA(4'b0000), .FDLY(4'b0000)
    );
    defparam u_pll_hdmi.FCLKIN          = "27";
    defparam u_pll_hdmi.DYN_IDIV_SEL    = "false";
    defparam u_pll_hdmi.IDIV_SEL        = 2;
    defparam u_pll_hdmi.DYN_FBDIV_SEL   = "false";
    defparam u_pll_hdmi.FBDIV_SEL       = 13;
    defparam u_pll_hdmi.DYN_ODIV_SEL    = "false";
    defparam u_pll_hdmi.ODIV_SEL        = 4;
    defparam u_pll_hdmi.PSDA_SEL        = "0000";
    defparam u_pll_hdmi.DYN_DA_EN       = "false";
    defparam u_pll_hdmi.DUTYDA_SEL      = "1000";
    defparam u_pll_hdmi.CLKOUT_FT_DIR   = 1'b1;
    defparam u_pll_hdmi.CLKOUTP_FT_DIR  = 1'b1;
    defparam u_pll_hdmi.CLKOUT_DLY_STEP = 0;
    defparam u_pll_hdmi.CLKOUTP_DLY_STEP = 0;
    defparam u_pll_hdmi.CLKFB_SEL       = "internal";
    defparam u_pll_hdmi.CLKOUT_BYPASS   = "false";
    defparam u_pll_hdmi.CLKOUTP_BYPASS  = "false";
    defparam u_pll_hdmi.CLKOUTD_BYPASS  = "false";
    defparam u_pll_hdmi.DYN_SDIV_SEL    = 2;
    defparam u_pll_hdmi.CLKOUTD_SRC     = "CLKOUT";
    defparam u_pll_hdmi.CLKOUTD3_SRC    = "CLKOUT";
    defparam u_pll_hdmi.DEVICE          = "GW1NR-9C";

    // ------------------------------------------------------------ pix_clk = ser_clk / 5
    CLKDIV u_div5 (
        .HCLKIN(ser_clk), .RESETN(lock_hdmi), .CALIB(1'b0), .CLKOUT(pix_clk)
    );
    defparam u_div5.DIV_MODE = "5";
   
endmodule
