`include "verirust_params.vh"

module verirust_stage_score (
    clk,
    rst_n,
    en,
    phase_first,
    q_value,
    k_value,
    q_rd_addr,
    k_rd_addr,
    wr_en,
    wr_addr,
    wr_data
);

input clk;
input rst_n;
input en;
input phase_first;
input signed [15:0] q_value;
input signed [15:0] k_value;
output reg [15:0] q_rd_addr;
output reg [15:0] k_rd_addr;
output reg wr_en;
output reg [15:0] wr_addr;
output reg signed [15:0] wr_data;

reg [1:0] head_idx;
reg [4:0] tq_idx;
reg [4:0] tk_idx;
reg [4:0] d_idx;
reg signed [31:0] acc_reg;

integer head;
integer tq;
integer tk;
integer inner;
reg signed [31:0] prod32;
reg signed [31:0] tmp32;

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
    head = phase_first ? 0 : head_idx;
    tq = phase_first ? 0 : tq_idx;
    tk = phase_first ? 0 : tk_idx;
    inner = phase_first ? 0 : d_idx;
    q_rd_addr = tq * `VERIRUST_D_MODEL + head * `VERIRUST_D_HEAD + inner;
    k_rd_addr = tk * `VERIRUST_D_MODEL + head * `VERIRUST_D_HEAD + inner;
    wr_en = en && (inner == `VERIRUST_D_HEAD);
    wr_addr = (head * `VERIRUST_SEQ_LEN + tq) * `VERIRUST_SEQ_LEN + tk;
    tmp32 = requantize_q16_to_q8(acc_reg) * `VERIRUST_ATTN_SCALE_Q88;
    wr_data = requantize_q16_to_q8(tmp32);
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        head_idx <= 0;
        tq_idx <= 0;
        tk_idx <= 0;
        d_idx <= 0;
        acc_reg <= 32'sd0;
    end else if (en) begin
        head = phase_first ? 0 : head_idx;
        tq = phase_first ? 0 : tq_idx;
        tk = phase_first ? 0 : tk_idx;
        inner = phase_first ? 0 : d_idx;

        if (inner < `VERIRUST_D_HEAD) begin
            prod32 = q_value * k_value;
            if (inner == 0)
                acc_reg <= prod32;
            else
                acc_reg <= acc_reg + prod32;
        end

        if (inner == `VERIRUST_D_HEAD) begin
            d_idx <= 0;
            if (tk == (`VERIRUST_SEQ_LEN - 1)) begin
                tk_idx <= 0;
                if (tq == (`VERIRUST_SEQ_LEN - 1)) begin
                    tq_idx <= 0;
                    if (head == (`VERIRUST_N_HEADS - 1))
                        head_idx <= 0;
                    else
                        head_idx <= head + 1;
                end else begin
                    tq_idx <= tq + 1;
                    head_idx <= head;
                end
            end else begin
                tk_idx <= tk + 1;
                tq_idx <= tq;
                head_idx <= head;
            end
        end else begin
            head_idx <= head;
            tq_idx <= tq;
            tk_idx <= tk;
            d_idx <= inner + 1;
        end
    end
end

endmodule
