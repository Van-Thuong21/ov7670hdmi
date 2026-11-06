// =============================================================================
// sccb_master.v : SCCB (giong I2C) - chi GHI 1 thanh ghi cua OV7670
//   Chu trinh 3 pha: [ID 0x42 | x] [reg addr | x] [data | x]  (x = bit ACK)
//   SCL ~ 99 kHz.  SDA dieu khien kieu open-drain: sda_low=1 -> keo SDA xuong 0.
//   nack = 1 (cung xung voi done) neu co it nhat 1 bit ACK khong ve muc 0.
// =============================================================================
module sccb_master #(
    parameter TICK_DIV = 68           // 27MHz / (4*68) ~= 99 kHz
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       start,          // xung 1 chu ky, kem reg_addr / reg_data
    input  wire [7:0] reg_addr,
    input  wire [7:0] reg_data,
    input  wire       sda_in,         // doc lai SDA (de kiem tra ACK)
    output reg        busy,
    output reg        done,           // xung khi ket thuc
    output reg        nack,           // hop le cung luc voi done
    output reg        sioc,
    output reg        sda_low
);
    localparam [3:0] S_IDLE = 4'd0, S_ST0 = 4'd1, S_ST1 = 4'd2, S_BIT = 4'd3,
                     S_SP0  = 4'd4, S_SP1 = 4'd5, S_SP2 = 4'd6, S_FIN = 4'd7;

    reg [3:0]  st;
    reg [1:0]  ph;
    reg [4:0]  bitcnt;
    reg [26:0] sh;
    reg [7:0]  tcnt;
    reg        nack_acc;

    wire tick = (tcnt == TICK_DIV - 1);

    initial begin
        st = S_IDLE; ph = 2'd0; bitcnt = 5'd0; sh = 27'd0; tcnt = 8'd0;
        busy = 1'b0; done = 1'b0; nack = 1'b0; sioc = 1'b1; sda_low = 1'b0;
        nack_acc = 1'b0;
    end

    // bo tao tick (1/4 chu ky SCL), chi chay khi busy
    always @(posedge clk) begin
        if (!rst_n || !busy) tcnt <= 8'd0;
        else if (tick)       tcnt <= 8'd0;
        else                 tcnt <= tcnt + 8'd1;
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            st <= S_IDLE; ph <= 2'd0; bitcnt <= 5'd0; sh <= 27'd0;
            busy <= 1'b0; done <= 1'b0; nack <= 1'b0;
            sioc <= 1'b1; sda_low <= 1'b0; nack_acc <= 1'b0;
        end else begin
            done <= 1'b0;
            nack <= 1'b0;
            case (st)
            S_IDLE: begin
                sioc    <= 1'b1;
                sda_low <= 1'b0;
                if (start) begin
                    sh       <= {8'h42, 1'b1, reg_addr, 1'b1, reg_data, 1'b1};
                    bitcnt   <= 5'd0;
                    ph       <= 2'd0;
                    nack_acc <= 1'b0;
                    busy     <= 1'b1;
                    st       <= S_ST0;
                end
            end
            // START: SDA ha xuong trong khi SCL = 1
            S_ST0: if (tick) begin sda_low <= 1'b1; st <= S_ST1; end
            S_ST1: if (tick) begin sioc <= 1'b0; ph <= 2'd0; st <= S_BIT; end
            // 27 bit, moi bit 4 tick
            S_BIT: if (tick) begin
                case (ph)
                2'd0: begin sioc <= 1'b0; sda_low <= ~sh[26]; ph <= 2'd1; end
                2'd1: begin sioc <= 1'b1; ph <= 2'd2; end
                2'd2: begin
                    ph <= 2'd3;
                    // lay mau bit ACK (bit thu 9, 18, 27) luc SCL dang cao
                    if ((bitcnt == 5'd8) || (bitcnt == 5'd17) || (bitcnt == 5'd26))
                        if (sda_in) nack_acc <= 1'b1;
                end
                2'd3: begin
                    sioc <= 1'b0;
                    sh   <= {sh[25:0], 1'b1};
                    if (bitcnt == 5'd26) st <= S_SP0;
                    else begin bitcnt <= bitcnt + 5'd1; ph <= 2'd0; end
                end
                endcase
            end
            // STOP: SDA len cao trong khi SCL = 1
            S_SP0: if (tick) begin sioc <= 1'b0; sda_low <= 1'b1; st <= S_SP1; end
            S_SP1: if (tick) begin sioc <= 1'b1; st <= S_SP2; end
            S_SP2: if (tick) begin sda_low <= 1'b0; st <= S_FIN; end
            S_FIN: if (tick) begin
                busy <= 1'b0;
                done <= 1'b1;
                nack <= nack_acc;
                st   <= S_IDLE;
            end
            default: st <= S_IDLE;
            endcase
        end
    end
endmodule
