module verirust_core (
    input  logic clk,
    input  logic rst_n,
    input  logic start,
    output logic done
);
`include "verirust_params.vh"

localparam int VOCAB_SIZE = `VERIRUST_VOCAB_SIZE;
localparam int SEQ_LEN = `VERIRUST_SEQ_LEN;
localparam int D_MODEL = `VERIRUST_D_MODEL;
localparam int N_HEADS = `VERIRUST_N_HEADS;
localparam int D_HEAD = `VERIRUST_D_HEAD;
localparam int D_FF = `VERIRUST_D_FF;

localparam int TOK_EMBEDDING_LEN = `VERIRUST_TOK_EMBEDDING_LEN;
localparam int POS_EMBEDDING_LEN = `VERIRUST_POS_EMBEDDING_LEN;
localparam int NORM_LEN = `VERIRUST_NORM_LEN;
localparam int MAT_DMODEL_DMODEL = `VERIRUST_MAT_DMODEL_DMODEL;
localparam int W1_LEN = `VERIRUST_W1_LEN;
localparam int W2_LEN = `VERIRUST_W2_LEN;
localparam int LM_HEAD_LEN = `VERIRUST_LM_HEAD_LEN;
localparam int SCORE_LEN = `VERIRUST_SCORE_LEN;

localparam int FRAC_BITS = `VERIRUST_FRAC_BITS;
localparam logic signed [15:0] MASK_NEG = `VERIRUST_MASK_NEG;
localparam logic signed [15:0] ATTN_SCALE_Q88 = `VERIRUST_ATTN_SCALE_Q88;
localparam int INV_D_MODEL_Q16 = `VERIRUST_INV_D_MODEL_Q16;
localparam int EPS_Q16 = `VERIRUST_EPS_Q16;
logic busy;

logic [7:0] tokens [0:SEQ_LEN-1];

logic signed [15:0] tok_embedding [0:TOK_EMBEDDING_LEN-1];
logic signed [15:0] pos_embedding [0:POS_EMBEDDING_LEN-1];
logic signed [15:0] norm1_weight [0:NORM_LEN-1];
logic signed [15:0] w_q [0:MAT_DMODEL_DMODEL-1];
logic signed [15:0] w_k [0:MAT_DMODEL_DMODEL-1];
logic signed [15:0] w_v [0:MAT_DMODEL_DMODEL-1];
logic signed [15:0] w_o [0:MAT_DMODEL_DMODEL-1];
logic signed [15:0] norm2_weight [0:NORM_LEN-1];
logic signed [15:0] w1 [0:W1_LEN-1];
logic signed [15:0] w2 [0:W2_LEN-1];
logic signed [15:0] lm_head [0:LM_HEAD_LEN-1];

logic signed [15:0] exp_lut [0:1023];
logic signed [15:0] rsqrt_lut [0:4095];
logic signed [15:0] recip_lut [0:4095];

logic signed [15:0] x_tok [0:SEQ_LEN*D_MODEL-1];
logic signed [15:0] x_in [0:SEQ_LEN*D_MODEL-1];
logic signed [15:0] norm1_out [0:SEQ_LEN*D_MODEL-1];
logic signed [15:0] q_flat [0:SEQ_LEN*D_MODEL-1];
logic signed [15:0] k_flat [0:SEQ_LEN*D_MODEL-1];
logic signed [15:0] v_flat [0:SEQ_LEN*D_MODEL-1];
logic signed [15:0] scores_pre_mask [0:SCORE_LEN-1];
logic signed [15:0] scores_post_mask [0:SCORE_LEN-1];
logic signed [15:0] attn_probs [0:SCORE_LEN-1];
logic signed [15:0] ctx_flat [0:SEQ_LEN*D_MODEL-1];
logic signed [15:0] attn_out [0:SEQ_LEN*D_MODEL-1];
logic signed [15:0] resid1_out [0:SEQ_LEN*D_MODEL-1];
logic signed [15:0] norm2_out [0:SEQ_LEN*D_MODEL-1];
logic signed [15:0] ffn_h1 [0:SEQ_LEN*D_FF-1];
logic signed [15:0] ffn_relu [0:SEQ_LEN*D_FF-1];
logic signed [15:0] ffn_out [0:SEQ_LEN*D_MODEL-1];
logic signed [15:0] block_out [0:SEQ_LEN*D_MODEL-1];
logic signed [15:0] logits [0:SEQ_LEN*VOCAB_SIZE-1];
logic signed [15:0] softmax_exp_vals [0:SEQ_LEN-1];

