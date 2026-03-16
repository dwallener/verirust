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
reg [15:0] tq_base;
reg [15:0] tk_base;
reg [15:0] prob_head_base;
reg signed [31:0] acc_reg;
reg signed [31:0] prod32;
reg [5:0] chan_idx;
reg [5:0] head_chan_base;

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
    if ((phase_first ? 6'd0 : packed_idx) < `VERIRUST_D_HEAD) begin
        chan_idx = phase_first ? 6'd0 : packed_idx;
        head_chan_base = 6'd0;
    end else begin
        chan_idx = (phase_first ? 6'd0 : packed_idx) - `VERIRUST_D_HEAD;
        head_chan_base = `VERIRUST_D_HEAD;
    end
    prob_rd_addr = (phase_first ? 16'd0 : prob_head_base) + (phase_first ? 16'd0 : tk_idx);
    v_rd_addr = (phase_first ? 16'd0 : tk_base) + head_chan_base + chan_idx;
    wr_en = en && ((phase_first ? 5'd0 : tk_idx) == `VERIRUST_SEQ_LEN);
    wr_addr = (phase_first ? 16'd0 : tq_base) + (phase_first ? 16'd0 : packed_idx);
    wr_data = requantize_q16_to_q8(acc_reg);
end

always @(posedge clk) begin
    if (!rst_n) begin
        tq_idx <= 0;
        packed_idx <= 0;
        tk_idx <= 0;
        tq_base <= 0;
        tk_base <= 0;
        prob_head_base <= 0;
        acc_reg <= 32'sd0;
    end else if (en) begin
        if ((phase_first ? 5'd0 : tk_idx) < `VERIRUST_SEQ_LEN) begin
            prod32 = prob_value * v_value;
            if ((phase_first ? 5'd0 : tk_idx) == 0)
                acc_reg <= prod32;
            else
                acc_reg <= acc_reg + prod32;
        end

        if ((phase_first ? 5'd0 : tk_idx) == `VERIRUST_SEQ_LEN) begin
            tk_idx <= 0;
            tk_base <= 0;
            if ((phase_first ? 6'd0 : packed_idx) == (`VERIRUST_D_MODEL - 1)) begin
                packed_idx <= 0;
                if ((phase_first ? 5'd0 : tq_idx) == (`VERIRUST_SEQ_LEN - 1)) begin
                    tq_idx <= 0;
                    tq_base <= 0;
                    prob_head_base <= 0;
                end else begin
                    tq_idx <= (phase_first ? 5'd0 : tq_idx) + 1'b1;
                    tq_base <= (phase_first ? 16'd0 : tq_base) + `VERIRUST_D_MODEL;
                    prob_head_base <= (phase_first ? 16'd0 : prob_head_base) + `VERIRUST_SEQ_LEN;
                end
            end else begin
                packed_idx <= (phase_first ? 6'd0 : packed_idx) + 1'b1;
                tq_idx <= phase_first ? 5'd0 : tq_idx;
                tq_base <= phase_first ? 16'd0 : tq_base;
                prob_head_base <= phase_first ? 16'd0 : prob_head_base;
            end
        end else begin
            tq_idx <= phase_first ? 5'd0 : tq_idx;
            packed_idx <= phase_first ? 6'd0 : packed_idx;
            tk_idx <= (phase_first ? 5'd0 : tk_idx) + 1'b1;
            tq_base <= phase_first ? 16'd0 : tq_base;
            prob_head_base <= phase_first ? 16'd0 : prob_head_base;
            tk_base <= (phase_first ? 16'd0 : tk_base) + `VERIRUST_D_MODEL;
        end
    end
end

endmodule
