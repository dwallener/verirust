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
reg [15:0] row_base;

always @* begin
    rd_addr = (phase_first ? 16'd0 : row_base) + (phase_first ? 16'd0 : col_idx);
    wr_addr = rd_addr;
    wr_en = en;
    if (in_value[15])
        wr_data = 16'sd0;
    else
        wr_data = in_value;
end

always @(posedge clk) begin
    if (!rst_n) begin
        row_idx <= 0;
        col_idx <= 0;
        row_base <= 0;
    end else if (en) begin
        if ((phase_first ? 7'd0 : col_idx) == (`VERIRUST_D_FF - 1)) begin
            col_idx <= 0;
            if ((phase_first ? 5'd0 : row_idx) == (`VERIRUST_SEQ_LEN - 1)) begin
                row_idx <= 0;
                row_base <= 0;
            end else begin
                row_idx <= (phase_first ? 5'd0 : row_idx) + 1'b1;
                row_base <= (phase_first ? 16'd0 : row_base) + `VERIRUST_D_FF;
            end
        end else begin
            row_idx <= phase_first ? 5'd0 : row_idx;
            row_base <= phase_first ? 16'd0 : row_base;
            col_idx <= (phase_first ? 7'd0 : col_idx) + 1'b1;
        end
    end
end

endmodule
