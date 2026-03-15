module tb_verirust_core;
`include "verirust_params.vh"

localparam int TOK_EMBEDDING_LEN = `VERIRUST_TOK_EMBEDDING_LEN;
localparam int POS_EMBEDDING_LEN = `VERIRUST_POS_EMBEDDING_LEN;
localparam int NORM_LEN = `VERIRUST_NORM_LEN;
localparam int MAT_DMODEL_DMODEL = `VERIRUST_MAT_DMODEL_DMODEL;
localparam int W1_LEN = `VERIRUST_W1_LEN;
localparam int W2_LEN = `VERIRUST_W2_LEN;
localparam int LM_HEAD_LEN = `VERIRUST_LM_HEAD_LEN;
localparam int SEQ_LEN = `VERIRUST_SEQ_LEN;

`define LOAD_U8_FILE(PATH, MEM, COUNT) \
    begin \
        fd = $fopen(PATH, "rb"); \
        if (fd == 0) $fatal(1, "failed to open %s", PATH); \
        for (idx = 0; idx < COUNT; idx = idx + 1) begin \
            byte_val = $fgetc(fd); \
            if (byte_val < 0) $fatal(1, "unexpected EOF in %s at byte %0d", PATH, idx); \
            MEM[idx] = byte_val[7:0]; \
        end \
        $fclose(fd); \
    end

`define LOAD_I16_FILE(PATH, MEM, COUNT) \
    begin \
        fd = $fopen(PATH, "rb"); \
        if (fd == 0) $fatal(1, "failed to open %s", PATH); \
        for (idx = 0; idx < COUNT; idx = idx + 1) begin \
            lo = $fgetc(fd); \
            hi = $fgetc(fd); \
            if (lo < 0 || hi < 0) $fatal(1, "unexpected EOF in %s at word %0d", PATH, idx); \
            MEM[idx] = {hi[7:0], lo[7:0]}; \
        end \
        $fclose(fd); \
    end

`define DUMP_I16_FILE(PATH, MEM, COUNT) \
    begin \
        fd = $fopen(PATH, "wb"); \
        if (fd == 0) $fatal(1, "failed to create %s", PATH); \
        for (idx = 0; idx < COUNT; idx = idx + 1) begin \
            $fwrite(fd, "%c", MEM[idx][7:0]); \
            $fwrite(fd, "%c", MEM[idx][15:8]); \
        end \
        $fclose(fd); \
    end

logic clk;
logic rst_n;
logic start;
logic done;

integer fd;
integer idx;
integer lo;
integer hi;
integer byte_val;

verirust_core dut (
    .clk(clk),
    .rst_n(rst_n),
    .start(start),
    .done(done)
);

always #5 clk = ~clk;

task automatic load_weights_from_blob(input string path);
    begin
        fd = $fopen(path, "rb");
        if (fd == 0) begin
            $fatal(1, "failed to open %s", path);
        end

        for (idx = 0; idx < TOK_EMBEDDING_LEN; idx = idx + 1) begin
            lo = $fgetc(fd);
            hi = $fgetc(fd);
            dut.tok_embedding[idx] = {hi[7:0], lo[7:0]};
        end
        for (idx = 0; idx < POS_EMBEDDING_LEN; idx = idx + 1) begin
            lo = $fgetc(fd);
            hi = $fgetc(fd);
            dut.pos_embedding[idx] = {hi[7:0], lo[7:0]};
        end
        for (idx = 0; idx < NORM_LEN; idx = idx + 1) begin
            lo = $fgetc(fd);
            hi = $fgetc(fd);
            dut.norm1_weight[idx] = {hi[7:0], lo[7:0]};
        end
        for (idx = 0; idx < MAT_DMODEL_DMODEL; idx = idx + 1) begin
            lo = $fgetc(fd);
            hi = $fgetc(fd);
            dut.w_q[idx] = {hi[7:0], lo[7:0]};
        end
        for (idx = 0; idx < MAT_DMODEL_DMODEL; idx = idx + 1) begin
            lo = $fgetc(fd);
            hi = $fgetc(fd);
            dut.w_k[idx] = {hi[7:0], lo[7:0]};
        end
        for (idx = 0; idx < MAT_DMODEL_DMODEL; idx = idx + 1) begin
            lo = $fgetc(fd);
            hi = $fgetc(fd);
            dut.w_v[idx] = {hi[7:0], lo[7:0]};
        end
        for (idx = 0; idx < MAT_DMODEL_DMODEL; idx = idx + 1) begin
            lo = $fgetc(fd);
            hi = $fgetc(fd);
            dut.w_o[idx] = {hi[7:0], lo[7:0]};
        end
        for (idx = 0; idx < NORM_LEN; idx = idx + 1) begin
            lo = $fgetc(fd);
            hi = $fgetc(fd);
            dut.norm2_weight[idx] = {hi[7:0], lo[7:0]};
        end
        for (idx = 0; idx < W1_LEN; idx = idx + 1) begin
            lo = $fgetc(fd);
            hi = $fgetc(fd);
            dut.w1[idx] = {hi[7:0], lo[7:0]};
        end
        for (idx = 0; idx < W2_LEN; idx = idx + 1) begin
            lo = $fgetc(fd);
            hi = $fgetc(fd);
            dut.w2[idx] = {hi[7:0], lo[7:0]};
        end
        for (idx = 0; idx < LM_HEAD_LEN; idx = idx + 1) begin
            lo = $fgetc(fd);
            hi = $fgetc(fd);
            dut.lm_head[idx] = {hi[7:0], lo[7:0]};
        end

        $fclose(fd);
    end
