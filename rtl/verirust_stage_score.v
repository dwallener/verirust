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
reg [5:0] head_chan_base;
reg [15:0] q_row_base;
reg [15:0] k_row_base;
reg [15:0] score_head_base;
reg [15:0] score_row_base;
reg signed [31:0] acc_reg;
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
    q_rd_addr = (phase_first ? 16'd0 : q_row_base) + (phase_first ? 16'd0 : head_chan_base) + (phase_first ? 16'd0 : d_idx);
    k_rd_addr = (phase_first ? 16'd0 : k_row_base) + (phase_first ? 16'd0 : head_chan_base) + (phase_first ? 16'd0 : d_idx);
    wr_en = en && ((phase_first ? 5'd0 : d_idx) == `VERIRUST_D_HEAD);
    wr_addr = (phase_first ? 16'd0 : score_head_base) + (phase_first ? 16'd0 : score_row_base) + (phase_first ? 16'd0 : tk_idx);
    tmp32 = requantize_q16_to_q8(acc_reg) * `VERIRUST_ATTN_SCALE_Q88;
    wr_data = requantize_q16_to_q8(tmp32);
end

always @(posedge clk) begin
    if (!rst_n) begin
        head_idx <= 0;
        tq_idx <= 0;
        tk_idx <= 0;
        d_idx <= 0;
        head_chan_base <= 0;
        q_row_base <= 0;
        k_row_base <= 0;
        score_head_base <= 0;
        score_row_base <= 0;
        acc_reg <= 32'sd0;
    end else if (en) begin
        if ((phase_first ? 5'd0 : d_idx) < `VERIRUST_D_HEAD) begin
            prod32 = q_value * k_value;
            if ((phase_first ? 5'd0 : d_idx) == 0)
                acc_reg <= prod32;
            else
                acc_reg <= acc_reg + prod32;
        end

        if ((phase_first ? 5'd0 : d_idx) == `VERIRUST_D_HEAD) begin
            d_idx <= 0;
            if ((phase_first ? 5'd0 : tk_idx) == (`VERIRUST_SEQ_LEN - 1)) begin
                tk_idx <= 0;
                k_row_base <= 0;
                if ((phase_first ? 5'd0 : tq_idx) == (`VERIRUST_SEQ_LEN - 1)) begin
                    tq_idx <= 0;
                    q_row_base <= 0;
                    score_row_base <= 0;
                    if ((phase_first ? 2'd0 : head_idx) == (`VERIRUST_N_HEADS - 1)) begin
                        head_idx <= 0;
                        head_chan_base <= 0;
                        score_head_base <= 0;
                    end else begin
                        head_idx <= (phase_first ? 2'd0 : head_idx) + 1'b1;
                        head_chan_base <= (phase_first ? 6'd0 : head_chan_base) + `VERIRUST_D_HEAD;
                        score_head_base <= (phase_first ? 16'd0 : score_head_base) + (`VERIRUST_SEQ_LEN * `VERIRUST_SEQ_LEN);
                    end
                end else begin
                    tq_idx <= (phase_first ? 5'd0 : tq_idx) + 1'b1;
                    head_idx <= phase_first ? 2'd0 : head_idx;
                    head_chan_base <= phase_first ? 6'd0 : head_chan_base;
                    q_row_base <= (phase_first ? 16'd0 : q_row_base) + `VERIRUST_D_MODEL;
                    score_row_base <= (phase_first ? 16'd0 : score_row_base) + `VERIRUST_SEQ_LEN;
                end
            end else begin
                tk_idx <= (phase_first ? 5'd0 : tk_idx) + 1'b1;
                tq_idx <= phase_first ? 5'd0 : tq_idx;
                head_idx <= phase_first ? 2'd0 : head_idx;
                head_chan_base <= phase_first ? 6'd0 : head_chan_base;
                q_row_base <= phase_first ? 16'd0 : q_row_base;
                score_row_base <= phase_first ? 16'd0 : score_row_base;
                k_row_base <= (phase_first ? 16'd0 : k_row_base) + `VERIRUST_D_MODEL;
            end
        end else begin
            head_idx <= phase_first ? 2'd0 : head_idx;
            tq_idx <= phase_first ? 5'd0 : tq_idx;
            tk_idx <= phase_first ? 5'd0 : tk_idx;
            d_idx <= (phase_first ? 5'd0 : d_idx) + 1'b1;
            head_chan_base <= phase_first ? 6'd0 : head_chan_base;
            q_row_base <= phase_first ? 16'd0 : q_row_base;
            k_row_base <= phase_first ? 16'd0 : k_row_base;
            score_head_base <= phase_first ? 16'd0 : score_head_base;
            score_row_base <= phase_first ? 16'd0 : score_row_base;
        end
    end
end

endmodule