function automatic integer tc_idx(input integer t, input integer c);
    tc_idx = t * D_MODEL + c;
endfunction

function automatic integer score_idx(input integer h, input integer tq, input integer tk);
    score_idx = (h * SEQ_LEN + tq) * SEQ_LEN + tk;
endfunction

function automatic logic signed [15:0] saturate_i16(input integer value);
    if (value > 32767) begin
        saturate_i16 = 32767;
    end else if (value < -32768) begin
        saturate_i16 = -32768;
    end else begin
        saturate_i16 = value[15:0];
    end
endfunction

function automatic logic signed [15:0] requantize_q16_to_q8(input integer value);
    integer shifted;
    begin
        if (value >= 0) begin
            shifted = value >>> FRAC_BITS;
        end else begin
            shifted = -((-value) >>> FRAC_BITS);
        end
        requantize_q16_to_q8 = saturate_i16(shifted);
    end
endfunction

function automatic integer exp_lut_index(input integer shifted_q88);
    integer clamped;
    begin
        if (shifted_q88 < -2048) begin
            clamped = -2048;
        end else if (shifted_q88 > 0) begin
            clamped = 0;
        end else begin
            clamped = shifted_q88;
        end
        exp_lut_index = ((clamped + 2048) * 1023) / 2048;
    end
endfunction

function automatic integer rsqrt_lut_index(input integer value_q16);
    integer clamped;
    begin
        if (value_q16 < 0) begin
            clamped = 0;
        end else if (value_q16 > (8 * 65536)) begin
            clamped = 8 * 65536;
        end else begin
            clamped = value_q16;
        end
        rsqrt_lut_index = (clamped * 4095) / (8 * 65536);
    end
endfunction

function automatic integer recip_lut_index(input integer value_q16);
    integer clamped;
    begin
        if (value_q16 < 0) begin
            clamped = 0;
        end else if (value_q16 > (16 * 65536)) begin
            clamped = 16 * 65536;
        end else begin
            clamped = value_q16;
        end
        recip_lut_index = (clamped * 4095) / (16 * 65536);
    end
endfunction

