`include "verirust_params.vh"
`include "generated/verirust_frozen_consts.svh"

module verirust_frozen (
    clk,
    rst_n,
    start,
    tokens_flat,
    logits_rd_addr,
    logits_rd_data,
    phase,
    phase_index,
    done
);

input clk;
input rst_n;
input start;
input [`VERIRUST_SEQ_LEN*8-1:0] tokens_flat;
input [15:0] logits_rd_addr;
output reg signed [15:0] logits_rd_data;
output [4:0] phase;
output [17:0] phase_index;
output done;

parameter [4:0] PH_IDLE     = 5'd0;
parameter [4:0] PH_EMBED_TOK = 5'd1;
parameter [4:0] PH_EMBED_ADD = 5'd2;
parameter [4:0] PH_NORM1     = 5'd3;
parameter [4:0] PH_Q         = 5'd4;
parameter [4:0] PH_K         = 5'd5;
parameter [4:0] PH_V         = 5'd6;
parameter [4:0] PH_SCORE     = 5'd7;
parameter [4:0] PH_SOFTMAX   = 5'd8;
parameter [4:0] PH_CTX       = 5'd9;
parameter [4:0] PH_ATTN_OUT  = 5'd10;
parameter [4:0] PH_RESID1    = 5'd11;
parameter [4:0] PH_NORM2     = 5'd12;
parameter [4:0] PH_FFN1      = 5'd13;
parameter [4:0] PH_FFN1_RELU = 5'd14;
parameter [4:0] PH_FFN2      = 5'd15;
parameter [4:0] PH_RESID2    = 5'd16;
parameter [4:0] PH_LOGITS    = 5'd17;

reg signed [15:0] x_tok [0:`VERIRUST_SEQ_LEN*`VERIRUST_D_MODEL-1];
reg signed [15:0] x_in [0:`VERIRUST_SEQ_LEN*`VERIRUST_D_MODEL-1];
reg signed [15:0] norm1_out [0:`VERIRUST_SEQ_LEN*`VERIRUST_D_MODEL-1];
reg signed [15:0] q_flat [0:`VERIRUST_SEQ_LEN*`VERIRUST_D_MODEL-1];
reg signed [15:0] k_flat [0:`VERIRUST_SEQ_LEN*`VERIRUST_D_MODEL-1];
reg signed [15:0] v_flat [0:`VERIRUST_SEQ_LEN*`VERIRUST_D_MODEL-1];
reg signed [15:0] scores_pre_mask [0:`VERIRUST_SCORE_LEN-1];
reg signed [15:0] scores_post_mask [0:`VERIRUST_SCORE_LEN-1];
reg signed [15:0] attn_probs [0:`VERIRUST_SCORE_LEN-1];
reg signed [15:0] ctx_flat [0:`VERIRUST_SEQ_LEN*`VERIRUST_D_MODEL-1];
reg signed [15:0] attn_out [0:`VERIRUST_SEQ_LEN*`VERIRUST_D_MODEL-1];
reg signed [15:0] resid1_out [0:`VERIRUST_SEQ_LEN*`VERIRUST_D_MODEL-1];
reg signed [15:0] norm2_out [0:`VERIRUST_SEQ_LEN*`VERIRUST_D_MODEL-1];
reg signed [15:0] ffn_h1 [0:`VERIRUST_SEQ_LEN*`VERIRUST_D_FF-1];
reg signed [15:0] ffn_relu [0:`VERIRUST_SEQ_LEN*`VERIRUST_D_FF-1];
reg signed [15:0] ffn_out [0:`VERIRUST_SEQ_LEN*`VERIRUST_D_MODEL-1];
reg signed [15:0] block_out [0:`VERIRUST_SEQ_LEN*`VERIRUST_D_MODEL-1];
reg signed [15:0] logits_mem [0:`VERIRUST_SEQ_LEN*`VERIRUST_VOCAB_SIZE-1];


reg [4:0] embed_row_idx;
reg [5:0] embed_chan_idx;
reg [4:0] ffn1_row_idx;
reg [6:0] ffn1_col_idx;
reg [5:0] ffn1_inner_idx;

wire [4:0] ctrl_phase;
wire [17:0] ctrl_phase_index;
wire ctrl_done;

