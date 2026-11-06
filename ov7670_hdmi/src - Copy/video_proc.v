// =============================================================================
// video_proc.v : KHE CAM BO XU LY ANH (hien tai: di thang)
//
//   Dat giua hdmi_scan va hdmi_tx, chay trong mien pix_clk (25.2 MHz), luong pixel lien tuc
//   (de/hs/vs). Khi them Sobel:
//     - doi RGB888 -> xam (Y = (r + 2g + b) / 4)
//     - 2 line buffer 640 x 8 bit (2 BSRAM) + cua so 3x3, |Gx|+|Gy| -> nguong
//     - cac tin hieu hs/vs/de can tre dung bang do tre cua bo loc (1 dong + vai chu ky)
//   Tai nguyen con lai (xem bao cao tong hop): BSRAM con trong ~20 khoi.
//
//   Co the dung tin hieu 'sel' (vi du nut bam) de chon anh goc / anh sau xu ly.
// =============================================================================
module video_proc (
    input  wire       pix_clk,
    input  wire       rst_n,
    input  wire       sel,           // 0 = anh goc ; 1 = (sau nay) anh Sobel

    input  wire [7:0] r_in,
    input  wire [7:0] g_in,
    input  wire [7:0] b_in,
    input  wire       hs_in,
    input  wire       vs_in,
    input  wire       de_in,

    output wire [7:0] r_out,
    output wire [7:0] g_out,
    output wire [7:0] b_out,
    output wire       hs_out,
    output wire       vs_out,
    output wire       de_out
);
    // TODO(Sobel): thay doan duoi bang bo loc; hien tai chi di thang.
    assign r_out  = r_in;
    assign g_out  = g_in;
    assign b_out  = b_in;
    assign hs_out = hs_in;
    assign vs_out = vs_in;
    assign de_out = de_in;
endmodule