task automatic run_inference;
    integer t;
    integer c;
    integer h;
    integer d;
    integer tq;
    integer tk;
    integer token_id;
    integer sum_sq;
    integer mean_sq;
    integer mean_sq_eps;
    integer rsqrt_value;
    integer acc;
    integer max_val;
    integer shifted;
    integer sum_exp;
    integer inv_sum;
    integer col;
    integer inner;
    begin
        for (t = 0; t < SEQ_LEN; t = t + 1) begin
            token_id = integer'(tokens[t]);
            for (c = 0; c < D_MODEL; c = c + 1) begin
                x_tok[tc_idx(t, c)] = tok_embedding[token_id * D_MODEL + c];
                x_in[tc_idx(t, c)] = saturate_i16(
                    integer'(tok_embedding[token_id * D_MODEL + c]) + integer'(pos_embedding[tc_idx(t, c)])
                );
            end
        end

        for (t = 0; t < SEQ_LEN; t = t + 1) begin
            sum_sq = 0;
            for (c = 0; c < D_MODEL; c = c + 1) begin
                sum_sq = sum_sq + x_in[tc_idx(t, c)] * x_in[tc_idx(t, c)];
            end
            mean_sq = (sum_sq * INV_D_MODEL_Q16) >>> 16;
            mean_sq_eps = mean_sq + EPS_Q16;
            rsqrt_value = integer'(rsqrt_lut[rsqrt_lut_index(mean_sq_eps)]);
            for (c = 0; c < D_MODEL; c = c + 1) begin
                norm1_out[tc_idx(t, c)] = requantize_q16_to_q8(
                    requantize_q16_to_q8(x_in[tc_idx(t, c)] * rsqrt_value) * norm1_weight[c]
                );
            end
        end

        for (t = 0; t < SEQ_LEN; t = t + 1) begin
            for (col = 0; col < D_MODEL; col = col + 1) begin
                acc = 0;
                for (inner = 0; inner < D_MODEL; inner = inner + 1) begin
                    acc = acc + norm1_out[t * D_MODEL + inner] * w_q[inner * D_MODEL + col];
                end
                q_flat[t * D_MODEL + col] = requantize_q16_to_q8(acc);
            end
        end

        for (t = 0; t < SEQ_LEN; t = t + 1) begin
            for (col = 0; col < D_MODEL; col = col + 1) begin
                acc = 0;
                for (inner = 0; inner < D_MODEL; inner = inner + 1) begin
                    acc = acc + norm1_out[t * D_MODEL + inner] * w_k[inner * D_MODEL + col];
                end
                k_flat[t * D_MODEL + col] = requantize_q16_to_q8(acc);
            end
        end

        for (t = 0; t < SEQ_LEN; t = t + 1) begin
            for (col = 0; col < D_MODEL; col = col + 1) begin
                acc = 0;
                for (inner = 0; inner < D_MODEL; inner = inner + 1) begin
                    acc = acc + norm1_out[t * D_MODEL + inner] * w_v[inner * D_MODEL + col];
                end
                v_flat[t * D_MODEL + col] = requantize_q16_to_q8(acc);
            end
        end

        for (h = 0; h < N_HEADS; h = h + 1) begin
            for (tq = 0; tq < SEQ_LEN; tq = tq + 1) begin
                for (tk = 0; tk < SEQ_LEN; tk = tk + 1) begin
                    acc = 0;
                    for (d = 0; d < D_HEAD; d = d + 1) begin
                        acc = acc
                            + q_flat[tc_idx(tq, h * D_HEAD + d)]
                            * k_flat[tc_idx(tk, h * D_HEAD + d)];
                    end
                    scores_pre_mask[score_idx(h, tq, tk)] = requantize_q16_to_q8(
                        requantize_q16_to_q8(acc) * ATTN_SCALE_Q88
                    );
                end
            end
        end

        for (h = 0; h < N_HEADS; h = h + 1) begin
            for (tq = 0; tq < SEQ_LEN; tq = tq + 1) begin
                for (tk = 0; tk < SEQ_LEN; tk = tk + 1) begin
                    if (tk > tq) begin
                        scores_post_mask[score_idx(h, tq, tk)] = MASK_NEG;
                    end else begin
                        scores_post_mask[score_idx(h, tq, tk)] = scores_pre_mask[score_idx(h, tq, tk)];
                    end
                end
            end
        end

        for (h = 0; h < N_HEADS; h = h + 1) begin
            for (tq = 0; tq < SEQ_LEN; tq = tq + 1) begin
                max_val = integer'(scores_post_mask[score_idx(h, tq, 0)]);
                for (tk = 1; tk < SEQ_LEN; tk = tk + 1) begin
                    if (integer'(scores_post_mask[score_idx(h, tq, tk)]) > max_val) begin
                        max_val = integer'(scores_post_mask[score_idx(h, tq, tk)]);
                    end
                end

                sum_exp = 0;
                for (tk = 0; tk < SEQ_LEN; tk = tk + 1) begin
                    shifted = integer'(scores_post_mask[score_idx(h, tq, tk)]) - max_val;
                    softmax_exp_vals[tk] = exp_lut[exp_lut_index(shifted)];
                    sum_exp = sum_exp + integer'(softmax_exp_vals[tk]);
                end

                inv_sum = integer'(recip_lut[recip_lut_index(sum_exp <<< 8)]);
                for (tk = 0; tk < SEQ_LEN; tk = tk + 1) begin
                    attn_probs[score_idx(h, tq, tk)] = requantize_q16_to_q8(softmax_exp_vals[tk] * inv_sum);
                end
            end
        end

        for (tq = 0; tq < SEQ_LEN; tq = tq + 1) begin
            for (c = 0; c < D_MODEL; c = c + 1) begin
                ctx_flat[tc_idx(tq, c)] = '0;
            end
        end

        for (h = 0; h < N_HEADS; h = h + 1) begin
            for (tq = 0; tq < SEQ_LEN; tq = tq + 1) begin
                for (d = 0; d < D_HEAD; d = d + 1) begin
                    acc = 0;
                    for (tk = 0; tk < SEQ_LEN; tk = tk + 1) begin
                        acc = acc
                            + attn_probs[score_idx(h, tq, tk)]
                            * v_flat[tc_idx(tk, h * D_HEAD + d)];
                    end
                    ctx_flat[tc_idx(tq, h * D_HEAD + d)] = requantize_q16_to_q8(acc);
                end
            end
        end

        for (t = 0; t < SEQ_LEN; t = t + 1) begin
            for (col = 0; col < D_MODEL; col = col + 1) begin
                acc = 0;
                for (inner = 0; inner < D_MODEL; inner = inner + 1) begin
                    acc = acc + ctx_flat[t * D_MODEL + inner] * w_o[inner * D_MODEL + col];
                end
                attn_out[t * D_MODEL + col] = requantize_q16_to_q8(acc);
            end
        end

        for (t = 0; t < SEQ_LEN; t = t + 1) begin
            for (c = 0; c < D_MODEL; c = c + 1) begin
                resid1_out[tc_idx(t, c)] = saturate_i16(integer'(x_in[tc_idx(t, c)]) + integer'(attn_out[tc_idx(t, c)]));
            end
        end

        for (t = 0; t < SEQ_LEN; t = t + 1) begin
            sum_sq = 0;
            for (c = 0; c < D_MODEL; c = c + 1) begin
                sum_sq = sum_sq + resid1_out[tc_idx(t, c)] * resid1_out[tc_idx(t, c)];
            end
            mean_sq = (sum_sq * INV_D_MODEL_Q16) >>> 16;
            mean_sq_eps = mean_sq + EPS_Q16;
            rsqrt_value = integer'(rsqrt_lut[rsqrt_lut_index(mean_sq_eps)]);
            for (c = 0; c < D_MODEL; c = c + 1) begin
                norm2_out[tc_idx(t, c)] = requantize_q16_to_q8(
                    requantize_q16_to_q8(resid1_out[tc_idx(t, c)] * rsqrt_value) * norm2_weight[c]
                );
            end
        end

        for (t = 0; t < SEQ_LEN; t = t + 1) begin
            for (col = 0; col < D_FF; col = col + 1) begin
                acc = 0;
                for (inner = 0; inner < D_MODEL; inner = inner + 1) begin
                    acc = acc + norm2_out[t * D_MODEL + inner] * w1[inner * D_FF + col];
                end
                ffn_h1[t * D_FF + col] = requantize_q16_to_q8(acc);
            end
        end

        for (t = 0; t < SEQ_LEN; t = t + 1) begin
            for (c = 0; c < D_FF; c = c + 1) begin
                if (ffn_h1[t * D_FF + c] < 0) begin
                    ffn_relu[t * D_FF + c] = '0;
                end else begin
                    ffn_relu[t * D_FF + c] = ffn_h1[t * D_FF + c];
                end
            end
        end

        for (t = 0; t < SEQ_LEN; t = t + 1) begin
            for (col = 0; col < D_MODEL; col = col + 1) begin
                acc = 0;
                for (inner = 0; inner < D_FF; inner = inner + 1) begin
                    acc = acc + ffn_relu[t * D_FF + inner] * w2[inner * D_MODEL + col];
                end
                ffn_out[t * D_MODEL + col] = requantize_q16_to_q8(acc);
            end
        end

        for (t = 0; t < SEQ_LEN; t = t + 1) begin
            for (c = 0; c < D_MODEL; c = c + 1) begin
                block_out[tc_idx(t, c)] = saturate_i16(integer'(resid1_out[tc_idx(t, c)]) + integer'(ffn_out[tc_idx(t, c)]));
            end
        end

        for (t = 0; t < SEQ_LEN; t = t + 1) begin
            for (col = 0; col < VOCAB_SIZE; col = col + 1) begin
                acc = 0;
                for (inner = 0; inner < D_MODEL; inner = inner + 1) begin
                    acc = acc + block_out[t * D_MODEL + inner] * lm_head[inner * VOCAB_SIZE + col];
                end
                logits[t * VOCAB_SIZE + col] = requantize_q16_to_q8(acc);
            end
        end
    end
endtask

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        busy <= 1'b0;
        done <= 1'b0;
    end else begin
        done <= 1'b0;
        if (start && !busy) begin
            busy <= 1'b1;
            run_inference();
            busy <= 1'b0;
            done <= 1'b1;
        end
    end
end

endmodule
