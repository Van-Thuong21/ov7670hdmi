
module ov7670_capture (
    input  wire        pclk,
    input  wire        vsync,
    input  wire        href,
    input  wire [7:0]  d,

    output reg         lb_we,
    output reg  [8:0]  lb_waddr,
    output reg  [63:0] lb_wdata,

    output reg         ln_tgl,
    output reg  [8:0]  ln_y,
    output reg         frm_tgl
);

    reg       vs_d = 1'b0;
    reg       hr_d = 1'b0;
    reg       bsel = 1'b0;

    reg [7:0] hi = 8'd0;
    reg [10:0] x = 11'd0;
    reg [9:0]  y = 10'd0;

    reg [15:0] p0 = 16'd0;
    reg [15:0] p1 = 16'd0;
    reg [15:0] p2 = 16'd0;

    wire vs_rise = vsync & ~vs_d;
    wire [15:0] pix = {hi, d};

    initial begin
        lb_we    = 1'b0;
        lb_waddr = 9'd0;
        lb_wdata = 64'd0;
        ln_tgl   = 1'b0;
        ln_y     = 9'd0;
        frm_tgl  = 1'b0;
    end

    always @(posedge pclk) begin

        vs_d  <= vsync;
        hr_d  <= href;
        lb_we <= 1'b0;

        // VSYNC active-high: reset vi tri dau khung
        if (vsync) begin
            x    <= 11'd0;
            y    <= 10'd0;
            bsel <= 1'b0;

            if (vs_rise)
                frm_tgl <= ~frm_tgl;
        end

        else if (!href) begin

            // Blanking: byte dau tien cua dong moi
            // luon duoc xem la byte RGB565 high
            bsel <= 1'b0;
            x    <= 11'd0;

            // Canh xuong HREF: dong vua ket thuc
            if (hr_d && (y < 10'd480)) begin
                ln_y   <= y[8:0];
                ln_tgl <= ~ln_tgl;
                y      <= y + 10'd1;
            end
        end

        else begin

            // Byte cao cua RGB565
            if (!bsel) begin
                hi   <= d;
                bsel <= 1'b1;
            end

            // Byte thap cua RGB565
            else begin
                bsel <= 1'b0;

                if ((x < 11'd640) && (y < 10'd480)) begin

                    case (x[1:0])

                        2'd0: p0 <= pix;

                        2'd1: p1 <= pix;

                        2'd2: p2 <= pix;

                        2'd3: begin
                            lb_we    <= 1'b1;

                            // Bank = y[0]
                            // 160 tu 64-bit tren moi dong
                            lb_waddr <= {y[0], x[9:2]};

                            // pixel0 nam ben trai nhat
                            lb_wdata <= {pix, p2, p1, p0};
                        end

                    endcase
                end

                // Dem pixel
                x <= x + 11'd1;
            end
        end
    end

endmodule