wire en_idle;
wire en_embed_tok;
wire en_embed_add;
wire en_norm1;
wire en_score;
wire en_softmax;
wire en_ctx;
wire en_resid1;
wire en_norm2;
wire en_ffn1;
wire en_ffn1_relu;
wire en_ffn2;
wire en_resid2;
wire en_logits;

integer idx;
integer token_idx;
reg signed [31:0] tmp32;
wire [7:0] embed_tok_token_rd_addr;
wire [15:0] embed_tok_tok_embed_addr;
wire embed_tok_wr_en;
wire [15:0] embed_tok_wr_addr;
wire signed [15:0] embed_tok_wr_data;
wire [15:0] embed_add_x_tok_rd_addr;
wire [15:0] embed_add_pos_addr;
wire embed_add_wr_en;
wire [15:0] embed_add_wr_addr;
wire signed [15:0] embed_add_wr_data;
wire [15:0] ffn1_lhs_rd_addr;
wire [15:0] ffn1_weight_addr;
wire ffn1_wr_en;
wire [15:0] ffn1_wr_addr;
wire signed [15:0] ffn1_wr_data;
wire [15:0] relu_rd_addr;
wire relu_wr_en;
wire [15:0] relu_wr_addr;
wire signed [15:0] relu_wr_data;
wire [15:0] norm1_in_rd_addr;
wire [15:0] norm1_weight_addr;
wire [15:0] norm1_rsqrt_addr;
wire norm1_use_weight;
wire norm1_use_rsqrt;
wire norm1_wr_en;
wire [15:0] norm1_wr_addr;
wire signed [15:0] norm1_wr_data;
wire [15:0] norm2_in_rd_addr;
wire [15:0] norm2_weight_addr;
wire [15:0] norm2_rsqrt_addr;
wire norm2_use_weight;
wire norm2_use_rsqrt;
wire norm2_wr_en;
wire [15:0] norm2_wr_addr;
wire signed [15:0] norm2_wr_data;
wire [15:0] resid1_rd_addr;
wire resid1_wr_en;
wire [15:0] resid1_wr_addr;
wire signed [15:0] resid1_wr_data;
wire [15:0] resid2_rd_addr;
wire resid2_wr_en;
wire [15:0] resid2_wr_addr;
wire signed [15:0] resid2_wr_data;
wire [15:0] q_lhs_rd_addr;
wire [15:0] q_weight_addr;
wire q_wr_en;
wire [15:0] q_wr_addr;
wire signed [15:0] q_wr_data;
wire [15:0] k_lhs_rd_addr;
wire [15:0] k_weight_addr;
wire k_wr_en;
wire [15:0] k_wr_addr;
wire signed [15:0] k_wr_data;
wire [15:0] v_lhs_rd_addr;
wire [15:0] v_weight_addr;
wire v_wr_en;
wire [15:0] v_wr_addr;
wire signed [15:0] v_wr_data;
wire [15:0] attn_out_lhs_rd_addr;
wire [15:0] attn_out_weight_addr;
wire attn_out_wr_en;
wire [15:0] attn_out_wr_addr;
wire signed [15:0] attn_out_wr_data;
wire [15:0] ffn2_lhs_rd_addr;
wire [15:0] ffn2_weight_addr;
wire ffn2_wr_en;
wire [15:0] ffn2_wr_addr;
wire signed [15:0] ffn2_wr_data;
wire [15:0] logits_lhs_rd_addr;
wire [15:0] logits_weight_addr;
wire logits_wr_en;
wire [15:0] logits_wr_addr;
wire signed [15:0] logits_wr_data;
wire [15:0] score_q_rd_addr;
wire [15:0] score_k_rd_addr;
wire score_wr_en;
wire [15:0] score_wr_addr;
wire signed [15:0] score_wr_data;
wire [15:0] softmax_score_pre_rd_addr;
wire softmax_use_exp_lut;
wire [15:0] softmax_exp_lut_addr;
wire softmax_use_recip_lut;
wire [15:0] softmax_recip_lut_addr;
wire softmax_post_wr_en;
wire [15:0] softmax_post_wr_addr;
wire signed [15:0] softmax_post_wr_data;
wire softmax_prob_wr_en;
wire [15:0] softmax_prob_wr_addr;
wire signed [15:0] softmax_prob_wr_data;
wire [15:0] ctx_prob_rd_addr;
wire [15:0] ctx_v_rd_addr;
wire ctx_wr_en;
wire [15:0] ctx_wr_addr;
wire signed [15:0] ctx_wr_data;

