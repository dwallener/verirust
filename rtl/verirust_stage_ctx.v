`include "verirust_params.vh"

module verirust_stage_ctx (
    clk,
    rst_n,
    en,
    phase_first,
    prob_value,
    v_value,
    prob_rd_addr,
    v_rd_addr,
    wr_en,
    wr_addr,
    wr_data
);

input clk;
input rst_n;
input en;
input phase_first;
input signed [15:0] prob_value;
input signed [15:0] v_value;
output reg [15:0] prob_rd_addr;
output reg [15:0] v_rd_addr;
output reg wr_en;
output reg [15:0] wr_addr;
output reg signed [15:0] wr_data;

reg [4:0] tq_idx;
reg [5:0] packed_idx;
reg [4:0] tk_idx;
reg signed [31:0] acc_reg;

integer tq;
integer packed_chan;
integer tk;
integer head;
integer chan;
reg signed [31:0] prod32;

function signed [15:0] saturate_i16;
    input signed [31:0] x;
    begin
        if (x > 32'sd32767)
            saturate_i16 = 16'sd32767;
        else if (x < -32'sd32768)
            saturate_i16 = -16'sd32768;
        else
            saturate_i16 = x[15:0];
    end
endfunction

function signed [15:0] requantize_q16_to_q8;
    input signed [31:0] x;
    reg signed [31:0] shifted;
    begin
        if (x >= 0)
            shifted = x >>> `VERIRUST_FRAC_BITS;
        else
            shifted = -((-x) >>> `VERIRUST_FRAC_BITS);
        requantize_q16_to_q8 = saturate_i16(shifted);
    end
endfunction

always @* begin
    tq = phase_first ? 0 : tq_idx;
    packed_chan = phase_first ? 0 : packed_idx;
    tk = phase_first ? 0 : tk_idx;
    if (packed_chan < `VERIRUST_D_HEAD) begin
        head = 0;
        chan = packed_chan;
    end else begin
        head = 1;
        chan = packed_chan - `VERIRUST_D_HEAD;
    end
    prob_rd_addr = (head * `VERIRUST_SEQ_LEN + tq) * `VERIRUST_SEQ_LEN + tk;
    v_rd_addr = tk * `VERIRUST_D_MODEL + head * `VERIRUST_D_HEAD + chan;
    wr_en = en && (tk == `VERIRUST_SEQ_LEN);
    wr_addr = tq * `VERIRUST_D_MODEL + packed_chan;
    wr_data = requantize_q16_to_q8(acc_reg);
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        tq_idx <= 0;
        packed_idx <= 0;
        tk_idx <= 0;
        acc_reg <= 32'sd0;
    end else if (en) begin
        tq = phase_first ? 0 : tq_idx;
        packed_chan = phase_first ? 0 : packed_idx;
        tk = phase_first ? 0 : tk_idx;

        if (packed_chan < `VERIRUST_D_HEAD) begin
            head = 0;
            chan = packed_chan;
        end else begin
            head = 1;
            chan = packed_chan - `VERIRUST_D_HEAD;
        end

        if (tk < `VERIRUST_SEQ_LEN) begin
            prod32 = prob_value * v_value;
            if (tk == 0)
                acc_reg <= prod32;
            else
                acc_reg <= acc_reg + prod32;
        end

        if (tk == `VERIRUST_SEQ_LEN) begin
            tk_idx <= 0;
            if (packed_chan == (`VERIRUST_D_MODEL - 1)) begin
                packed_idx <= 0;
                if (tq == (`VERIRUST_SEQ_LEN - 1))
                    tq_idx <= 0;
                else
                    tq_idx <= tq + 1;
            end else begin
                packed_idx <= packed_chan + 1;
                tq_idx <= tq;
            end
        end else begin
            tq_idx <= tq;
            packed_idx <= packed_chan;
            tk_idx <= tk + 1;
        end
    end
end

endmodule
