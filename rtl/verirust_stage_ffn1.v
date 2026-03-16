`include "verirust_params.vh"

module verirust_stage_ffn1 (
    clk,
    rst_n,
    en,
    phase_first,
    lhs_value,
    weight_value,
    lhs_rd_addr,
    weight_addr,
    wr_en,
    wr_addr,
    wr_data
);

input clk;
input rst_n;
input en;
input phase_first;
input signed [15:0] lhs_value;
input signed [15:0] weight_value;
output reg [15:0] lhs_rd_addr;
output reg [15:0] weight_addr;
output reg wr_en;
output reg [15:0] wr_addr;
output reg signed [15:0] wr_data;

reg [4:0] row_idx;
reg [6:0] col_idx;
reg [5:0] inner_idx;
reg signed [31:0] acc_reg;
integer row;
integer col;
integer inner;
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
    row = phase_first ? 0 : row_idx;
    col = phase_first ? 0 : col_idx;
    inner = phase_first ? 0 : inner_idx;
    lhs_rd_addr = row * `VERIRUST_D_MODEL + inner;
    weight_addr = inner * `VERIRUST_D_FF + col;
    wr_en = en && (inner == `VERIRUST_D_MODEL);
    wr_addr = row * `VERIRUST_D_FF + col;
    wr_data = requantize_q16_to_q8(acc_reg);
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        row_idx <= 0;
        col_idx <= 0;
        inner_idx <= 0;
        acc_reg <= 32'sd0;
    end else if (en) begin
        row = phase_first ? 0 : row_idx;
        col = phase_first ? 0 : col_idx;
        inner = phase_first ? 0 : inner_idx;
        if (inner < `VERIRUST_D_MODEL) begin
            prod32 = lhs_value * weight_value;
            if (inner == 0)
                acc_reg <= prod32;
            else
                acc_reg <= acc_reg + prod32;
        end
        if (inner == `VERIRUST_D_MODEL) begin
            inner_idx <= 0;
            if (col == (`VERIRUST_D_FF - 1)) begin
                col_idx <= 0;
                if (row == (`VERIRUST_SEQ_LEN - 1))
                    row_idx <= 0;
                else
                    row_idx <= row + 1;
            end else begin
                col_idx <= col + 1;
                row_idx <= row;
            end
        end else begin
            row_idx <= row;
            col_idx <= col;
            inner_idx <= inner + 1;
        end
    end
end

endmodule
