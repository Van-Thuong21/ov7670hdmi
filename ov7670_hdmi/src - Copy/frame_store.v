// =============================================================================
// frame_store.v : Bo nho khung hinh 640x480x16bit trong PSRAM tich hop cua GW1NR-9
//                 (Gowin "PSRAM Memory Interface HS" IP, 2 kenh, burst 64 byte/kenh)
//
//   Camera (pclk) -> line_buf (2 dong, BSRAM) -> [ghi burst] -> PSRAM
//   PSRAM -> [doc burst] -> afifo64 (BSRAM) -> HDMI (pix_clk)
//
//   Dinh dang du lieu 1 "tu" 64 bit = 4 pixel RGB565:
//        {pixel3, pixel2, pixel1, pixel0}          (pixel0 = ben trai nhat)
//        kenh 0 = tu[31:0] (pixel0,1)   kenh 1 = tu[63:32] (pixel2,3)
//   1 lenh burst = 16 tu = 64 pixel = 128 byte (moi kenh 64 byte)
//   1 dong 640 pixel = 10 burst ; 1 khung = 4800 burst
//
//   Dia chi IP (21 bit, don vi 2 byte/kenh):
//        addr = {1'b0, buf[1:0], n[12:0], 5'b00000}     n = y*10 + seg
//
//   3 bo dem khung (triple buffer) - khong bao gio xe hinh:
//        bw : camera dang ghi      bl : khung hoan chinh moi nhat      bd : dang hien thi
//        - ghi xong dong 479      -> doi bw <-> bl
//        - HDMI bat dau khung moi -> neu co khung moi thi doi bl <-> bd
//
//   Phia HDMI moi khung (khoang blanking doc) keo flush_req len -> FIFO + bo dem doc
//   duoc reset, bo thu burst duoc khoi dong lai tu burst 0 cua khung hien thi.
//
//   !!! Ten cong cua IP lay theo Gowin IPUG943 (bang 5-2, dual channel). Neu ban IP sinh
//   ra khac ten, chi can sua khoi "u_psram" ben duoi.
// =============================================================================
module frame_store #(
    parameter CMD_INTERVAL = 32          // so chu ky clk_mem toi thieu giua 2 lenh (burst 64: >= 27)
)(
    input  wire        clk27,            // clock tham chieu cua IP
    input  wire        mem_clk_hs,       // 81 MHz tu PLL
    input  wire        pll_lock,
    input  wire        rst_n,            // reset (mien clk27)

    output wire        clk_mem,          // = clk_out cua IP (40.5 MHz)
    output wire        mem_ready,        // IP da calib xong (muc, mien clk_mem)
    output reg         mem_err,          // dinh 1 khi tran hang doi dong (mien clk_mem)
    output reg         have_any,         // da co it nhat 1 khung hop le (mien clk_mem)

    // chan PSRAM noi trong goi (khong can IO_LOC)
    output wire [1:0]  O_psram_ck,
    output wire [1:0]  O_psram_ck_n,
    inout  wire [1:0]  IO_psram_rwds,
    output wire [1:0]  O_psram_reset_n,
    inout  wire [15:0] IO_psram_dq,
    output wire [1:0]  O_psram_cs_n,

    // phia camera (mien pclk)
    input  wire        pclk,
    input  wire        lb_we,
    input  wire [8:0]  lb_waddr,
    input  wire [63:0] lb_wdata,
    input  wire        ln_tgl,
    input  wire [8:0]  ln_y,
    input  wire        freeze,           // muc (bat dong bo): 1 = dung cap nhat khung moi

    // phia HDMI (mien pix_clk)
    input  wire        pix_clk,
    input  wire        pix_rst_n,
    input  wire        flush_req,        // muc, tu hdmi_scan
    input  wire        f_ren,
    output wire [63:0] f_rdata,
    output wire        f_empty
);
    // ------------------------------------------------------------------ IP PSRAM
    wire        init0, init1;
    reg         cmd    = 1'b0;
    reg         cmd_en = 1'b0;
    reg  [20:0] addr   = 21'd0;
    wire [63:0] lb_q;
    wire [31:0] rd0, rd1;
    wire        rv0, rv1;

    PSRAM_Memory_Interface_HS_Top u_psram (
        .clk            (clk27),
        .memory_clk     (mem_clk_hs),
        .pll_lock       (pll_lock),
        .rst_n          (rst_n),
        .clk_out        (clk_mem),

        .O_psram_ck     (O_psram_ck),
        .O_psram_ck_n   (O_psram_ck_n),
        .IO_psram_rwds  (IO_psram_rwds),
        .O_psram_reset_n(O_psram_reset_n),
        .IO_psram_dq    (IO_psram_dq),
        .O_psram_cs_n   (O_psram_cs_n),

        .init_calib0    (init0),
        .init_calib1    (init1),

        .cmd0           (cmd),
        .cmd_en0        (cmd_en),
        .addr0          (addr),
        .wr_data0       (lb_q[31:0]),
        .data_mask0     (4'b0000),
        .rd_data0       (rd0),
        .rd_data_valid0 (rv0),

        .cmd1           (cmd),
        .cmd_en1        (cmd_en),
        .addr1          (addr),
        .wr_data1       (lb_q[63:32]),
        .data_mask1     (4'b0000),
        .rd_data1       (rd1),
        .rd_data_valid1 (rv1)
    );

    // ------------------------------------------------------------------ reset mien clk_mem
    reg [1:0] rstm_s = 2'b00;
    always @(posedge clk_mem) rstm_s <= {rstm_s[0], rst_n & init0 & init1};
    wire mem_rst_n = rstm_s[1];
    assign mem_ready = mem_rst_n;

    // ------------------------------------------------------------------ dong bo tin hieu vao clk_mem
    reg [2:0] tg_s = 3'b000;       // ln_tgl
    reg [1:0] fz_s = 2'b00;        // freeze
    reg [1:0] fl_s = 2'b00;        // flush_req
    reg       fl_d = 1'b0;
    always @(posedge clk_mem) begin
        tg_s <= {tg_s[1:0], ln_tgl};
        fz_s <= {fz_s[0], freeze};
        fl_s <= {fl_s[0], flush_req};
        fl_d <= fl_s[1];
    end
    wire ev_line = tg_s[2] ^ tg_s[1];          // 1 dong moi tu camera
    wire vs_ev   = fl_s[1] & ~fl_d;            // HDMI bat dau khoang blanking doc

    // ------------------------------------------------------------------ line buffer
    reg  [8:0] lb_raddr = 9'd0;
    line_buf u_lb (
        .wclk(pclk),    .we(lb_we), .waddr(lb_waddr), .wdata(lb_wdata),
        .rclk(clk_mem), .raddr(lb_raddr), .rdata(lb_q)
    );

    // ------------------------------------------------------------------ FIFO hien thi
    wire [8:0] wfree;
    reg        rpush = 1'b0;
    reg [63:0] rword = 64'd0;
    always @(posedge clk_mem) begin
        rpush <= rv0;
        rword <= {rd1, rd0};
    end

    afifo64 #(.AW(8)) u_fifo (
        .wclk(clk_mem), .wrst_n(mem_rst_n & ~fl_s[1]),
        .wen(rpush), .wdata(rword), .wfree(wfree),
        .rclk(pix_clk), .rrst_n(pix_rst_n & ~flush_req),
        .ren(f_ren), .rdata(f_rdata), .rempty(f_empty)
    );

    // ------------------------------------------------------------------ dieu khien
    localparam [1:0] A_IDLE = 2'd0, A_WCMD = 2'd1, A_WSTR = 2'd2;

    reg [1:0]  st   = A_IDLE;
    reg [5:0]  hold = 6'd0;                 // dem chan lenh ke tiep
    reg [3:0]  wk   = 4'd0;

    // hang doi dong: 1 dong dang ghi (a_*) + 1 dong cho (p_*)
    reg        a_valid = 1'b0, p_valid = 1'b0;
    reg [8:0]  a_y = 9'd0, p_y = 9'd0;
    reg [3:0]  a_seg = 4'd0;
    reg        drop = 1'b0;                 // khung hien tai bi bo qua (freeze)

    // 3 bo dem khung
    reg [1:0]  bw = 2'd0, bl = 2'd1, bd = 2'd2;
    reg        have_new = 1'b0;

    // bo doc
    reg        r_active = 1'b0;
    reg [12:0] r_n = 13'd0;

    // bien tam (blocking)
    reg        fin, wdone_f, accept, av, pv, ld;
    reg [8:0]  ay, py;

    wire [12:0] a_y10 = ({4'd0, a_y} << 3) + ({4'd0, a_y} << 1);   // y*10
    wire [12:0] a_n   = a_y10 + {9'd0, a_seg};
    wire [20:0] wr_addr = {1'b0, bw, a_n, 5'b00000};
    wire [20:0] rd_addr = {1'b0, bd, r_n, 5'b00000};

    wire want_rd = r_active && !fl_s[1] && (wfree >= 9'd48);

    initial begin mem_err = 1'b0; have_any = 1'b0; end

    always @(posedge clk_mem) begin
        if (!mem_rst_n) begin
            st <= A_IDLE; hold <= 6'd0; wk <= 4'd0;
            cmd <= 1'b0; cmd_en <= 1'b0; addr <= 21'd0; lb_raddr <= 9'd0;
            a_valid <= 1'b0; p_valid <= 1'b0; a_y <= 9'd0; p_y <= 9'd0; a_seg <= 4'd0;
            drop <= 1'b0;
            bw <= 2'd0; bl <= 2'd1; bd <= 2'd2; have_new <= 1'b0; have_any <= 1'b0;
            r_active <= 1'b0; r_n <= 13'd0;
            mem_err <= 1'b0;
        end else begin
            cmd_en  <= 1'b0;
            fin     = 1'b0;
            wdone_f = 1'b0;
            ld      = 1'b0;
            if (hold != 6'd0) hold <= hold - 6'd1;

            // ------------------------------------------------ FSM lenh (doc uu tien hon ghi)
            case (st)
            A_IDLE: if (hold == 6'd0) begin
                if (want_rd) begin
                    cmd    <= 1'b0;                 // doc
                    cmd_en <= 1'b1;
                    addr   <= rd_addr;
                    hold   <= CMD_INTERVAL;
                    r_n    <= r_n + 13'd1;
                    if (r_n == 13'd4799) r_active <= 1'b0;
                end else if (a_valid) begin
                    lb_raddr <= {a_y[0], a_seg, 4'd0};   // nap dia chi tu dau tien (BRAM tre 1 chu ky)
                    st       <= A_WCMD;
                end
            end

            A_WCMD: begin                           // lenh + tu thu 0 ra cung 1 chu ky
                cmd      <= 1'b1;                   // ghi
                cmd_en   <= 1'b1;
                addr     <= wr_addr;
                hold     <= CMD_INTERVAL;
                lb_raddr <= lb_raddr + 9'd1;
                wk       <= 4'd1;
                st       <= A_WSTR;
                if (a_seg == 4'd9) begin
                    fin = 1'b1;
                    if (a_y == 9'd479) wdone_f = 1'b1;
                end else begin
                    a_seg <= a_seg + 4'd1;
                end
            end

            A_WSTR: begin                           // phat tiep 15 tu con lai
                lb_raddr <= lb_raddr + 9'd1;
                wk       <= wk + 4'd1;
                if (wk == 4'd14) st <= A_IDLE;
            end

            default: st <= A_IDLE;
            endcase

            // ------------------------------------------------ hang doi dong tu camera
            av = a_valid; pv = p_valid; ay = a_y; py = p_y;
            if (fin) begin
                if (pv) begin ay = py; pv = 1'b0; ld = 1'b1; end
                else          av = 1'b0;
            end
            if (ev_line) begin
                if (ln_y == 9'd0) begin
                    drop   <= fz_s[1];
                    accept = !fz_s[1];
                end else begin
                    accept = !drop;
                end
                if (accept) begin
                    if (!av)       begin av = 1'b1; ay = ln_y; ld = 1'b1; end
                    else if (!pv)  begin pv = 1'b1; py = ln_y; end
                    else           mem_err <= 1'b1;
                end
            end
            a_valid <= av; p_valid <= pv; a_y <= ay; p_y <= py;
            if (ld) a_seg <= 4'd0;

            // ------------------------------------------------ doi bo dem khung
            if (wdone_f && vs_ev) begin
                bw <= bl; bl <= bd; bd <= bw; have_new <= 1'b0; have_any <= 1'b1;
            end else if (wdone_f) begin
                bw <= bl; bl <= bw; have_new <= 1'b1;
            end else if (vs_ev && have_new) begin
                bl <= bd; bd <= bl; have_new <= 1'b0; have_any <= 1'b1;
            end

            // ------------------------------------------------ khoi dong lai bo doc moi khung
            if (vs_ev) begin
                r_active <= 1'b1;
                r_n      <= 13'd0;
            end
        end
    end
endmodule
