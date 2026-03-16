`include "verirust_params.vh"

module verirust_stage_embed_add (
    clk,
    rst_n,
    en,
    phase_first,
    x_tok_value,
    pos_value,
    x_tok_rd_addr,
    pos_addr,
    wr_en,
    wr_addr,
    wr_data
);

input clk;
input rst_n;
input en;
input phase_first;
input signed [15:0] x_tok_value;
input signed [15:0] pos_value;
output reg [15:0] x_tok_rd_addr;
output reg [15:0] pos_addr;
output reg wr_en;
output reg [15:0] wr_addr;
output reg signed [15:0] wr_data;

reg [4:0] row_idx;
reg [5:0] chan_idx;
integer row;
integer chan;
reg signed [31:0] sum32;

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

always @* begin
    row = phase_first ? 0 : row_idx;
    chan = phase_first ? 0 : chan_idx;
    wr_addr = row * `VERIRUST_D_MODEL + chan;
    x_tok_rd_addr = wr_addr;
    pos_addr = wr_addr;
    wr_en = en;
    sum32 = x_tok_value;
    sum32 = sum32 + pos_value;
    wr_data = saturate_i16(sum32);
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        row_idx <= 0;
        chan_idx <= 0;
    end else if (en) begin
        row = phase_first ? 0 : row_idx;
        chan = phase_first ? 0 : chan_idx;
        if (chan == (`VERIRUST_D_MODEL - 1)) begin
            chan_idx <= 0;
            if (row == (`VERIRUST_SEQ_LEN - 1))
                row_idx <= 0;
            else
                row_idx <= row + 1;
        end else begin
            row_idx <= row;
            chan_idx <= chan + 1;
        end
    end
end

endmodule
