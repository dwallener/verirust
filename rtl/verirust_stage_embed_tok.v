`include "verirust_params.vh"

module verirust_stage_embed_tok (
    clk,
    rst_n,
    en,
    phase_first,
    token_value,
    tok_embed_value,
    token_rd_addr,
    tok_embed_addr,
    wr_en,
    wr_addr,
    wr_data
);

input clk;
input rst_n;
input en;
input phase_first;
input [7:0] token_value;
input signed [15:0] tok_embed_value;
output reg [7:0] token_rd_addr;
output reg [15:0] tok_embed_addr;
output reg wr_en;
output reg [15:0] wr_addr;
output reg signed [15:0] wr_data;

reg [4:0] row_idx;
reg [5:0] chan_idx;
integer row;
integer chan;

always @* begin
    row = phase_first ? 0 : row_idx;
    chan = phase_first ? 0 : chan_idx;
    token_rd_addr = row[7:0];
    tok_embed_addr = token_value * `VERIRUST_D_MODEL + chan;
    wr_en = en;
    wr_addr = row * `VERIRUST_D_MODEL + chan;
    wr_data = tok_embed_value;
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