verirust_ctrl ctrl (
    .clk(clk),
    .rst_n(rst_n),
    .start(start),
    .phase(ctrl_phase),
    .phase_index(ctrl_phase_index),
    .phase_active(),
    .done(ctrl_done)
);

assign phase = ctrl_phase;
assign phase_index = ctrl_phase_index;
assign done = ctrl_done;

assign en_idle    = (ctrl_phase == PH_IDLE);
assign en_embed_tok = (ctrl_phase == PH_EMBED_TOK);
assign en_embed_add = (ctrl_phase == PH_EMBED_ADD);
assign en_norm1   = (ctrl_phase == PH_NORM1);
assign en_score   = (ctrl_phase == PH_SCORE);
assign en_softmax = (ctrl_phase == PH_SOFTMAX);
assign en_ctx     = (ctrl_phase == PH_CTX);
assign en_resid1  = (ctrl_phase == PH_RESID1);
assign en_norm2   = (ctrl_phase == PH_NORM2);
assign en_ffn1    = (ctrl_phase == PH_FFN1);
assign en_ffn1_relu = (ctrl_phase == PH_FFN1_RELU);
assign en_ffn2    = (ctrl_phase == PH_FFN2);
assign en_resid2  = (ctrl_phase == PH_RESID2);
assign en_logits  = (ctrl_phase == PH_LOGITS);

function [7:0] frozen_token;
    input integer tok_idx;
    integer bit_idx;
    begin
        bit_idx = tok_idx * 8;
        frozen_token = tokens_flat[bit_idx +: 8];
    end
endfunction

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

verirust_stage_embed_tok stage_embed_tok (
    .clk(clk),
    .rst_n(rst_n),
    .en(en_embed_tok),
    .phase_first(ctrl_phase_index == 0),
    .token_value(frozen_token(embed_tok_token_rd_addr)),
    .tok_embed_value(frozen_tok_embedding(embed_tok_tok_embed_addr)),
    .token_rd_addr(embed_tok_token_rd_addr),
    .tok_embed_addr(embed_tok_tok_embed_addr),
    .wr_en(embed_tok_wr_en),
    .wr_addr(embed_tok_wr_addr),
    .wr_data(embed_tok_wr_data)
);

verirust_stage_embed_add stage_embed_add (
    .clk(clk),
    .rst_n(rst_n),
    .en(en_embed_add),
    .phase_first(ctrl_phase_index == 0),
    .x_tok_value(x_tok[embed_add_x_tok_rd_addr]),
    .pos_value(frozen_pos_embedding(embed_add_pos_addr)),
    .x_tok_rd_addr(embed_add_x_tok_rd_addr),
    .pos_addr(embed_add_pos_addr),
    .wr_en(embed_add_wr_en),
    .wr_addr(embed_add_wr_addr),
    .wr_data(embed_add_wr_data)
);

verirust_stage_ffn1 stage_ffn1 (
    .clk(clk),
    .rst_n(rst_n),
    .en(en_ffn1),
    .phase_first(ctrl_phase_index == 0),
    .lhs_value(norm2_out[ffn1_lhs_rd_addr]),
    .weight_value(frozen_w1(ffn1_weight_addr)),
    .lhs_rd_addr(ffn1_lhs_rd_addr),
    .weight_addr(ffn1_weight_addr),
    .wr_en(ffn1_wr_en),
    .wr_addr(ffn1_wr_addr),
    .wr_data(ffn1_wr_data)
);

verirust_stage_relu stage_relu (
    .clk(clk),
    .rst_n(rst_n),
    .en(en_ffn1_relu),
    .phase_first(ctrl_phase_index == 0),
    .in_value(ffn_h1[relu_rd_addr]),
    .rd_addr(relu_rd_addr),
    .wr_en(relu_wr_en),
    .wr_addr(relu_wr_addr),
    .wr_data(relu_wr_data)
);