endtask

initial begin
    clk = 1'b0;
    rst_n = 1'b0;
    start = 1'b0;

    `LOAD_U8_FILE("tests/input_000.bin", dut.tokens, SEQ_LEN);
    `LOAD_I16_FILE("spec/luts/exp_lut.bin", dut.exp_lut, 1024);
    `LOAD_I16_FILE("spec/luts/rsqrt_lut.bin", dut.rsqrt_lut, 4096);
    `LOAD_I16_FILE("spec/luts/recip_lut.bin", dut.recip_lut, 4096);
    load_weights_from_blob("weights/weights_v1.bin");

    $system("mkdir -p sim/out");

    #20;
    rst_n = 1'b1;
    #20;
    start = 1'b1;
    #10;
    start = 1'b0;

    @(posedge done);

    `DUMP_I16_FILE("sim/out/x_tok.bin", dut.x_tok, `VERIRUST_SEQ_LEN * `VERIRUST_D_MODEL);
    `DUMP_I16_FILE("sim/out/x_in.bin", dut.x_in, `VERIRUST_SEQ_LEN * `VERIRUST_D_MODEL);
    `DUMP_I16_FILE("sim/out/norm1_out.bin", dut.norm1_out, `VERIRUST_SEQ_LEN * `VERIRUST_D_MODEL);
    `DUMP_I16_FILE("sim/out/q_flat.bin", dut.q_flat, `VERIRUST_SEQ_LEN * `VERIRUST_D_MODEL);
    `DUMP_I16_FILE("sim/out/k_flat.bin", dut.k_flat, `VERIRUST_SEQ_LEN * `VERIRUST_D_MODEL);
    `DUMP_I16_FILE("sim/out/v_flat.bin", dut.v_flat, `VERIRUST_SEQ_LEN * `VERIRUST_D_MODEL);
    `DUMP_I16_FILE("sim/out/scores_pre_mask.bin", dut.scores_pre_mask, `VERIRUST_SCORE_LEN);
    `DUMP_I16_FILE("sim/out/scores_post_mask.bin", dut.scores_post_mask, `VERIRUST_SCORE_LEN);
    `DUMP_I16_FILE("sim/out/attn_probs.bin", dut.attn_probs, `VERIRUST_SCORE_LEN);
    `DUMP_I16_FILE("sim/out/ctx_flat.bin", dut.ctx_flat, `VERIRUST_SEQ_LEN * `VERIRUST_D_MODEL);
    `DUMP_I16_FILE("sim/out/attn_out.bin", dut.attn_out, `VERIRUST_SEQ_LEN * `VERIRUST_D_MODEL);
    `DUMP_I16_FILE("sim/out/resid1_out.bin", dut.resid1_out, `VERIRUST_SEQ_LEN * `VERIRUST_D_MODEL);
    `DUMP_I16_FILE("sim/out/norm2_out.bin", dut.norm2_out, `VERIRUST_SEQ_LEN * `VERIRUST_D_MODEL);
    `DUMP_I16_FILE("sim/out/ffn_h1.bin", dut.ffn_h1, `VERIRUST_SEQ_LEN * `VERIRUST_D_FF);
    `DUMP_I16_FILE("sim/out/ffn_relu.bin", dut.ffn_relu, `VERIRUST_SEQ_LEN * `VERIRUST_D_FF);
    `DUMP_I16_FILE("sim/out/ffn_out.bin", dut.ffn_out, `VERIRUST_SEQ_LEN * `VERIRUST_D_MODEL);
    `DUMP_I16_FILE("sim/out/block_out.bin", dut.block_out, `VERIRUST_SEQ_LEN * `VERIRUST_D_MODEL);
    `DUMP_I16_FILE("sim/out/logits.bin", dut.logits, `VERIRUST_SEQ_LEN * `VERIRUST_VOCAB_SIZE);

    $finish;
end

endmodule
