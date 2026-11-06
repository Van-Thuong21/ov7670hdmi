// =============================================================================
// line_buf.v : 2 dong x 160 tu x 64 bit (ping-pong), 2 BSRAM
//   Cong ghi : clock PCLK cua camera
//   Cong doc : clock clk_mem (doc dong bo, tre 1 chu ky)
// =============================================================================
module line_buf (
    input  wire        wclk,
    input  wire        we,
    input  wire [8:0]  waddr,
    input  wire [63:0] wdata,
    input  wire        rclk,
    input  wire [8:0]  raddr,
    output reg  [63:0] rdata
);
    reg [63:0] mem [0:511] /* synthesis syn_ramstyle="block_ram" */;

    always @(posedge wclk) begin
        if (we) mem[waddr] <= wdata;
    end

    always @(posedge rclk) begin
        rdata <= mem[raddr];
    end
endmodule