verirust_stage_rmsnorm #(
    .ROWS(`VERIRUST_SEQ_LEN),
    .COLS(`VERIRUST_D_MODEL),
    .INV_D_MODEL_Q16(`VERIRUST_INV_D_MODEL_Q16),
    .EPS_Q16(`VERIRUST_EPS_Q16)
) stage_norm1 (
    .clk(clk),
    .rst_n(rst_n),
    .en(en_norm1),
    .phase_first(ctrl_phase_index == 0),
    .in_value(x_in[norm1_in_rd_addr]),
    .weight_value(frozen_norm1_weight(norm1_weight_addr)),
    .rsqrt_value(frozen_rsqrt_lut(norm1_rsqrt_addr)),
    .in_rd_addr(norm1_in_rd_addr),
    .weight_addr(norm1_weight_addr),
    .rsqrt_addr(norm1_rsqrt_addr),
    .use_weight(norm1_use_weight),
    .use_rsqrt(norm1_use_rsqrt),
    .wr_en(norm1_wr_en),
    .wr_addr(norm1_wr_addr),
    .wr_data(norm1_wr_data)
);

verirust_stage_rmsnorm #(
    .ROWS(`VERIRUST_SEQ_LEN),
    .COLS(`VERIRUST_D_MODEL),
    .INV_D_MODEL_Q16(`VERIRUST_INV_D_MODEL_Q16),
    .EPS_Q16(`VERIRUST_EPS_Q16)
) stage_norm2 (
    .clk(clk),
    .rst_n(rst_n),
    .en(en_norm2),
    .phase_first(ctrl_phase_index == 0),
    .in_value(resid1_out[norm2_in_rd_addr]),
    .weight_value(frozen_norm2_weight(norm2_weight_addr)),
    .rsqrt_value(frozen_rsqrt_lut(norm2_rsqrt_addr)),
    .in_rd_addr(norm2_in_rd_addr),
    .weight_addr(norm2_weight_addr),
    .rsqrt_addr(norm2_rsqrt_addr),
    .use_weight(norm2_use_weight),
    .use_rsqrt(norm2_use_rsqrt),
    .wr_en(norm2_wr_en),
    .wr_addr(norm2_wr_addr),
    .wr_data(norm2_wr_data)
);

verirust_stage_resid #(
    .LEN(`VERIRUST_SEQ_LEN * `VERIRUST_D_MODEL)
) stage_resid1 (
    .clk(clk),
    .rst_n(rst_n),
    .en(en_resid1),
    .phase_first(ctrl_phase_index == 0),
    .a_value(x_in[resid1_rd_addr]),
    .b_value(attn_out[resid1_rd_addr]),
    .rd_addr(resid1_rd_addr),
    .wr_en(resid1_wr_en),
    .wr_addr(resid1_wr_addr),
    .wr_data(resid1_wr_data)
);

verirust_stage_resid #(
    .LEN(`VERIRUST_SEQ_LEN * `VERIRUST_D_MODEL)
) stage_resid2 (
    .clk(clk),
    .rst_n(rst_n),
    .en(en_resid2),
    .phase_first(ctrl_phase_index == 0),
    .a_value(resid1_out[resid2_rd_addr]),
    .b_value(ffn_out[resid2_rd_addr]),
    .rd_addr(resid2_rd_addr),
    .wr_en(resid2_wr_en),
    .wr_addr(resid2_wr_addr),
    .wr_data(resid2_wr_data)
);

verirust_stage_matmul #(
    .ROWS(`VERIRUST_SEQ_LEN),
    .COLS(`VERIRUST_D_MODEL),
    .INNER(`VERIRUST_D_MODEL)
) stage_q (
    .clk(clk),
    .rst_n(rst_n),
    .en(ctrl_phase == PH_Q),
    .phase_first(ctrl_phase_index == 0),
    .lhs_value(norm1_out[q_lhs_rd_addr]),
    .rhs_value(frozen_w_q(q_weight_addr)),
    .lhs_rd_addr(q_lhs_rd_addr),
    .rhs_addr(q_weight_addr),
    .wr_en(q_wr_en),
    .wr_addr(q_wr_addr),
    .wr_data(q_wr_data)
);

verirust_stage_matmul #(
    .ROWS(`VERIRUST_SEQ_LEN),
    .COLS(`VERIRUST_D_MODEL),
    .INNER(`VERIRUST_D_MODEL)
) stage_k (
    .clk(clk),
    .rst_n(rst_n),
    .en(ctrl_phase == PH_K),
    .phase_first(ctrl_phase_index == 0),
    .lhs_value(norm1_out[k_lhs_rd_addr]),
    .rhs_value(frozen_w_k(k_weight_addr)),
    .lhs_rd_addr(k_lhs_rd_addr),
    .rhs_addr(k_weight_addr),
    .wr_en(k_wr_en),
    .wr_addr(k_wr_addr),
    .wr_data(k_wr_data)
);

