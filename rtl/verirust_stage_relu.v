`include "verirust_params.vh"

module verirust_stage_relu (
    clk,
    rst_n,
    en,
    phase_first,
    in_value,
    rd_addr,
    wr_en,
    wr_addr,
    wr_data
);

input clk;
input rst_n;
input en;
input phase_first;
input signed [15:0] in_value;
output reg [15:0] rd_addr;
output reg wr_en;
output reg [15:0] wr_addr;
output reg signed [15:0] wr_data;

reg [4:0] row_idx;
reg [6:0] col_idx;
integer row;
integer col;

always @* begin
    row = phase_first ? 0 : row_idx;
    col = phase_first ? 0 : col_idx;
    rd_addr = row * `VERIRUST_D_FF + col;
    wr_addr = rd_addr;
    wr_en = en;
    if (in_value[15])
        wr_data = 16'sd0;
    else
        wr_data = in_value;
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        row_idx <= 0;
        col_idx <= 0;
    end else if (en) begin
        row = phase_first ? 0 : row_idx;
        col = phase_first ? 0 : col_idx;
        if (col == (`VERIRUST_D_FF - 1)) begin
            col_idx <= 0;
            if (row == (`VERIRUST_SEQ_LEN - 1))
                row_idx <= 0;
            else
                row_idx <= row + 1;
        end else begin
            row_idx <= row;
            col_idx <= col + 1;
        end
    end
end

endmodule
