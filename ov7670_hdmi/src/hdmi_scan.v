// =============================================================================
// hdmi_scan.v : tao timing VGA 640x480@60Hz (pix_clk 25.2 MHz) + doc FIFO khung hinh
//
//   H: 640 + 16 + 96 + 48 = 800     V: 480 + 10 + 2 + 33 = 525     hsync, vsync am
//
//   FIFO cho ra tu 64 bit = 4 pixel RGB565 {p3,p2,p1,p0}. Cu 4 pixel doc 1 tu.
//   Moi khung:
//     - dong 481..482 : giu flush_req = 1  (frame_store reset FIFO, doi bo dem khung,
//                       khoi dong lai viec doc PSRAM tu dau khung)
//     - dong 484..524 : doc truoc tu dau tien (preload) khi FIFO co du lieu
//     - dong 0..479   : doc moi 4 pixel; tu cuoi cua dong keo tu dau cua dong ke tiep
//   Neu chua co khung camera nao / PSRAM chua san sang -> hien thanh mau 8 mau
//   (de kiem tra duong HDMI doc lap voi camera).
//
//   Dau ra la luong video thuong (r,g,b,hs,vs,de) -> co the chen bo xu ly (Sobel...)
//   vao giua hdmi_scan va hdmi_tx (xem video_proc.v).
// =============================================================================
module hdmi_scan (
    input  wire       pix_clk,
    input  wire       rst_n,

    input  wire       have_any,        // bat dong bo (tu clk_mem): da co khung hop le
    output reg        flush_req,
    output reg        f_ren,
    input  wire [63:0] f_rdata,
    input  wire       f_empty,

    output reg  [7:0] r,
    output reg  [7:0] g,
    output reg  [7:0] b,
    output reg        hs,
    output reg        vs,
    output reg        de,

    output reg        cam_on,          // khung hien tai dang hien anh camera
    output reg        underrun         // dinh 1: FIFO can trong luc dang hien
);
    localparam H_ACT = 640, H_FP = 16, H_SY = 96, H_BP = 48, H_TOT = 800;
    localparam V_ACT = 480, V_FP = 10, V_SY = 2,  V_BP = 33, V_TOT = 525;

    reg [9:0] h = 10'd0;
    reg [9:0] v = 10'd0;

    reg [1:0] ha_s    = 2'b00;
    reg       vid_ok  = 1'b0;
    reg       pre_done = 1'b0;

    initial begin
        flush_req = 1'b0; f_ren = 1'b0; r = 8'd0; g = 8'd0; b = 8'd0;
        hs = 1'b1; vs = 1'b1; de = 1'b0; cam_on = 1'b0; underrun = 1'b0;
    end

    // ---------------------------------------------------------------- tin hieu theo (h, v)
    wire act    = (h < H_ACT) && (v < V_ACT);
    wire hs_n   = ~((h >= H_ACT + H_FP) && (h < H_ACT + H_FP + H_SY));
    wire vs_n   = ~((v >= V_ACT + V_FP) && (v < V_ACT + V_FP + V_SY));

    wire [5:0]  sh = {h[1:0], 4'b0000};
    wire [15:0] px = f_rdata[sh +: 16];

    wire [2:0] bar = (h >= 560) ? 3'd7 : (h >= 480) ? 3'd6 : (h >= 400) ? 3'd5 :
                     (h >= 320) ? 3'd4 : (h >= 240) ? 3'd3 : (h >= 160) ? 3'd2 :
                     (h >=  80) ? 3'd1 : 3'd0;
    reg [23:0] bar_rgb;
    always @* begin
        case (bar)
        3'd0:    bar_rgb = 24'hFFFFFF;   // trang
        3'd1:    bar_rgb = 24'hFFFF00;   // vang
        3'd2:    bar_rgb = 24'h00FFFF;   // cyan
        3'd3:    bar_rgb = 24'h00FF00;   // xanh la
        3'd4:    bar_rgb = 24'hFF00FF;   // tim
        3'd5:    bar_rgb = 24'hFF0000;   // do
        3'd6:    bar_rgb = 24'h0000FF;   // xanh duong
        default: bar_rgb = 24'h000000;   // den
        endcase
    end

    // ---------------------------------------------------------------- dem h / v
    always @(posedge pix_clk) begin
        if (!rst_n) begin
            h <= 10'd0; v <= 10'd0;
        end else begin
            if (h == H_TOT - 1) begin
                h <= 10'd0;
                v <= (v == V_TOT - 1) ? 10'd0 : (v + 10'd1);
            end else begin
                h <= h + 10'd1;
            end
        end
    end

    // ---------------------------------------------------------------- dieu khien doc FIFO
    always @(posedge pix_clk) begin
        ha_s <= {ha_s[0], have_any};
        if (!rst_n) begin
            flush_req <= 1'b0; f_ren <= 1'b0; vid_ok <= 1'b0; pre_done <= 1'b0;
            cam_on <= 1'b0; underrun <= 1'b0;
        end else begin
            f_ren     <= 1'b0;
            flush_req <= (v == 10'd481) || (v == 10'd482);

            if ((v == 10'd483) && (h == 10'd0)) vid_ok <= ha_s[1];

            if (flush_req) begin
                pre_done <= 1'b0;
            end else if ((v >= 10'd484) && vid_ok && !pre_done && !f_empty && !f_ren) begin
                f_ren    <= 1'b1;               // doc truoc tu dau tien cua khung
                pre_done <= 1'b1;
            end

            if ((v == V_TOT - 1) && (h == H_TOT - 1))
    cam_on <= vid_ok & pre_done;

            // (bo lenh doc cuoi cung cua khung: sau tu thu 76800 khong con du lieu)
            if (cam_on && (v < V_ACT) && (h < H_ACT) && (h[1:0] == 2'd2) &&
                !((v == V_ACT - 1) && (h == H_ACT - 2))) begin
                f_ren <= 1'b1;                  // keo tu ke tiep (xuat hien o chu ky h[1:0]==0)
                if (f_empty) underrun <= 1'b1;
            end
        end
    end

    // ---------------------------------------------------------------- dau ra (tre 1 chu ky)
    always @(posedge pix_clk) begin
        de <= act;
        hs <= hs_n;
        vs <= vs_n;
        if (act) begin
            if (cam_on) begin
                r <= {px[15:11], px[15:13]};
                g <= {px[10:5],  px[10:9]};
                b <= {px[4:0],   px[4:2]};
            end else begin
                {r, g, b} <= bar_rgb;
            end
        end else begin
            r <= 8'd0; g <= 8'd0; b <= 8'd0;
        end
    end
endmodule
