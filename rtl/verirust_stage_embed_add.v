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
reg [15:0] row_base;
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
    wr_addr = (phase_first ? 16'd0 : row_base) + (phase_first ? 16'd0 : chan_idx);
    x_tok_rd_addr = wr_addr;
    pos_addr = wr_addr;
    wr_en = en;
    sum32 = x_tok_value;
    sum32 = sum32 + pos_value;
    wr_data = saturate_i16(sum32);
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