verirust_stage_matmul #(
    .ROWS(`VERIRUST_SEQ_LEN),
    .COLS(`VERIRUST_D_MODEL),
    .INNER(`VERIRUST_D_MODEL)
) stage_v (
    .clk(clk),
    .rst_n(rst_n),
    .en(ctrl_phase == PH_V),
    .phase_first(ctrl_phase_index == 0),
    .lhs_value(norm1_out[v_lhs_rd_addr]),
    .rhs_value(frozen_w_v(v_weight_addr)),
    .lhs_rd_addr(v_lhs_rd_addr),
    .rhs_addr(v_weight_addr),
    .wr_en(v_wr_en),
    .wr_addr(v_wr_addr),
    .wr_data(v_wr_data)
);

verirust_stage_matmul #(
    .ROWS(`VERIRUST_SEQ_LEN),
    .COLS(`VERIRUST_D_MODEL),
    .INNER(`VERIRUST_D_MODEL)
) stage_attn_out (
    .clk(clk),
    .rst_n(rst_n),
    .en(ctrl_phase == PH_ATTN_OUT),
    .phase_first(ctrl_phase_index == 0),
    .lhs_value(ctx_flat[attn_out_lhs_rd_addr]),
    .rhs_value(frozen_w_o(attn_out_weight_addr)),
    .lhs_rd_addr(attn_out_lhs_rd_addr),
    .rhs_addr(attn_out_weight_addr),
    .wr_en(attn_out_wr_en),
    .wr_addr(attn_out_wr_addr),
    .wr_data(attn_out_wr_data)
);

verirust_stage_matmul #(
    .ROWS(`VERIRUST_SEQ_LEN),
    .COLS(`VERIRUST_D_MODEL),
    .INNER(`VERIRUST_D_FF)
) stage_ffn2 (
    .clk(clk),
    .rst_n(rst_n),
    .en(en_ffn2),
    .phase_first(ctrl_phase_index == 0),
    .lhs_value(ffn_relu[ffn2_lhs_rd_addr]),
    .rhs_value(frozen_w2(ffn2_weight_addr)),
    .lhs_rd_addr(ffn2_lhs_rd_addr),
    .rhs_addr(ffn2_weight_addr),
    .wr_en(ffn2_wr_en),
    .wr_addr(ffn2_wr_addr),
    .wr_data(ffn2_wr_data)
);

verirust_stage_matmul #(
    .ROWS(`VERIRUST_SEQ_LEN),
    .COLS(`VERIRUST_VOCAB_SIZE),
    .INNER(`VERIRUST_D_MODEL)
) stage_logits (
    .clk(clk),
    .rst_n(rst_n),
    .en(en_logits),
    .phase_first(ctrl_phase_index == 0),
    .lhs_value(block_out[logits_lhs_rd_addr]),
    .rhs_value(frozen_lm_head(logits_weight_addr)),
    .lhs_rd_addr(logits_lhs_rd_addr),
    .rhs_addr(logits_weight_addr),
    .wr_en(logits_wr_en),
    .wr_addr(logits_wr_addr),
    .wr_data(logits_wr_data)
);

verirust_stage_score stage_score (
    .clk(clk),
    .rst_n(rst_n),
    .en(en_score),
    .phase_first(ctrl_phase_index == 0),
    .q_value(q_flat[score_q_rd_addr]),
    .k_value(k_flat[score_k_rd_addr]),
    .q_rd_addr(score_q_rd_addr),
    .k_rd_addr(score_k_rd_addr),
    .wr_en(score_wr_en),
    .wr_addr(score_wr_addr),
    .wr_data(score_wr_data)
);

