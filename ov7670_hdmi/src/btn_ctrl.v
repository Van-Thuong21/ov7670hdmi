// =============================================================================
// btn_ctrl.v : chong doi nut bam + TU DONG NHAN DIEN muc nghi (active-high/low)
//   Sau khi cap nguon ~78 ms, muc dang doc duoc coi la "chua bam".
//   => Dung cho ca truong hop nut active-high lan active-low.
//   (Dung giu nut khi vua nap/cap nguon)
// =============================================================================
module btn_ctrl #(
    parameter LEARN_BITS = 21,     // 2^21 / 27MHz ~ 78 ms
    parameter DEB_BITS   = 20      // 2^20 / 27MHz ~ 39 ms
)(
    input  wire clk,
    input  wire rst_n,
    input  wire btn_in,
    output reg  pulse
);
    reg [1:0]            sync     = 2'b00;
    reg [LEARN_BITS-1:0] lcnt     = {LEARN_BITS{1'b0}};
    reg                  learned  = 1'b0;
    reg                  idle_lvl = 1'b0;
    reg                  stable   = 1'b0;
    reg [DEB_BITS-1:0]   dcnt     = {DEB_BITS{1'b0}};

    initial pulse = 1'b0;

    always @(posedge clk) begin
        sync  <= {sync[0], btn_in};
        pulse <= 1'b0;
        if (!rst_n) begin
            lcnt    <= {LEARN_BITS{1'b0}};
            dcnt    <= {DEB_BITS{1'b0}};
            learned <= 1'b0;
        end else if (!learned) begin
            lcnt <= lcnt + 1'b1;
            if (&lcnt) begin
                learned  <= 1'b1;
                idle_lvl <= sync[1];
                stable   <= sync[1];
            end
        end else begin
            if (sync[1] != stable) begin
                dcnt <= dcnt + 1'b1;
                if (&dcnt) begin
                    stable <= sync[1];
                    dcnt   <= {DEB_BITS{1'b0}};
                    if (sync[1] != idle_lvl) pulse <= 1'b1;   // chi bao luc BAM
                end
            end else begin
                dcnt <= {DEB_BITS{1'b0}};
            end
        end
    end
endmodule
