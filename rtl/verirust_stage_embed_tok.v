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
reg [15:0] row_base;

always @* begin
    token_rd_addr = phase_first ? 8'd0 : row_idx;
    tok_embed_addr = (token_value << 5) + (phase_first ? 16'd0 : chan_idx);
    wr_en = en;
    wr_addr = (phase_first ? 16'd0 : row_base) + (phase_first ? 16'd0 : chan_idx);
    wr_data = tok_embed_value;
end

always @(posedge clk) begin
    if (!rst_n) begin
        row_idx <= 0;
        chan_idx <= 0;
        row_base <= 0;
    end else if (en) begin
        if ((phase_first ? 6'd0 : chan_idx) == (`VERIRUST_D_MODEL - 1)) begin
            chan_idx <= 0;
            if ((phase_first ? 5'd0 : row_idx) == (`VERIRUST_SEQ_LEN - 1)) begin
                row_idx <= 0;
                row_base <= 0;
            end else begin
                row_idx <= (phase_first ? 5'd0 : row_idx) + 1'b1;
                row_base <= (phase_first ? 16'd0 : row_base) + `VERIRUST_D_MODEL;
            end
        end else begin
            row_idx <= phase_first ? 5'd0 : row_idx;
            row_base <= phase_first ? 16'd0 : row_base;
            chan_idx <= (phase_first ? 6'd0 : chan_idx) + 1'b1;
        end
    end
end

endmodule
