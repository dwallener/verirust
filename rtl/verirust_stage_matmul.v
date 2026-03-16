module verirust_stage_matmul (
    clk,
    rst_n,
    en,
    phase_first,
    lhs_value,
    rhs_value,
    lhs_rd_addr,
    rhs_addr,
    wr_en,
    wr_addr,
    wr_data
);

parameter ROWS = 16;
parameter COLS = 32;
parameter INNER = 32;

input clk;
input rst_n;
input en;
input phase_first;
input signed [15:0] lhs_value;
input signed [15:0] rhs_value;
output reg [15:0] lhs_rd_addr;
output reg [15:0] rhs_addr;
output reg wr_en;
output reg [15:0] wr_addr;
output reg signed [15:0] wr_data;

reg [15:0] row_idx;
reg [15:0] col_idx;
reg [15:0] inner_idx;
reg [15:0] lhs_row_base;
reg [15:0] wr_row_base;
reg [15:0] rhs_row_base;
reg signed [31:0] acc_reg;
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
            shifted = x >>> 8;
        else
            shifted = -((-x) >>> 8);
        requantize_q16_to_q8 = saturate_i16(shifted);
    end
endfunction

always @* begin
    lhs_rd_addr = (phase_first ? 16'd0 : lhs_row_base) + (phase_first ? 16'd0 : inner_idx);
    rhs_addr = (phase_first ? 16'd0 : rhs_row_base) + (phase_first ? 16'd0 : col_idx);
    wr_en = en && ((phase_first ? 16'd0 : inner_idx) == INNER);
    wr_addr = (phase_first ? 16'd0 : wr_row_base) + (phase_first ? 16'd0 : col_idx);
    wr_data = requantize_q16_to_q8(acc_reg);
end

always @(posedge clk) begin
    if (!rst_n) begin
        row_idx <= 0;
        col_idx <= 0;
        inner_idx <= 0;
        lhs_row_base <= 0;
        wr_row_base <= 0;
        rhs_row_base <= 0;
        acc_reg <= 32'sd0;
    end else if (en) begin
        if ((phase_first ? 16'd0 : inner_idx) < INNER) begin
            prod32 = lhs_value * rhs_value;
            if ((phase_first ? 16'd0 : inner_idx) == 0)
                acc_reg <= prod32;
            else
                acc_reg <= acc_reg + prod32;
        end
        if ((phase_first ? 16'd0 : inner_idx) == INNER) begin
            inner_idx <= 0;
            rhs_row_base <= 0;
            if ((phase_first ? 16'd0 : col_idx) == (COLS - 1)) begin
                col_idx <= 0;
                if ((phase_first ? 16'd0 : row_idx) == (ROWS - 1)) begin
                    row_idx <= 0;
                    lhs_row_base <= 0;
                    wr_row_base <= 0;
                end else begin
                    row_idx <= (phase_first ? 16'd0 : row_idx) + 1'b1;
                    lhs_row_base <= (phase_first ? 16'd0 : lhs_row_base) + INNER;
                    wr_row_base <= (phase_first ? 16'd0 : wr_row_base) + COLS;
                end
            end else begin
                col_idx <= (phase_first ? 16'd0 : col_idx) + 1'b1;
                row_idx <= phase_first ? 16'd0 : row_idx;
                lhs_row_base <= phase_first ? 16'd0 : lhs_row_base;
                wr_row_base <= phase_first ? 16'd0 : wr_row_base;
            end
        end else begin
            row_idx <= phase_first ? 16'd0 : row_idx;
            col_idx <= phase_first ? 16'd0 : col_idx;
            lhs_row_base <= phase_first ? 16'd0 : lhs_row_base;
            wr_row_base <= phase_first ? 16'd0 : wr_row_base;
            inner_idx <= (phase_first ? 16'd0 : inner_idx) + 1'b1;
            rhs_row_base <= (phase_first ? 16'd0 : rhs_row_base) + COLS;
        end
    end
end

endmodule
