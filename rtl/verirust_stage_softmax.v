`include "verirust_params.vh"

module verirust_stage_softmax (
    clk,
    rst_n,
    en,
    phase_first,
    score_pre_value,
    exp_lut_value,
    recip_lut_value,
    score_pre_rd_addr,
    use_exp_lut,
    exp_lut_addr,
    use_recip_lut,
    recip_lut_addr,
    post_wr_en,
    post_wr_addr,
    post_wr_data,
    prob_wr_en,
    prob_wr_addr,
    prob_wr_data
);

input clk;
input rst_n;
input en;
input phase_first;
input signed [15:0] score_pre_value;
input signed [15:0] exp_lut_value;
input signed [15:0] recip_lut_value;
output reg [15:0] score_pre_rd_addr;
output reg use_exp_lut;
output reg [15:0] exp_lut_addr;
output reg use_recip_lut;
output reg [15:0] recip_lut_addr;
output reg post_wr_en;
output reg [15:0] post_wr_addr;
output reg signed [15:0] post_wr_data;
output reg prob_wr_en;
output reg [15:0] prob_wr_addr;
output reg signed [15:0] prob_wr_data;

reg [1:0] head_idx;
reg [4:0] tq_idx;
reg [5:0] step_idx;
reg signed [15:0] max_reg;
reg signed [31:0] sum_reg;
reg signed [15:0] inv_reg;
reg signed [15:0] exp_temp [0:`VERIRUST_SEQ_LEN-1];
reg signed [15:0] post_temp [0:`VERIRUST_SEQ_LEN-1];

integer head;
integer tq;
integer step;
integer tk;
integer row_base;
reg signed [15:0] masked_val;
reg signed [31:0] tmp32;
reg signed [15:0] clamped_val;

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

function [9:0] exp_lookup_addr;
    input signed [15:0] shifted_q88;
    integer local_clamped;
    begin
        local_clamped = shifted_q88;
        if (local_clamped < -2048)
            local_clamped = -2048;
        else if (local_clamped > 0)
            local_clamped = 0;
        exp_lookup_addr = ((local_clamped + 2048) * 1023) / 2048;
    end
endfunction

function [11:0] recip_lookup_addr_fn;
    input signed [31:0] value_q16;
    integer local_clamped;
    begin
        local_clamped = value_q16;
        if (local_clamped < 0)
            local_clamped = 0;
        else if (local_clamped > (16 * 65536))
            local_clamped = 16 * 65536;
        recip_lookup_addr_fn = (local_clamped * 4095) / (16 * 65536);
    end
endfunction

always @* begin
    head = phase_first ? 0 : head_idx;
    tq = phase_first ? 0 : tq_idx;
    step = phase_first ? 0 : step_idx;
    row_base = (head * `VERIRUST_SEQ_LEN + tq) * `VERIRUST_SEQ_LEN;

    score_pre_rd_addr = row_base;
    use_exp_lut = 1'b0;
    exp_lut_addr = 16'd0;
    use_recip_lut = 1'b0;
    recip_lut_addr = 16'd0;
    post_wr_en = 1'b0;
    post_wr_addr = 16'd0;
    post_wr_data = 16'sd0;
    prob_wr_en = 1'b0;
    prob_wr_addr = 16'd0;
    prob_wr_data = 16'sd0;

    if (step < `VERIRUST_SEQ_LEN) begin
        tk = step;
        score_pre_rd_addr = row_base + tk;
        masked_val = score_pre_value;
        if (tk > tq)
            masked_val = `VERIRUST_MASK_NEG;
        post_wr_en = en;
        post_wr_addr = row_base + tk;
        post_wr_data = masked_val;
    end else if (step < (2 * `VERIRUST_SEQ_LEN)) begin
        tk = step - `VERIRUST_SEQ_LEN;
        tmp32 = post_temp[tk] - max_reg;
        if (tmp32 < -2048)
            clamped_val = -16'sd2048;
        else if (tmp32 > 0)
            clamped_val = 16'sd0;
        else
            clamped_val = tmp32[15:0];
        use_exp_lut = 1'b1;
        exp_lut_addr = exp_lookup_addr(clamped_val);
    end else if (step == (2 * `VERIRUST_SEQ_LEN)) begin
        use_recip_lut = 1'b1;
        recip_lut_addr = recip_lookup_addr_fn(sum_reg <<< `VERIRUST_FRAC_BITS);
    end else begin
        tk = step - ((2 * `VERIRUST_SEQ_LEN) + 1);
        prob_wr_en = en;
        prob_wr_addr = row_base + tk;
        prob_wr_data = requantize_q16_to_q8(exp_temp[tk] * inv_reg);
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        head_idx <= 0;
        tq_idx <= 0;
        step_idx <= 0;
        max_reg <= -16'sd32768;
        sum_reg <= 32'sd0;
        inv_reg <= 16'sd0;
    end else if (en) begin
        head = phase_first ? 0 : head_idx;
        tq = phase_first ? 0 : tq_idx;
        step = phase_first ? 0 : step_idx;

        if (step < `VERIRUST_SEQ_LEN) begin
            tk = step;
            masked_val = score_pre_value;
            if (tk > tq)
                masked_val = `VERIRUST_MASK_NEG;
            post_temp[tk] <= masked_val;
            if (step == 0)
                max_reg <= masked_val;
            else if (masked_val > max_reg)
                max_reg <= masked_val;
        end else if (step < (2 * `VERIRUST_SEQ_LEN)) begin
            tk = step - `VERIRUST_SEQ_LEN;
            exp_temp[tk] <= exp_lut_value;
            if (tk == 0)
                sum_reg <= exp_lut_value;
            else
                sum_reg <= sum_reg + exp_lut_value;
        end else if (step == (2 * `VERIRUST_SEQ_LEN)) begin
            inv_reg <= recip_lut_value;
        end

        if (step == (3 * `VERIRUST_SEQ_LEN)) begin
            step_idx <= 0;
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
            head_idx <= head;
            tq_idx <= tq;
            step_idx <= step + 1;
        end
    end
end

endmodule