verirust_stage_softmax stage_softmax (
    .clk(clk),
    .rst_n(rst_n),
    .en(en_softmax),
    .phase_first(ctrl_phase_index == 0),
    .score_pre_value(scores_pre_mask[softmax_score_pre_rd_addr]),
    .exp_lut_value(frozen_exp_lut(softmax_exp_lut_addr)),
    .recip_lut_value(frozen_recip_lut(softmax_recip_lut_addr)),
    .score_pre_rd_addr(softmax_score_pre_rd_addr),
    .use_exp_lut(softmax_use_exp_lut),
    .exp_lut_addr(softmax_exp_lut_addr),
    .use_recip_lut(softmax_use_recip_lut),
    .recip_lut_addr(softmax_recip_lut_addr),
    .post_wr_en(softmax_post_wr_en),
    .post_wr_addr(softmax_post_wr_addr),
    .post_wr_data(softmax_post_wr_data),
    .prob_wr_en(softmax_prob_wr_en),
    .prob_wr_addr(softmax_prob_wr_addr),
    .prob_wr_data(softmax_prob_wr_data)
);

verirust_stage_ctx stage_ctx (
    .clk(clk),
    .rst_n(rst_n),
    .en(en_ctx),
    .phase_first(ctrl_phase_index == 0),
    .prob_value(attn_probs[ctx_prob_rd_addr]),
    .v_value(v_flat[ctx_v_rd_addr]),
    .prob_rd_addr(ctx_prob_rd_addr),
    .v_rd_addr(ctx_v_rd_addr),
    .wr_en(ctx_wr_en),
    .wr_addr(ctx_wr_addr),
    .wr_data(ctx_wr_data)
);

always @(posedge clk) begin
    logits_rd_data <= logits_mem[logits_rd_addr];
end

always @(posedge clk) begin
    if (embed_tok_wr_en) begin
        x_tok[embed_tok_wr_addr] <= embed_tok_wr_data;
    end
end

always @(posedge clk) begin
    if (embed_add_wr_en) begin
        x_in[embed_add_wr_addr] <= embed_add_wr_data;
    end
end

always @(posedge clk) begin
    if (norm1_wr_en) begin
        norm1_out[norm1_wr_addr] <= norm1_wr_data;
    end
end

always @(posedge clk) begin
    if (q_wr_en) begin
        q_flat[q_wr_addr] <= q_wr_data;
    end
end

always @(posedge clk) begin
    if (k_wr_en) begin
        k_flat[k_wr_addr] <= k_wr_data;
    end
end

always @(posedge clk) begin
    if (v_wr_en) begin
        v_flat[v_wr_addr] <= v_wr_data;
    end
end

always @(posedge clk) begin
    if (score_wr_en) begin
        scores_pre_mask[score_wr_addr] <= score_wr_data;
    end
end

always @(posedge clk) begin
    if (softmax_post_wr_en) begin
        scores_post_mask[softmax_post_wr_addr] <= softmax_post_wr_data;
    end
end

always @(posedge clk) begin
    if (softmax_prob_wr_en) begin
        attn_probs[softmax_prob_wr_addr] <= softmax_prob_wr_data;
    end
end

always @(posedge clk) begin
    if (ctx_wr_en) begin
        ctx_flat[ctx_wr_addr] <= ctx_wr_data;
    end
end

always @(posedge clk) begin
    if (resid1_wr_en) begin
        resid1_out[resid1_wr_addr] <= resid1_wr_data;
    end
end

always @(posedge clk) begin
    if (norm2_wr_en) begin
        norm2_out[norm2_wr_addr] <= norm2_wr_data;
    end
end

always @(posedge clk) begin
    if (ffn1_wr_en) begin
        ffn_h1[ffn1_wr_addr] <= ffn1_wr_data;
    end
end

always @(posedge clk) begin
    if (relu_wr_en) begin
        ffn_relu[relu_wr_addr] <= relu_wr_data;
    end
end

always @(posedge clk) begin
    if (attn_out_wr_en) begin
        attn_out[attn_out_wr_addr] <= attn_out_wr_data;
    end
end

always @(posedge clk) begin
    if (ffn2_wr_en) begin
        ffn_out[ffn2_wr_addr] <= ffn2_wr_data;
    end
end

always @(posedge clk) begin
    if (resid2_wr_en) begin
        block_out[resid2_wr_addr] <= resid2_wr_data;
    end
end

always @(posedge clk) begin
    if (logits_wr_en) begin
        logits_mem[logits_wr_addr] <= logits_wr_data;
    end
end

endmodule
