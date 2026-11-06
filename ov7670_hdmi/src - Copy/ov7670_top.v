// =============================================================================
// ov7670_top.v : OV7670 (640x480 RGB565) -> PSRAM (triple buffer) -> HDMI 640x480@60
//                Tang Nano 9K (GW1NR-LV9QN88PC6/I5)
//
//   Luong du lieu:
//     OV7670 --PCLK 13.5MHz--> ov7670_capture --> line_buf (2 dong, BSRAM)
//          --clk_mem 40.5MHz--> frame_store --> PSRAM (IP Gowin, 81 MHz) --> afifo64
//          --pix_clk 25.2MHz--> hdmi_scan --> video_proc (cho Sobel) --> hdmi_tx
//
//   S1 (btn_run , chan 4) : DONG BANG / tiep tuc  (dong bang = giu nguyen khung hien tai)
//   S2 (btn_mode, chan 3) : bat/tat color bar BEN TRONG cam bien OV7670
//
//   LED (active-low tren board; o day da dao san => 1 = sang):
//     LED0 : da nap xong thanh ghi camera
//     LED1 : cam bien tra ACK du (SCCB tot)
//     LED2 : thay PCLK nhap nhay
//     LED3 : thay VSYNC nhap nhay
//     LED4 : sang = PSRAM san sang + da co khung | nhap nhay nhanh = LOI (tran hang doi
//            ghi hoac FIFO HDMI can) | tat = PSRAM chua calib xong / chua co khung
//     LED5 : sang = dong bang | nhap nhay cham = color bar cam bien
//
//   Man hinh: neu chua co khung camera -> 8 thanh mau (kiem tra HDMI doc lap).
// =============================================================================
module ov7670_top (
    input  wire        clk27,
    input  wire        btn_run,
    input  wire        btn_mode,
    output wire [5:0]  led,

    // camera
    output wire        cam_xclk,
    output wire        cam_reset,
    output wire        cam_pwdn,
    output wire        cam_sioc,
    inout  wire        cam_siod,
    input  wire        cam_pclk,
    input  wire        cam_vsync,
    input  wire        cam_href,
    input  wire [7:0]  cam_d,

    // HDMI (DVI)
    output wire        tmds_clk_p,
    output wire        tmds_clk_n,
    output wire [2:0]  tmds_d_p,
    output wire [2:0]  tmds_d_n,

    // PSRAM tich hop trong goi (khong can IO_LOC)
    output wire [1:0]  O_psram_ck,
    output wire [1:0]  O_psram_ck_n,
    inout  wire [1:0]  IO_psram_rwds,
    output wire [1:0]  O_psram_reset_n,
    inout  wire [15:0] IO_psram_dq,
    output wire [1:0]  O_psram_cs_n
);
    parameter CLK_HZ    = 27_000_000;
    parameter [7:0] CLKRC_VAL = 8'h01;   // 0x01: PCLK 13.5 MHz (~17 fps) | 0x00: 27 MHz (~34 fps)

    // ----------------------------- reset khi cap nguon ------------------------------
    reg [15:0] por = 16'd0;
    wire rst_n = &por;
    always @(posedge clk27) if (!rst_n) por <= por + 16'd1;

    // ----------------------------- camera: clock + chan phu --------------------------
    assign cam_xclk  = clk27;            // 27 MHz
    assign cam_reset = 1'b1;
    assign cam_pwdn  = 1'b0;

    // ----------------------------- clock he thong -----------------------------------
    wire clk_mem_hs, lock_mem, ser_clk, pix_clk, lock_hdmi;
    clk_gen u_clk (
        .clk27(clk27),
        .clk_mem_hs(clk_mem_hs), .lock_mem(lock_mem),
        .ser_clk(ser_clk), .pix_clk(pix_clk), .lock_hdmi(lock_hdmi)
    );

    reg [1:0] prs = 2'b00;                // reset dong bo vao pix_clk
    always @(posedge pix_clk) prs <= {prs[0], rst_n & lock_hdmi};
    wire pix_rst_n = prs[1];

    // ----------------------------- nut bam ------------------------------------------
    wire run_p, mode_p;
    btn_ctrl u_btn_run  (.clk(clk27), .rst_n(rst_n), .btn_in(btn_run),  .pulse(run_p));
    btn_ctrl u_btn_mode (.clk(clk27), .rst_n(rst_n), .btn_in(btn_mode), .pulse(mode_p));

    reg freeze   = 1'b0;
    reg colorbar = 1'b0;
    always @(posedge clk27) begin
        if (!rst_n) begin
            freeze <= 1'b0; colorbar <= 1'b0;
        end else begin
            if (run_p)  freeze   <= ~freeze;
            if (mode_p) colorbar <= ~colorbar;
        end
    end

    // ----------------------------- cau hinh camera ----------------------------------
    wire cfg_done, ack_bad;
    ov7670_init #(.CLK_HZ(CLK_HZ), .CLKRC_VAL(CLKRC_VAL)) u_init (
        .clk(clk27), .rst_n(rst_n),
        .colorbar(colorbar),
        .done(cfg_done), .ack_bad(ack_bad),
        .sioc(cam_sioc), .siod(cam_siod)
    );

    // ----------------------------- thu hinh 640x480 ---------------------------------
    wire        lb_we;
    wire [8:0]  lb_waddr;
    wire [63:0] lb_wdata;
    wire        ln_tgl, frm_tgl;
    wire [8:0]  ln_y;

    ov7670_capture u_cap (
        .pclk(cam_pclk), .vsync(cam_vsync), .href(cam_href), .d(cam_d),
        .lb_we(lb_we), .lb_waddr(lb_waddr), .lb_wdata(lb_wdata),
        .ln_tgl(ln_tgl), .ln_y(ln_y), .frm_tgl(frm_tgl)
    );

    // ----------------------------- bo nho khung (PSRAM) -----------------------------
    wire        clk_mem, mem_ready, mem_err, have_any;
    wire        flush_req, f_ren, f_empty;
    wire [63:0] f_rdata;

    frame_store u_fs (
        .clk27(clk27), .mem_clk_hs(clk_mem_hs), .pll_lock(lock_mem), .rst_n(rst_n),
        .clk_mem(clk_mem), .mem_ready(mem_ready), .mem_err(mem_err), .have_any(have_any),

        .O_psram_ck(O_psram_ck), .O_psram_ck_n(O_psram_ck_n),
        .IO_psram_rwds(IO_psram_rwds), .O_psram_reset_n(O_psram_reset_n),
        .IO_psram_dq(IO_psram_dq), .O_psram_cs_n(O_psram_cs_n),

        .pclk(cam_pclk), .lb_we(lb_we), .lb_waddr(lb_waddr), .lb_wdata(lb_wdata),
        .ln_tgl(ln_tgl), .ln_y(ln_y), .freeze(freeze),

        .pix_clk(pix_clk), .pix_rst_n(pix_rst_n), .flush_req(flush_req),
        .f_ren(f_ren), .f_rdata(f_rdata), .f_empty(f_empty)
    );

    // ----------------------------- quet hinh + HDMI ---------------------------------
    wire [7:0] s_r, s_g, s_b, p_r, p_g, p_b;
    wire       s_hs, s_vs, s_de, p_hs, p_vs, p_de;
    wire       cam_on, underrun;

    hdmi_scan u_scan (
        .pix_clk(pix_clk), .rst_n(pix_rst_n),
        .have_any(have_any), .flush_req(flush_req),
        .f_ren(f_ren), .f_rdata(f_rdata), .f_empty(f_empty),
        .r(s_r), .g(s_g), .b(s_b), .hs(s_hs), .vs(s_vs), .de(s_de),
        .cam_on(cam_on), .underrun(underrun)
    );

    video_proc u_proc (
        .pix_clk(pix_clk), .rst_n(pix_rst_n), .sel(1'b0),
        .r_in(s_r), .g_in(s_g), .b_in(s_b), .hs_in(s_hs), .vs_in(s_vs), .de_in(s_de),
        .r_out(p_r), .g_out(p_g), .b_out(p_b), .hs_out(p_hs), .vs_out(p_vs), .de_out(p_de)
    );

    hdmi_tx u_tx (
        .pix_clk(pix_clk), .ser_clk(ser_clk), .rst_n(pix_rst_n),
        .r(p_r), .g(p_g), .b(p_b), .hs(p_hs), .vs(p_vs), .de(p_de),
        .tmds_clk_p(tmds_clk_p), .tmds_clk_n(tmds_clk_n),
        .tmds_d_p(tmds_d_p), .tmds_d_n(tmds_d_n)
    );

    // ----------------------------- LED chan doan ------------------------------------
    reg [2:0] pc_s = 3'd0, vs_s = 3'd0;
    always @(posedge clk27) begin
        pc_s <= {pc_s[1:0], cam_pclk};
        vs_s <= {vs_s[1:0], cam_vsync};
    end
    wire pc_tgl = pc_s[2] ^ pc_s[1];
    wire vs_tgl = vs_s[2] ^ vs_s[1];

    reg [21:0] pc_hold = 22'd0, vs_hold = 22'd0;     // keo dai ~155 ms
    always @(posedge clk27) begin
        if (pc_tgl)                pc_hold <= 22'h3FFFFF;
        else if (pc_hold != 22'd0) pc_hold <= pc_hold - 22'd1;
        if (vs_tgl)                vs_hold <= 22'h3FFFFF;
        else if (vs_hold != 22'd0) vs_hold <= vs_hold - 22'd1;
    end

    reg [1:0] rdy_s = 2'b00, hav_s = 2'b00, err_s = 2'b00, und_s = 2'b00;
    always @(posedge clk27) begin
        rdy_s <= {rdy_s[0], mem_ready};
        hav_s <= {hav_s[0], have_any};
        err_s <= {err_s[0], mem_err};
        und_s <= {und_s[0], underrun};
    end

    reg [25:0] blink = 26'd0;
    always @(posedge clk27) blink <= blink + 26'd1;

    wire fault = err_s[1] | und_s[1];
    wire led4  = fault ? blink[22] : (rdy_s[1] & hav_s[1]);
    wire led5  = freeze | (colorbar & blink[24]);

    wire [5:0] led_on = { led5, led4, (vs_hold != 22'd0), (pc_hold != 22'd0),
                          (cfg_done & ~ack_bad), cfg_done };
    assign led = ~led_on;                            // LED tren board sang khi muc 0
endmodule
