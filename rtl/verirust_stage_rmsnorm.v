module verirust_stage_rmsnorm (
    clk,
    rst_n,
    en,
    phase_first,
    in_value,
    weight_value,
    rsqrt_value,
    in_rd_addr,
    weight_addr,
    rsqrt_addr,
    use_weight,
    use_rsqrt,
    wr_en,
    wr_addr,
    wr_data
);

parameter ROWS = 16;
parameter COLS = 32;
parameter INV_D_MODEL_Q16 = 2048;
parameter EPS_Q16 = 1;

input clk;
input rst_n;
input en;
input phase_first;
input signed [15:0] in_value;
input signed [15:0] weight_value;
input signed [15:0] rsqrt_value;
output reg [15:0] in_rd_addr;
output reg [15:0] weight_addr;
output reg [15:0] rsqrt_addr;
output reg use_weight;
output reg use_rsqrt;
output reg wr_en;
output reg [15:0] wr_addr;
output reg signed [15:0] wr_data;

reg [15:0] row_idx;
reg [15:0] step_idx;
reg [15:0] row_base;
reg signed [31:0] sum_sq_reg;
reg signed [15:0] rsqrt_reg;
reg signed [31:0] mean_sq;
reg signed [31:0] prod32;
reg signed [31:0] tmp32;
reg [15:0] chan_idx;

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
    chan_idx = (phase_first ? 16'd0 : step_idx) - (COLS + 1);
    in_rd_addr = phase_first ? 16'd0 : row_base;
    weight_addr = 16'd0;
    rsqrt_addr = 16'd0;
    use_weight = 1'b0;
    use_rsqrt = 1'b0;
    wr_en = en && ((phase_first ? 16'd0 : step_idx) > COLS);
    wr_addr = (phase_first ? 16'd0 : row_base) + chan_idx;
    wr_data = 16'sd0;

    if ((phase_first ? 16'd0 : step_idx) < COLS) begin
        in_rd_addr = (phase_first ? 16'd0 : row_base) + (phase_first ? 16'd0 : step_idx);
    end else if ((phase_first ? 16'd0 : step_idx) == COLS) begin
        mean_sq = (sum_sq_reg * INV_D_MODEL_Q16) >>> 16;
        rsqrt_addr = ((mean_sq + EPS_Q16) * 4095) / (8 * 65536);
        use_rsqrt = 1'b1;
    end else begin
        in_rd_addr = (phase_first ? 16'd0 : row_base) + chan_idx;
        weight_addr = chan_idx;
        use_weight = 1'b1;
        tmp32 = in_value * rsqrt_reg;
        wr_data = requantize_q16_to_q8(requantize_q16_to_q8(tmp32) * weight_value);
    end
end

always @(posedge clk) begin
    if (!rst_n) begin
        row_idx <= 0;
        step_idx <= 0;
        row_base <= 0;
        sum_sq_reg <= 32'sd0;
        rsqrt_reg <= 16'sd0;
    end else if (en) begin
        if ((phase_first ? 16'd0 : step_idx) < COLS) begin
            prod32 = in_value * in_value;
            if ((phase_first ? 16'd0 : step_idx) == 0)
                sum_sq_reg <= prod32;
            else
                sum_sq_reg <= sum_sq_reg + prod32;
        end else if ((phase_first ? 16'd0 : step_idx) == COLS) begin
            rsqrt_reg <= rsqrt_value;
        end

        if ((phase_first ? 16'd0 : step_idx) == ((2 * COLS))) begin
            step_idx <= 0;
            if ((phase_first ? 16'd0 : row_idx) == (ROWS - 1)) begin
                row_idx <= 0;
                row_base <= 0;
            end else begin
                row_idx <= (phase_first ? 16'd0 : row_idx) + 1'b1;
                row_base <= (phase_first ? 16'd0 : row_base) + COLS;
            end
        end else begin
            row_idx <= phase_first ? 16'd0 : row_idx;
            row_base <= phase_first ? 16'd0 : row_base;
            step_idx <= (phase_first ? 16'd0 : step_idx) + 1'b1;
        end
    end
end

endmodule
