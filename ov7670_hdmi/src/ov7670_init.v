
module ov7670_init #(
    parameter integer CLK_HZ = 27_000_000,
    parameter [7:0] CLKRC_VAL = 8'h01
)(
    input  wire clk,
    input  wire rst_n,
    input  wire colorbar,

    output reg  done,
    output reg  ack_bad,

    output wire sioc,
    inout  wire siod
);

    localparam integer NREG = 91;
    localparam [6:0] LAST = NREG - 1;

    localparam integer POR_CYCLES = CLK_HZ / 5;
    localparam integer RST_CYCLES = CLK_HZ / 20;
    localparam integer GAP_CYCLES = CLK_HZ / 2000;

    function [15:0] rom;
        input [6:0] i;
        input cb;

        begin
            case (i)

                7'd0:  rom = 16'h1280;
                7'd1:  rom = cb ? 16'h1206 : 16'h1204;
                7'd2:  rom = {8'h11, CLKRC_VAL};
                7'd3:  rom = 16'h0C00;
                7'd4:  rom = 16'h3E00;
                7'd5:  rom = 16'h8C00;
                7'd6:  rom = 16'h0400;
                7'd7:  rom = 16'h40D0;
                7'd8:  rom = 16'h3A04;
                7'd9:  rom = 16'h1418;
                7'd10: rom = 16'h13E7;
                7'd11: rom = 16'h0140;
                7'd12: rom = 16'h0240;
                7'd13: rom = 16'h1500;

                // RGB color matrix
                7'd14: rom = 16'h4FB3;
                7'd15: rom = 16'h50B3;
                7'd16: rom = 16'h5100;
                7'd17: rom = 16'h523D;
                7'd18: rom = 16'h53A7;
                7'd19: rom = 16'h54E4;
                7'd20: rom = 16'h589E;
                7'd21: rom = 16'h3DC0;

                // VGA window
                7'd22: rom = 16'h1713;
                7'd23: rom = 16'h1801;
                7'd24: rom = 16'h32B6;
                7'd25: rom = 16'h1902;
                7'd26: rom = 16'h1A7A;
                7'd27: rom = 16'h030A;

                // AWB parameters
                7'd28: rom = 16'h430A;
                7'd29: rom = 16'h44F0;
                7'd30: rom = 16'h4534;
                7'd31: rom = 16'h4658;
                7'd32: rom = 16'h4728;
                7'd33: rom = 16'h483A;
                7'd34: rom = 16'h5988;
                7'd35: rom = 16'h5A88;
                7'd36: rom = 16'h5B44;
                7'd37: rom = 16'h5C67;
                7'd38: rom = 16'h5D49;
                7'd39: rom = 16'h5E0E;
                7'd40: rom = 16'h6C0A;
                7'd41: rom = 16'h6D55;
                7'd42: rom = 16'h6E11;
                7'd43: rom = 16'h6F9F;

                // Additional sensor registers
                7'd44: rom = 16'h0E61;
                7'd45: rom = 16'h0F4B;
                7'd46: rom = 16'h1602;
                7'd47: rom = 16'h1E07;
                7'd48: rom = 16'h2102;
                7'd49: rom = 16'h2291;
                7'd50: rom = 16'h2907;
                7'd51: rom = 16'h330B;
                7'd52: rom = 16'h350B;
                7'd53: rom = 16'h371D;
                7'd54: rom = 16'h3871;
                7'd55: rom = 16'h392A;
                7'd56: rom = 16'h3C78;
                7'd57: rom = 16'h4D40;
                7'd58: rom = 16'h4E20;
                7'd59: rom = 16'h6900;
                7'd60: rom = 16'h7410;
                7'd61: rom = 16'h8D4F;
                7'd62: rom = 16'h8E00;
                7'd63: rom = 16'h8F00;
                7'd64: rom = 16'h9000;
                7'd65: rom = 16'h9100;
                7'd66: rom = 16'h9600;
                7'd67: rom = 16'h9A00;
                7'd68: rom = 16'hB084;
                7'd69: rom = 16'hB10C;
                7'd70: rom = 16'hB20E;
                7'd71: rom = 16'hB382;
                7'd72: rom = 16'hB80A;

                // Gamma
                7'd73: rom = 16'h7A20;
                7'd74: rom = 16'h7B10;
                7'd75: rom = 16'h7C1E;
                7'd76: rom = 16'h7D35;
                7'd77: rom = 16'h7E5A;
                7'd78: rom = 16'h7F69;
                7'd79: rom = 16'h8076;
                7'd80: rom = 16'h8180;
                7'd81: rom = 16'h8288;
                7'd82: rom = 16'h838F;
                7'd83: rom = 16'h8496;
                7'd84: rom = 16'h85A3;
                7'd85: rom = 16'h86AF;
                7'd86: rom = 16'h87C4;
                7'd87: rom = 16'h88D7;
                7'd88: rom = 16'h89E8;

                7'd89: rom = 16'h7000;
                7'd90: rom = 16'h7100;

                default: rom = 16'h0000;

            endcase
        end
    endfunction

    // SCCB
    reg       sccb_start;
    reg [7:0] w_addr, w_data;

    wire sccb_busy;
    wire sccb_done;
    wire sccb_nack;
    wire sda_low;

    reg [1:0] sda_s;

    initial begin
        sccb_start = 1'b0;
        w_addr = 8'd0;
        w_data = 8'd0;
        sda_s = 2'b11;
        done = 1'b0;
        ack_bad = 1'b0;
    end

    always @(posedge clk)
        sda_s <= {sda_s[0], siod};

    assign siod = sda_low ? 1'b0 : 1'bz;

    sccb_master #(
        .TICK_DIV(68)
    ) u_sccb (
        .clk(clk),
        .rst_n(rst_n),
        .start(sccb_start),
        .reg_addr(w_addr),
        .reg_data(w_data),
        .sda_in(sda_s[1]),
        .busy(sccb_busy),
        .done(sccb_done),
        .nack(sccb_nack),
        .sioc(sioc),
        .sda_low(sda_low)
    );

    localparam [2:0]
        I_POR  = 3'd0,
        I_LOAD = 3'd1,
        I_WAIT = 3'd2,
        I_GAP  = 3'd3,
        I_DONE = 3'd4;

    reg [2:0]  st;
    reg [6:0]  idx;
    reg [23:0] dly;
    reg        cb_applied;

    initial begin
        st = I_POR;
        idx = 7'd0;
        dly = 24'd0;
        cb_applied = 1'b0;
    end

    always @(posedge clk) begin

        if (!rst_n) begin
            st <= I_POR;
            idx <= 7'd0;
            dly <= 24'd0;
            done <= 1'b0;
            ack_bad <= 1'b0;
            sccb_start <= 1'b0;
            cb_applied <= 1'b0;
            w_addr <= 8'd0;
            w_data <= 8'd0;
        end

        else begin

            sccb_start <= 1'b0;

            case (st)

                I_POR: begin
                    if (dly == POR_CYCLES) begin
                        dly <= 24'd0;
                        idx <= 7'd0;
                        st <= I_LOAD;
                    end
                    else
                        dly <= dly + 24'd1;
                end

                I_LOAD: begin
                    {w_addr, w_data} <= rom(idx, colorbar);

                    if (idx == 7'd1)
                        cb_applied <= colorbar;

                    sccb_start <= 1'b1;
                    st <= I_WAIT;
                end

                I_WAIT: begin
                    if (sccb_done) begin
                        if (sccb_nack)
                            ack_bad <= 1'b1;

                        dly <= 24'd0;
                        st <= I_GAP;
                    end
                end

                I_GAP: begin
                    if (dly == ((idx == 7'd0) ?
                                RST_CYCLES : GAP_CYCLES)) begin

                        dly <= 24'd0;

                        if (idx == LAST)
                            st <= I_DONE;
                        else begin
                            idx <= idx + 7'd1;
                            st <= I_LOAD;
                        end
                    end
                    else
                        dly <= dly + 24'd1;
                end

                I_DONE: begin
                    done <= 1'b1;

                    if (colorbar != cb_applied) begin
                        done <= 1'b0;
                        idx <= 7'd1;
                        st <= I_LOAD;
                    end
                end

                default:
                    st <= I_POR;

            endcase
        end
    end

endmodule
