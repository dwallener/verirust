module verirust_stage_resid (
    clk,
    rst_n,
    en,
    phase_first,
    a_value,
    b_value,
    rd_addr,
    wr_en,
    wr_addr,
    wr_data
);

parameter LEN = 512;

input clk;
input rst_n;
input en;
input phase_first;
input signed [15:0] a_value;
input signed [15:0] b_value;
output reg [15:0] rd_addr;
output reg wr_en;
output reg [15:0] wr_addr;
output reg signed [15:0] wr_data;

reg [15:0] idx_reg;
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
    rd_addr = phase_first ? 16'd0 : idx_reg;
    wr_addr = phase_first ? 16'd0 : idx_reg;
    wr_en = en;
    sum32 = a_value;
    sum32 = sum32 + b_value;
    wr_data = saturate_i16(sum32);
end

always @(posedge clk) begin
    if (!rst_n) begin
        idx_reg <= 0;
    end else if (en) begin
        if ((phase_first ? 16'd0 : idx_reg) == (LEN - 1))
            idx_reg <= 0;
        else
            idx_reg <= (phase_first ? 16'd0 : idx_reg) + 1'b1;
    end
end

endmodule
