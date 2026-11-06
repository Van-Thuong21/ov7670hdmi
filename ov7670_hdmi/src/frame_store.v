// =============================================================================
// frame_store.v
// OV7670 -> Line Buffer -> PSRAM -> FIFO -> HDMI
// Tang Nano 9K - GW1NR-LV9QN88PC6/I5
//
// Data format:
//   64-bit = 4 pixels RGB565
//   {pixel3, pixel2, pixel1, pixel0}
//
// PSRAM:
//   2 channels, each 32-bit
//   1 burst = 8 words/channel
//   1 line = 20 bursts
//   1 frame = 480 * 20 = 9600 bursts
//
// Buffer:
//   bw = buffer camera ghi
//   bl = buffer chứa frame hoàn chỉnh đang chờ
//   bd = buffer HDMI đang hiển thị
//
// Events:
//   frm_tgl  : camera bắt đầu frame mới
//   flush_req: HDMI chuẩn bị frame mới, reset FIFO
//
// =============================================================================

module frame_store #(
    parameter CMD_INTERVAL = 20
)(
    input  wire        clk27,
    input  wire        mem_clk_hs,
    input  wire        pll_lock,
    input  wire        rst_n,

    output wire        clk_mem,
    output wire        mem_ready,
    output reg         mem_err,
    output reg         have_any,

    // PSRAM pins
    output wire [1:0]  O_psram_ck,
    output wire [1:0]  O_psram_ck_n,
    inout  wire [1:0]  IO_psram_rwds,
    output wire [1:0]  O_psram_reset_n,
    inout  wire [15:0] IO_psram_dq,
    output wire [1:0]  O_psram_cs_n,

    // Camera domain
    input  wire        pclk,
    input  wire        lb_we,
    input  wire [8:0]  lb_waddr,
    input  wire [63:0] lb_wdata,
    input  wire        ln_tgl,
    input  wire [8:0]  ln_y,
    input  wire        frm_tgl,
    input  wire        freeze,

    // HDMI domain
    input  wire        pix_clk,
    input  wire        pix_rst_n,
    input  wire        flush_req,
    input  wire        f_ren,
    output wire [63:0] f_rdata,
    output wire        f_empty
);

    // =========================================================================
    // 1. PSRAM IP
    // =========================================================================

    wire init0, init1;

    reg         cmd    = 1'b0;
    reg         cmd_en = 1'b0;
    reg [20:0]  addr   = 21'd0;

    wire [63:0] lb_q;

    wire [31:0] rd0;
    wire [31:0] rd1;

    wire rv0;
    wire rv1;

    PSRAM_Memory_Interface_HS_Top u_psram (
        .clk             (clk27),
        .memory_clk      (mem_clk_hs),
        .pll_lock        (pll_lock),
        .rst_n           (rst_n),
        .clk_out         (clk_mem),

        .O_psram_ck      (O_psram_ck),
        .O_psram_ck_n    (O_psram_ck_n),
        .IO_psram_rwds   (IO_psram_rwds),
        .O_psram_reset_n (O_psram_reset_n),
        .IO_psram_dq     (IO_psram_dq),
        .O_psram_cs_n    (O_psram_cs_n),

        .init_calib0     (init0),
        .init_calib1     (init1),

        .cmd0            (cmd),
        .cmd_en0         (cmd_en),
        .addr0           (addr),
        .wr_data0        (lb_q[31:0]),
        .data_mask0      (4'b0000),
        .rd_data0        (rd0),
        .rd_data_valid0  (rv0),

        .cmd1            (cmd),
        .cmd_en1         (cmd_en),
        .addr1           (addr),
        .wr_data1        (lb_q[63:32]),
        .data_mask1      (4'b0000),
        .rd_data1        (rd1),
        .rd_data_valid1  (rv1)
    );


    // =========================================================================
    // 2. RESET DOMAIN clk_mem
    // =========================================================================

    reg [1:0] rstm_s = 2'b00;

    always @(posedge clk_mem) begin
        rstm_s <= {rstm_s[0], rst_n & init0 & init1};
    end

    wire mem_rst_n = rstm_s[1];

    assign mem_ready = mem_rst_n;


    // =========================================================================
    // 3. SYNCHRONIZE CAMERA AND HDMI SIGNALS
    // =========================================================================

    // Camera line toggle
    reg [2:0] tg_s = 3'b000;

    // Camera frame toggle
    reg [2:0] frm_s = 3'b000;
    reg       frm_d = 1'b0;

    // Freeze
    reg [1:0] fz_s = 2'b00;

    // HDMI flush
    reg [1:0] fl_s = 2'b00;
    reg       fl_d = 1'b0;

    // Camera line number
    reg [8:0] ln_y_s0 = 9'd0;
    reg [8:0] ln_y_s1 = 9'd0;
    reg [8:0] ln_y_s2 = 9'd0;

    always @(posedge clk_mem) begin

        if (!mem_rst_n) begin
            tg_s    <= 3'b000;

            frm_s   <= 3'b000;
            frm_d   <= 1'b0;

            fz_s    <= 2'b00;

            fl_s    <= 2'b00;
            fl_d    <= 1'b0;

            ln_y_s0 <= 9'd0;
            ln_y_s1 <= 9'd0;
            ln_y_s2 <= 9'd0;
        end
        else begin
            tg_s  <= {tg_s[1:0], ln_tgl};

            frm_s <= {frm_s[1:0], frm_tgl};
            frm_d <= frm_s[2];

            fz_s  <= {fz_s[0], freeze};

            fl_s  <= {fl_s[0], flush_req};
            fl_d  <= fl_s[1];

            ln_y_s0 <= ln_y;
            ln_y_s1 <= ln_y_s0;
            ln_y_s2 <= ln_y_s1;
        end
    end

    // Camera line event
    wire ev_line = tg_s[2] ^ tg_s[1];

    // Camera frame event
    wire cam_frame_ev = frm_s[2] ^ frm_d;

    // HDMI frame refresh event
    wire disp_frame_ev = fl_s[1] & ~fl_d;


    // =========================================================================
    // 4. LINE BUFFER
    // =========================================================================

    reg [8:0] lb_raddr = 9'd0;

    line_buf u_lb (
        .wclk  (pclk),
        .we    (lb_we),
        .waddr (lb_waddr),
        .wdata (lb_wdata),

        .rclk  (clk_mem),
        .raddr (lb_raddr),
        .rdata (lb_q)
    );


    // =========================================================================
    // 5. ASYNC FIFO: clk_mem -> pix_clk
    // =========================================================================

    wire [8:0] wfree;

    reg        rpush = 1'b0;
    reg [63:0] rword = 64'd0;

    afifo64 #(
        .AW(8)
    ) u_fifo (
        .wclk   (clk_mem),
        .wrst_n (mem_rst_n & ~fl_s[1]),
        .wen    (rpush),
        .wdata  (rword),
        .wfree  (wfree),

        .rclk   (pix_clk),
        .rrst_n (pix_rst_n & ~flush_req),
        .ren    (f_ren),
        .rdata  (f_rdata),
        .rempty (f_empty)
    );


    // =========================================================================
    // 6. PSRAM READ COLLECTOR
    // =========================================================================

    reg        rd_collecting  = 1'b0;
    reg        rd_push_active = 1'b0;

    reg [3:0]  rd0_count = 4'd0;
    reg [3:0]  rd1_count = 4'd0;

    reg [2:0]  rd_push_idx = 3'd0;

    reg [31:0] rd0_buf [0:7];
    reg [31:0] rd1_buf [0:7];


    // =========================================================================
    // 7. FSM AND FRAME BUFFER CONTROL
    // =========================================================================

    localparam [1:0]
        A_IDLE = 2'd0,
        A_WPRE = 2'd1,
        A_WCMD = 2'd2,
        A_WSTR = 2'd3;

    reg [1:0] st = A_IDLE;

    reg [5:0] hold = 6'd0;
    reg [2:0] wk   = 3'd0;


    // Line queue:
    // a_* : current line
    // p_* : pending line

    reg       a_valid = 1'b0;
    reg       p_valid = 1'b0;

    reg [8:0] a_y = 9'd0;
    reg [8:0] p_y = 9'd0;

    reg [4:0] a_seg = 5'd0;

    reg drop = 1'b0;


    // Triple buffer pointers

    reg [1:0] bw = 2'd0;
    reg [1:0] bl = 2'd1;
    reg [1:0] bd = 2'd2;

    reg have_new = 1'b0;


    // PSRAM read control

    reg       r_active = 1'b0;
    reg [13:0] r_n = 14'd0;


    // Temporary variables

    reg fin;
    reg wdone_f;
    reg accept;

    reg av;
    reg pv;

    reg ld;

    reg [8:0] ay;
    reg [8:0] py;


    // Temporary next buffer pointers

    reg [1:0] nbw;
    reg [1:0] nbl;
    reg [1:0] nbd;

    reg nhave_new;


    // =========================================================================
    // 8. ADDRESS GENERATION
    // =========================================================================

    // y * 20 = y * 16 + y * 4

    wire [13:0] a_y20 =
        ({5'd0, a_y} << 4) +
        ({5'd0, a_y} << 2);

    wire [13:0] a_n =
        a_y20 + {9'd0, a_seg};


    // Write address

    wire [20:0] wr_addr =
        {1'b0, bw, a_n, 4'b0000};


    // Read address

    wire [20:0] rd_addr =
        {1'b0, bd, r_n, 4'b0000};


    // Read request condition

    wire want_rd =
        r_active &&
        !fl_s[1] &&
        !rd_collecting &&
        !rd_push_active &&
        (wfree >= 9'd48);


    // =========================================================================
    // 9. INITIALIZATION
    // =========================================================================

    initial begin
        mem_err  = 1'b0;
        have_any = 1'b0;
    end


    // =========================================================================
    // 10. MAIN CONTROL
    // =========================================================================

    always @(posedge clk_mem) begin

        if (!mem_rst_n) begin

            // FSM

            st      <= A_IDLE;
            hold    <= 6'd0;
            wk      <= 3'd0;

            cmd     <= 1'b0;
            cmd_en  <= 1'b0;
            addr    <= 21'd0;

            lb_raddr <= 9'd0;


            // Line queue

            a_valid <= 1'b0;
            p_valid <= 1'b0;

            a_y     <= 9'd0;
            p_y     <= 9'd0;

            a_seg   <= 5'd0;

            drop    <= 1'b0;


            // Triple buffer

            bw       <= 2'd0;
            bl       <= 2'd1;
            bd       <= 2'd2;

            have_new <= 1'b0;
            have_any <= 1'b0;


            // Read control

            r_active <= 1'b0;
            r_n      <= 14'd0;


            // Read collector

            rd_collecting  <= 1'b0;
            rd_push_active <= 1'b0;

            rd0_count <= 4'd0;
            rd1_count <= 4'd0;

            rd_push_idx <= 3'd0;


            // FIFO write

            rpush <= 1'b0;
            rword <= 64'd0;


            // Error

            mem_err <= 1'b0;

        end
        else begin

            // -------------------------------------------------------------
            // Default values
            // -------------------------------------------------------------

            cmd_en <= 1'b0;
            rpush  <= 1'b0;

            fin     = 1'b0;
            wdone_f = 1'b0;
            ld      = 1'b0;

            if (hold != 6'd0)
                hold <= hold - 6'd1;


            // -------------------------------------------------------------
            // Camera frame event
            // -------------------------------------------------------------

            // Khi camera bắt đầu frame mới, xác định trạng thái freeze.
            // Sự kiện này KHÔNG dùng để reset FIFO HDMI.

            if (cam_frame_ev) begin
                drop <= fz_s[1];
            end


            // -------------------------------------------------------------
            // Collect PSRAM read data
            // -------------------------------------------------------------

            if (rd_collecting) begin

                if (rv0 && (rd0_count < 4'd8)) begin
                    rd0_buf[rd0_count[2:0]] <= rd0;
                    rd0_count <= rd0_count + 4'd1;
                end

                if (rv1 && (rd1_count < 4'd8)) begin
                    rd1_buf[rd1_count[2:0]] <= rd1;
                    rd1_count <= rd1_count + 4'd1;
                end


                // Đã nhận đủ 8 word ở cả hai kênh

                if (
                    ((rd0_count == 4'd8) ||
                     (rv0 && (rd0_count == 4'd7))) &&

                    ((rd1_count == 4'd8) ||
                     (rv1 && (rd1_count == 4'd7)))
                ) begin

                    rd_collecting  <= 1'b0;
                    rd_push_active <= 1'b1;

                    rd_push_idx <= 3'd0;
                end
            end


            // -------------------------------------------------------------
            // Push 8 words 64-bit into FIFO
            // -------------------------------------------------------------

            if (rd_push_active) begin

                rpush <= 1'b1;

                rword <= {
                    rd1_buf[rd_push_idx],
                    rd0_buf[rd_push_idx]
                };

                if (rd_push_idx == 3'd7) begin
                    rd_push_active <= 1'b0;
                end
                else begin
                    rd_push_idx <= rd_push_idx + 3'd1;
                end
            end


            // -------------------------------------------------------------
            // PSRAM command FSM
            // Read has priority over write
            // -------------------------------------------------------------

            case (st)

                // ---------------------------------------------------------
                // IDLE
                // ---------------------------------------------------------

                A_IDLE: begin

                    if (hold == 6'd0) begin

                        // Read burst

                        if (want_rd) begin

                            cmd    <= 1'b0;
                            cmd_en <= 1'b1;

                            addr <= rd_addr;

                            hold <= CMD_INTERVAL;

                            rd_collecting <= 1'b1;

                            rd0_count <= 4'd0;
                            rd1_count <= 4'd0;

                            r_n <= r_n + 14'd1;

                            if (r_n == 14'd9599)
                                r_active <= 1'b0;

                        end

                        // Write burst

                        else if (a_valid) begin

                            lb_raddr <= {
                                a_y[0],
                                a_seg,
                                3'b000
                            };

                            st <= A_WPRE;
                        end
                    end
                end


                // ---------------------------------------------------------
                // WAIT FOR LINE BUFFER READ
                // ---------------------------------------------------------

                A_WPRE: begin

                    // line_buf có latency đọc đồng bộ 1 chu kỳ

                    st <= A_WCMD;
                end


                // ---------------------------------------------------------
                // WRITE COMMAND
                // ---------------------------------------------------------

                A_WCMD: begin

                    cmd    <= 1'b1;
                    cmd_en <= 1'b1;

                    addr <= wr_addr;

                    hold <= CMD_INTERVAL;

                    // Chuẩn bị word tiếp theo

                    lb_raddr <= lb_raddr + 9'd1;

                    wk <= 3'd1;

                    st <= A_WSTR;
                end


                // ---------------------------------------------------------
                // WRITE DATA
                // ---------------------------------------------------------

                A_WSTR: begin

                    wk <= wk + 3'd1;

                    if (wk < 3'd7) begin
                        lb_raddr <= lb_raddr + 9'd1;
                    end


                    // Đã ghi đủ 8 word

                    if (wk == 3'd7) begin

                        st <= A_IDLE;

                        if (a_seg == 5'd19) begin

                            fin = 1'b1;

                            if (a_y == 9'd479)
                                wdone_f = 1'b1;

                        end
                        else begin

                            a_seg <= a_seg + 5'd1;

                        end
                    end
                end


                default: begin
                    st <= A_IDLE;
                end

            endcase


            // -------------------------------------------------------------
            // Line queue management
            // -------------------------------------------------------------

            av = a_valid;
            pv = p_valid;

            ay = a_y;
            py = p_y;


            // Hoàn thành một dòng

            if (fin) begin

                if (pv) begin

                    ay = py;

                    pv = 1'b0;

                    ld = 1'b1;

                end
                else begin

                    av = 1'b0;

                end
            end


            // Nhận dòng mới từ camera

            if (ev_line) begin

                if (ln_y_s2 == 9'd0) begin

                    drop   <= fz_s[1];
                    accept = !fz_s[1];

                end
                else begin

                    accept = !drop;

                end


                if (accept) begin

                    if (!av) begin

                        av = 1'b1;

                        ay = ln_y_s2;

                        ld = 1'b1;

                    end

                    else if (!pv) begin

                        pv = 1'b1;

                        py = ln_y_s2;

                    end

                    else begin

                        // Queue đầy: không thể nhận thêm dòng

                        mem_err <= 1'b1;

                    end
                end
            end


            a_valid <= av;
            p_valid <= pv;

            a_y <= ay;
            p_y <= py;


            if (ld)
                a_seg <= 5'd0;


            // -------------------------------------------------------------
            // TRIPLE BUFFER MANAGEMENT
            // -------------------------------------------------------------

            // Dùng biến tạm để xử lý đúng khi hai sự kiện xảy ra
            // trong cùng một chu kỳ clk_mem.

            nbw = bw;
            nbl = bl;
            nbd = bd;

            nhave_new = have_new;


            // Bước 1:
            // HDMI chuyển sang buffer mới nhất đang chờ.

            if (disp_frame_ev && have_new) begin

                nbl = bd;
                nbd = bl;

                nhave_new = 1'b0;

                have_any <= 1'b1;

            end


            // Bước 2:
            // Camera ghi xong toàn bộ frame.
            // Chuyển buffer vừa ghi xong sang buffer chờ.

            if (wdone_f) begin

                nbw = nbl;
                nbl = bw;

                nhave_new = 1'b1;

            end


            // Cập nhật đồng thời các con trỏ buffer

            bw <= nbw;
            bl <= nbl;
            bd <= nbd;

            have_new <= nhave_new;


            // -------------------------------------------------------------
            // HDMI FRAME REFRESH: restart PSRAM reader
            // -------------------------------------------------------------

            // Chỉ flush_req mới được dùng để bắt đầu đọc frame mới.
            // Không dùng frm_tgl thay thế flush_req.

            if (disp_frame_ev) begin

                r_active <= 1'b1;

                r_n <= 14'd0;

                rd_collecting <= 1'b0;
                rd_push_active <= 1'b0;

                rd0_count <= 4'd0;
                rd1_count <= 4'd0;

                rd_push_idx <= 3'd0;

                rpush <= 1'b0;

            end

        end
    end

endmodule