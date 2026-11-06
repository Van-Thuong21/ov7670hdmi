// =============================================================================
// ov7670_init.v : Nap bang thanh ghi cho OV7670
//   - Che do: VGA 640x480, RGB565 (full range), CLKRC = /2 (doi bang CLKRC_VAL)
//   - XCLK = 27 MHz  ->  PCLK = 13.5 MHz  (~17 fps)
//     CLKRC_VAL = 8'h00 -> PCLK = 27 MHz (~34 fps) nhung day cam phai tot
//   - FPGA thu du 640x480 (khong lay mau bot)
//   - colorbar = 1 : bat 8-bar color bar BEN TRONG cam bien (thanh ghi 0x71[7])
//   Khi 'colorbar' doi trang thai, chi ghi lai thanh ghi 0x71.
// =============================================================================
module ov7670_init #(
    parameter CLK_HZ        = 27_000_000,
    parameter [7:0] CLKRC_VAL = 8'h01          // 0x01: PCLK = XCLK/2 | 0x00: PCLK = XCLK
)(
    input  wire clk,
    input  wire rst_n,
    input  wire colorbar,
    output reg  done,          // da nap xong
    output reg  ack_bad,       // 1 neu tung co bit ACK khong ve (cam bien khong tra loi)
    output wire sioc,
    inout  wire siod
);
    localparam integer NREG       = 55;
    localparam [6:0]   LAST       = NREG - 1;          // 54 : thanh ghi 0x71 (colorbar)
    localparam integer POR_CYCLES = CLK_HZ / 10;       // 100 ms cho cam bien on dinh
    localparam integer RST_CYCLES = CLK_HZ / 50;       // 20 ms sau soft-reset
    localparam integer GAP_CYCLES = CLK_HZ / 5000;     // 200 us giua 2 lan ghi

    // ------------------------------------------------------------------ ROM
    function [15:0] rom;
        input [6:0] i;
        input       cb;
        begin
            case (i)
            7'd0:  rom = 16'h1280;  // COM7  : soft reset
            7'd1:  rom = 16'h1204;  // COM7  : VGA, output RGB
            7'd2:  rom = {8'h11, CLKRC_VAL};  // CLKRC : PCLK = XCLK/(CLKRC+1)
            7'd3:  rom = 16'h0C00;  // COM3
            7'd4:  rom = 16'h3E00;  // COM14 : tat scaling PCLK
            7'd5:  rom = 16'h8C00;  // RGB444: tat
            7'd6:  rom = 16'h0400;  // COM1
            7'd7:  rom = 16'h40D0;  // COM15 : RGB565, full range 00-FF
            7'd8:  rom = 16'h3A04;  // TSLB
            7'd9:  rom = 16'h1438;  // COM9  : AGC ceiling
            7'd10: rom = 16'h4FB3;  // MTX1..MTX6, MTXS : ma tran mau
            7'd11: rom = 16'h50B3;
            7'd12: rom = 16'h5100;
            7'd13: rom = 16'h523D;
            7'd14: rom = 16'h53A7;
            7'd15: rom = 16'h54E4;
            7'd16: rom = 16'h589E;
            7'd17: rom = 16'h3DC0;  // COM13 : gamma + UV auto
            7'd18: rom = 16'h1711;  // HSTART
            7'd19: rom = 16'h1861;  // HSTOP
            7'd20: rom = 16'h32A4;  // HREF
            7'd21: rom = 16'h1903;  // VSTART
            7'd22: rom = 16'h1A7B;  // VSTOP
            7'd23: rom = 16'h030A;  // VREF
            7'd24: rom = 16'h0E61;  // COM5
            7'd25: rom = 16'h0F4B;  // COM6
            7'd26: rom = 16'h1602;
            7'd27: rom = 16'h1E07;  // MVFP : 07 binh thuong | 27 guong | 17 lat doc | 37 ca hai
            7'd28: rom = 16'h2102;
            7'd29: rom = 16'h2291;
            7'd30: rom = 16'h2907;
            7'd31: rom = 16'h330B;
            7'd32: rom = 16'h350B;
            7'd33: rom = 16'h371D;
            7'd34: rom = 16'h3871;
            7'd35: rom = 16'h392A;
            7'd36: rom = 16'h3C78;  // COM12
            7'd37: rom = 16'h4D40;
            7'd38: rom = 16'h4E20;
            7'd39: rom = 16'h6900;  // GFIX
            7'd40: rom = 16'h7410;
            7'd41: rom = 16'h8D4F;
            7'd42: rom = 16'h8E00;
            7'd43: rom = 16'h8F00;
            7'd44: rom = 16'h9000;
            7'd45: rom = 16'h9100;
            7'd46: rom = 16'h9600;
            7'd47: rom = 16'h9A00;
            7'd48: rom = 16'hB084;
            7'd49: rom = 16'hB10C;
            7'd50: rom = 16'hB20E;
            7'd51: rom = 16'hB382;
            7'd52: rom = 16'hB80A;
            7'd53: rom = 16'h703A;  // SCALING_XSC : bit7 = test_pattern[0] = 0
            7'd54: rom = cb ? 16'h71B5 : 16'h7135;  // SCALING_YSC : bit7 = test_pattern[1] (1 = color bar)
            default: rom = 16'h0000;
            endcase
        end
    endfunction

    // ------------------------------------------------------------------ SCCB
    reg        sccb_start;
    reg  [7:0] w_addr, w_data;
    wire       sccb_busy, sccb_done, sccb_nack, sda_low;
    reg  [1:0] sda_s;

    initial begin
        sccb_start = 1'b0; w_addr = 8'd0; w_data = 8'd0; sda_s = 2'b11;
        done = 1'b0; ack_bad = 1'b0;
    end

    always @(posedge clk) sda_s <= {sda_s[0], siod};

    assign siod = sda_low ? 1'b0 : 1'bz;      // open-drain

    sccb_master #(.TICK_DIV(68)) u_sccb (
        .clk(clk), .rst_n(rst_n),
        .start(sccb_start), .reg_addr(w_addr), .reg_data(w_data),
        .sda_in(sda_s[1]),
        .busy(sccb_busy), .done(sccb_done), .nack(sccb_nack),
        .sioc(sioc), .sda_low(sda_low)
    );

    // ------------------------------------------------------------------ FSM
    localparam [2:0] I_POR = 3'd0, I_LOAD = 3'd1, I_WAIT = 3'd2, I_GAP = 3'd3, I_DONE = 3'd4;

    reg [2:0]  st;
    reg [6:0]  idx;
    reg [23:0] dly;
    reg        cb_applied;

    initial begin st = I_POR; idx = 7'd0; dly = 24'd0; cb_applied = 1'b0; end

    always @(posedge clk) begin
        if (!rst_n) begin
            st <= I_POR; idx <= 7'd0; dly <= 24'd0; done <= 1'b0; ack_bad <= 1'b0;
            sccb_start <= 1'b0; cb_applied <= 1'b0; w_addr <= 8'd0; w_data <= 8'd0;
        end else begin
            sccb_start <= 1'b0;
            case (st)
            I_POR: begin
                if (dly == POR_CYCLES) begin dly <= 24'd0; idx <= 7'd0; st <= I_LOAD; end
                else dly <= dly + 24'd1;
            end
            I_LOAD: begin
                {w_addr, w_data} <= rom(idx, colorbar);
                if (idx == LAST) cb_applied <= colorbar;
                sccb_start <= 1'b1;
                st <= I_WAIT;
            end
            I_WAIT: if (sccb_done) begin
                if (sccb_nack) ack_bad <= 1'b1;
                dly <= 24'd0;
                st  <= I_GAP;
            end
            I_GAP: begin
                if (dly == ((idx == 7'd0) ? RST_CYCLES : GAP_CYCLES)) begin
                    dly <= 24'd0;
                    if (idx == LAST) st <= I_DONE;
                    else begin idx <= idx + 7'd1; st <= I_LOAD; end
                end else dly <= dly + 24'd1;
            end
            I_DONE: begin
                done <= 1'b1;
                if (colorbar != cb_applied) begin   // doi che do test -> ghi lai 0x71
                    done <= 1'b0;
                    idx  <= LAST;
                    st   <= I_LOAD;
                end
            end
            default: st <= I_POR;
            endcase
        end
    end
endmodule
