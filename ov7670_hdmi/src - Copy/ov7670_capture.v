// =============================================================================
// ov7670_capture.v : Thu anh 640x480 RGB565 tu OV7670 (Da fix chong lech byte)
// =============================================================================
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
    reg        vs_d  = 1'b0;
    reg        hr_d  = 1'b0;
    reg        bsel  = 1'b0;            
    reg [7:0]  hi    = 8'd0;
    reg [9:0]  x     = 10'd0;          
    reg [9:0]  y     = 10'd0;          
    reg [15:0] p0    = 16'd0, p1 = 16'd0, p2 = 16'd0;
    reg        ev    = 1'b0;

    initial begin
        lb_we    = 1'b0;
        lb_waddr = 9'd0;
        lb_wdata = 64'd0;
        ln_tgl   = 1'b0;
        ln_y     = 9'd0;
        frm_tgl  = 1'b0;
    end

    wire        vs_rise = vsync & ~vs_d;
    wire        hr_rise = href & ~hr_d;     // Phat hien suon len cua HREF (bat dau 1 dong)
    wire [15:0] pix     = {hi, d};

    always @(posedge pclk) begin
        vs_d  <= vsync;
        hr_d  <= href;
        lb_we <= 1'b0;
        ev    <= 1'b0;
        if (ev) ln_tgl <= ~ln_tgl;

        if (vs_rise) begin                   
            x       <= 10'd0;
            y       <= 10'd0;
            bsel    <= 1'b0;
            frm_tgl <= ~frm_tgl;
        end else begin
            // Quan trọng: Moi khi HREF bat dau len cao, Ep buoc reset bsel ve 0 
            // de dam bao byte dau tien cua dong luon la byte cao (MSB).
            if (hr_rise) begin
                x    <= 10'd0;
                bsel <= 1'b0;
            end

            if (href) begin
                if (!bsel) begin
                    hi   <= d;              
                    bsel <= 1'b1;
                end else begin
                    bsel <= 1'b0;          
                    if (x < 10'd640 && y < 10'd480) begin
                        case (x[1:0])
                        2'd0: p0 <= pix;
                        2'd1: p1 <= pix;
                        2'd2: p2 <= pix;
                        2'd3: begin
                            lb_we    <= 1'b1;
                            lb_waddr <= {y[0], x[9:2]};
                            lb_wdata <= {pix, p2, p1, p0}; 
                        end
                        endcase
                    end
                    if (x < 10'd639) begin
                        x <= x + 10'd1;
                    end
                end
            end

            // Khi ket thuc mot dong quet (href chuyen tu cao xuong thap)
            if (hr_d && !href) begin
                if (y < 10'd480) begin
                    ln_y <= y[8:0];
                    ev   <= 1'b1;
                    y    <= y + 10'd1;
                end
                x    <= 10'd0;
                bsel <= 1'b0;
            end
        end
    end
endmodule