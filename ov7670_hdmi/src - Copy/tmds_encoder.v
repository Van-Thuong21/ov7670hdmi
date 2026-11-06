// =============================================================================
// tmds_encoder.v : ma hoa TMDS 8b/10b (DVI 1.0), 1 kenh, co thanh ghi dau ra
//   de = 1 : ma hoa du lieu pixel (din)
//   de = 0 : ma hoa 2 bit dieu khien c[1:0]  (kenh xanh duong: c = {vsync, hsync})
//   Do tre: 1 chu ky pix_clk.
// =============================================================================
module tmds_encoder (
    input  wire       clk,
    input  wire [7:0] din,
    input  wire [1:0] c,
    input  wire       de,
    output reg  [9:0] q
);
    integer n1d, n1q, n0q, i;
    integer cnt = 0;                 // chenh lech so bit 1 - bit 0 da gui (disparity)
    reg [8:0] qm;

    initial q = 10'b1101010100;

    always @(posedge clk) begin
        // ---- buoc 1: giam so lan chuyen bit (XOR / XNOR) ----
        n1d = 0;
        for (i = 0; i < 8; i = i + 1) n1d = n1d + din[i];

        qm[0] = din[0];
        if ((n1d > 4) || ((n1d == 4) && (din[0] == 1'b0))) begin
            for (i = 1; i < 8; i = i + 1) qm[i] = ~(qm[i-1] ^ din[i]);
            qm[8] = 1'b0;
        end else begin
            for (i = 1; i < 8; i = i + 1) qm[i] = qm[i-1] ^ din[i];
            qm[8] = 1'b1;
        end

        n1q = 0;
        for (i = 0; i < 8; i = i + 1) n1q = n1q + qm[i];
        n0q = 8 - n1q;

        // ---- buoc 2: can bang DC ----
        if (de) begin
            if ((cnt == 0) || (n1q == n0q)) begin
                q[9]   <= ~qm[8];
                q[8]   <= qm[8];
                q[7:0] <= qm[8] ? qm[7:0] : ~qm[7:0];
                if (qm[8] == 1'b0) cnt = cnt + (n0q - n1q);
                else               cnt = cnt + (n1q - n0q);
            end else if (((cnt > 0) && (n1q > n0q)) || ((cnt < 0) && (n0q > n1q))) begin
                q[9]   <= 1'b1;
                q[8]   <= qm[8];
                q[7:0] <= ~qm[7:0];
                cnt = cnt + (qm[8] ? 2 : 0) + (n0q - n1q);
            end else begin
                q[9]   <= 1'b0;
                q[8]   <= qm[8];
                q[7:0] <= qm[7:0];
                cnt = cnt - (qm[8] ? 0 : 2) + (n1q - n0q);
            end
        end else begin
            cnt = 0;
            case (c)
            2'b00:   q <= 10'b1101010100;
            2'b01:   q <= 10'b0010101011;
            2'b10:   q <= 10'b0101010100;
            default: q <= 10'b1010101011;
            endcase
        end
    end
endmodule
