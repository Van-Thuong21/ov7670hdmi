// =============================================================================
// hdmi_tx.v : phat DVI/HDMI (khong audio) tren Tang Nano 9K
//   3 encoder TMDS + 4 bo OSER10 (10:1 DDR) + ELVDS_OBUF (LVDS gia lap, 3.3V)
//   pix_clk = 25.2 MHz , ser_clk = 5 x pix_clk = 126 MHz (DDR -> 252 Mbps/10 = 10 bit/pixel)
//   Kenh 0 = xanh duong (+ hsync/vsync), kenh 1 = xanh la, kenh 2 = do
// =============================================================================
module hdmi_tx (
    input  wire       pix_clk,
    input  wire       ser_clk,
    input  wire       rst_n,          // muc thap = reset serializer

    input  wire [7:0] r,
    input  wire [7:0] g,
    input  wire [7:0] b,
    input  wire       hs,
    input  wire       vs,
    input  wire       de,

    output wire       tmds_clk_p,
    output wire       tmds_clk_n,
    output wire [2:0] tmds_d_p,
    output wire [2:0] tmds_d_n
);
    wire [9:0] q0, q1, q2;

    tmds_encoder u_e0 (.clk(pix_clk), .din(b), .c({vs, hs}), .de(de), .q(q0));
    tmds_encoder u_e1 (.clk(pix_clk), .din(g), .c(2'b00),    .de(de), .q(q1));
    tmds_encoder u_e2 (.clk(pix_clk), .din(r), .c(2'b00),    .de(de), .q(q2));

    wire [3:0] ser;
    wire       rst = ~rst_n;

    OSER10 u_o0 (.Q(ser[0]),
        .D0(q0[0]), .D1(q0[1]), .D2(q0[2]), .D3(q0[3]), .D4(q0[4]),
        .D5(q0[5]), .D6(q0[6]), .D7(q0[7]), .D8(q0[8]), .D9(q0[9]),
        .PCLK(pix_clk), .FCLK(ser_clk), .RESET(rst));
    OSER10 u_o1 (.Q(ser[1]),
        .D0(q1[0]), .D1(q1[1]), .D2(q1[2]), .D3(q1[3]), .D4(q1[4]),
        .D5(q1[5]), .D6(q1[6]), .D7(q1[7]), .D8(q1[8]), .D9(q1[9]),
        .PCLK(pix_clk), .FCLK(ser_clk), .RESET(rst));
    OSER10 u_o2 (.Q(ser[2]),
        .D0(q2[0]), .D1(q2[1]), .D2(q2[2]), .D3(q2[3]), .D4(q2[4]),
        .D5(q2[5]), .D6(q2[6]), .D7(q2[7]), .D8(q2[8]), .D9(q2[9]),
        .PCLK(pix_clk), .FCLK(ser_clk), .RESET(rst));
    // kenh clock: 5 bit 1 roi 5 bit 0 (gui bit D0 truoc)
    OSER10 u_oc (.Q(ser[3]),
        .D0(1'b1), .D1(1'b1), .D2(1'b1), .D3(1'b1), .D4(1'b1),
        .D5(1'b0), .D6(1'b0), .D7(1'b0), .D8(1'b0), .D9(1'b0),
        .PCLK(pix_clk), .FCLK(ser_clk), .RESET(rst));

    ELVDS_OBUF u_b0 (.I(ser[0]), .O(tmds_d_p[0]), .OB(tmds_d_n[0]));
    ELVDS_OBUF u_b1 (.I(ser[1]), .O(tmds_d_p[1]), .OB(tmds_d_n[1]));
    ELVDS_OBUF u_b2 (.I(ser[2]), .O(tmds_d_p[2]), .OB(tmds_d_n[2]));
    ELVDS_OBUF u_bc (.I(ser[3]), .O(tmds_clk_p),  .OB(tmds_clk_n));
endmodule
