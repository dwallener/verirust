`include "verirust_params.vh"

module verirust_flexible_store (
    clk,
    rst_n,
    cfg_we,
    cfg_space,
    cfg_addr,
    cfg_wdata,
    token_we,
    token_addr,
    token_wdata,
    token_rd_addr,
    token_rd_data,
    rd0_space,
    rd0_addr,
    rd0_data,
    rd1_space,
    rd1_addr,
    rd1_data
);

input clk;
input rst_n;
input cfg_we;
input [3:0] cfg_space;
input [15:0] cfg_addr;
input signed [15:0] cfg_wdata;
input token_we;
input [7:0] token_addr;
input [7:0] token_wdata;
input [7:0] token_rd_addr;
output reg [7:0] token_rd_data;
input [3:0] rd0_space;
input [15:0] rd0_addr;
output reg signed [15:0] rd0_data;
input [3:0] rd1_space;
input [15:0] rd1_addr;
output reg signed [15:0] rd1_data;

parameter [3:0] CFG_TOK_EMBED = 4'd0;
parameter [3:0] CFG_POS_EMBED = 4'd1;
parameter [3:0] CFG_NORM1     = 4'd2;
parameter [3:0] CFG_W_Q       = 4'd3;
parameter [3:0] CFG_W_K       = 4'd4;
parameter [3:0] CFG_W_V       = 4'd5;
parameter [3:0] CFG_W_O       = 4'd6;
parameter [3:0] CFG_NORM2     = 4'd7;
parameter [3:0] CFG_W1        = 4'd8;
parameter [3:0] CFG_W2        = 4'd9;
parameter [3:0] CFG_LM_HEAD   = 4'd10;
parameter [3:0] CFG_EXP_LUT   = 4'd11;
parameter [3:0] CFG_RSQRT_LUT = 4'd12;
parameter [3:0] CFG_RECIP_LUT = 4'd13;

reg [7:0] token_mem [0:`VERIRUST_SEQ_LEN-1];
reg signed [15:0] tok_embedding [0:`VERIRUST_TOK_EMBEDDING_LEN-1];
reg signed [15:0] pos_embedding [0:`VERIRUST_POS_EMBEDDING_LEN-1];
reg signed [15:0] norm1_weight [0:`VERIRUST_NORM_LEN-1];
reg signed [15:0] w_q [0:`VERIRUST_MAT_DMODEL_DMODEL-1];
reg signed [15:0] w_k [0:`VERIRUST_MAT_DMODEL_DMODEL-1];
reg signed [15:0] w_v [0:`VERIRUST_MAT_DMODEL_DMODEL-1];
reg signed [15:0] w_o [0:`VERIRUST_MAT_DMODEL_DMODEL-1];
reg signed [15:0] norm2_weight [0:`VERIRUST_NORM_LEN-1];
reg signed [15:0] w1 [0:`VERIRUST_W1_LEN-1];
reg signed [15:0] w2 [0:`VERIRUST_W2_LEN-1];
reg signed [15:0] lm_head [0:`VERIRUST_LM_HEAD_LEN-1];
reg signed [15:0] exp_lut [0:1023];
reg signed [15:0] rsqrt_lut [0:4095];
reg signed [15:0] recip_lut [0:4095];

function signed [15:0] read_space_word;
    input [3:0] space;
    input [15:0] addr;
    begin
        case (space)
            CFG_TOK_EMBED: read_space_word = tok_embedding[addr];
            CFG_POS_EMBED: read_space_word = pos_embedding[addr];
            CFG_NORM1:     read_space_word = norm1_weight[addr];
            CFG_W_Q:       read_space_word = w_q[addr];
            CFG_W_K:       read_space_word = w_k[addr];
            CFG_W_V:       read_space_word = w_v[addr];
            CFG_W_O:       read_space_word = w_o[addr];
            CFG_NORM2:     read_space_word = norm2_weight[addr];
            CFG_W1:        read_space_word = w1[addr];
            CFG_W2:        read_space_word = w2[addr];
            CFG_LM_HEAD:   read_space_word = lm_head[addr];
            CFG_EXP_LUT:   read_space_word = exp_lut[addr];
            CFG_RSQRT_LUT: read_space_word = rsqrt_lut[addr];
            CFG_RECIP_LUT: read_space_word = recip_lut[addr];
            default:       read_space_word = 16'sd0;
        endcase
    end
endfunction

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
    end else begin
        if (cfg_we) begin
            case (cfg_space)
                CFG_TOK_EMBED: tok_embedding[cfg_addr] <= cfg_wdata;
                CFG_POS_EMBED: pos_embedding[cfg_addr] <= cfg_wdata;
                CFG_NORM1:     norm1_weight[cfg_addr] <= cfg_wdata;
                CFG_W_Q:       w_q[cfg_addr] <= cfg_wdata;
                CFG_W_K:       w_k[cfg_addr] <= cfg_wdata;
                CFG_W_V:       w_v[cfg_addr] <= cfg_wdata;
                CFG_W_O:       w_o[cfg_addr] <= cfg_wdata;
                CFG_NORM2:     norm2_weight[cfg_addr] <= cfg_wdata;
                CFG_W1:        w1[cfg_addr] <= cfg_wdata;
                CFG_W2:        w2[cfg_addr] <= cfg_wdata;
                CFG_LM_HEAD:   lm_head[cfg_addr] <= cfg_wdata;
                CFG_EXP_LUT:   exp_lut[cfg_addr] <= cfg_wdata;
                CFG_RSQRT_LUT: rsqrt_lut[cfg_addr] <= cfg_wdata;
                CFG_RECIP_LUT: recip_lut[cfg_addr] <= cfg_wdata;
            endcase
        end
        if (token_we)
            token_mem[token_addr] <= token_wdata;
    end
end

always @* begin
    token_rd_data = token_mem[token_rd_addr];
    rd0_data = read_space_word(rd0_space, rd0_addr);
    rd1_data = read_space_word(rd1_space, rd1_addr);
end

endmodule
