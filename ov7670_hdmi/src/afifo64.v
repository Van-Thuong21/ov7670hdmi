// =============================================================================
// afifo64.v : FIFO bat dong bo 2^AW tu x 64 bit (gray pointer, BSRAM)
//   Ghi (wclk): wen, wdata ; wfree = so cho trong (0..2^AW), tinh tu pointer doc da dong bo
//   Doc (rclk): ren (xung) -> rdata cap nhat o canh clock ke tiep (rdata la thanh ghi)
//               rempty = 1 : khong co du lieu (ren bi bo qua)
//   Reset: wrst_n (mien wclk) va rrst_n (mien rclk) rieng; phai giu CA HAI trong
//          vai chu ky (o day: ca khoang blanking doc) de 2 pointer ve 0.
// =============================================================================
module afifo64 #(
    parameter AW = 8
)(
    input  wire          wclk,
    input  wire          wrst_n,
    input  wire          wen,
    input  wire [63:0]   wdata,
    output wire [AW:0]   wfree,

    input  wire          rclk,
    input  wire          rrst_n,
    input  wire          ren,
    output reg  [63:0]   rdata,
    output wire          rempty
);
    localparam [AW:0] DEPTH = {1'b1, {AW{1'b0}}};

    reg [63:0] mem [0:DEPTH-1] /* synthesis syn_ramstyle="block_ram" */;

    reg [AW:0] wbin  = {(AW+1){1'b0}};
    reg [AW:0] wgray = {(AW+1){1'b0}};
    reg [AW:0] rbin  = {(AW+1){1'b0}};
    reg [AW:0] rgray = {(AW+1){1'b0}};

    reg [AW:0] rg_w1 = {(AW+1){1'b0}}, rg_w2 = {(AW+1){1'b0}};   // rgray -> wclk
    reg [AW:0] wg_r1 = {(AW+1){1'b0}}, wg_r2 = {(AW+1){1'b0}};   // wgray -> rclk

    function [AW:0] g2b;
        input [AW:0] g;
        integer i;
        begin
            g2b[AW] = g[AW];
            for (i = AW - 1; i >= 0; i = i - 1)
                g2b[i] = g2b[i+1] ^ g[i];
        end
    endfunction

    // ------------------------------------------------------------ phia ghi
    wire [AW:0] wused  = wbin - g2b(rg_w2);
    wire        wfull  = (wused == DEPTH);
    assign      wfree  = DEPTH - wused;

    wire        wdo    = wen & wrst_n & ~wfull;
    wire [AW:0] wbin_n = wbin + 1'b1;

    always @(posedge wclk) begin
        if (wdo) mem[wbin[AW-1:0]] <= wdata;
    end

    always @(posedge wclk) begin
        rg_w1 <= rgray;
        rg_w2 <= rg_w1;
        if (!wrst_n) begin
            wbin  <= {(AW+1){1'b0}};
            wgray <= {(AW+1){1'b0}};
        end else if (wdo) begin
            wbin  <= wbin_n;
            wgray <= wbin_n ^ (wbin_n >> 1);
        end
    end

    // ------------------------------------------------------------ phia doc
    assign rempty = (rgray == wg_r2);

    wire        rdo    = ren & ~rempty;
    wire [AW:0] rbin_n = rbin + 1'b1;

    always @(posedge rclk) begin
        if (rdo) rdata <= mem[rbin[AW-1:0]];
    end

    always @(posedge rclk) begin
        wg_r1 <= wgray;
        wg_r2 <= wg_r1;
        if (!rrst_n) begin
            rbin  <= {(AW+1){1'b0}};
            rgray <= {(AW+1){1'b0}};
        end else if (rdo) begin
            rbin  <= rbin_n;
            rgray <= rbin_n ^ (rbin_n >> 1);
        end
    end
endmodule
