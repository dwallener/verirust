`include "verirust_params.vh"

module verirust_ctrl (
    clk,
    rst_n,
    start,
    phase,
    phase_index,
    phase_active,
    done
);

input clk;
input rst_n;
input start;
output reg [4:0] phase;
output reg [17:0] phase_index;
output reg phase_active;
output reg done;

parameter [4:0] PH_IDLE     = 5'd0;
parameter [4:0] PH_EMBED_TOK  = 5'd1;
parameter [4:0] PH_EMBED_ADD  = 5'd2;
parameter [4:0] PH_NORM1      = 5'd3;
parameter [4:0] PH_Q          = 5'd4;
parameter [4:0] PH_K          = 5'd5;
parameter [4:0] PH_V          = 5'd6;
parameter [4:0] PH_SCORE      = 5'd7;
parameter [4:0] PH_SOFTMAX    = 5'd8;
parameter [4:0] PH_CTX        = 5'd9;
parameter [4:0] PH_ATTN_OUT   = 5'd10;
parameter [4:0] PH_RESID1     = 5'd11;
parameter [4:0] PH_NORM2      = 5'd12;
parameter [4:0] PH_FFN1       = 5'd13;
parameter [4:0] PH_FFN1_RELU  = 5'd14;
parameter [4:0] PH_FFN2       = 5'd15;
parameter [4:0] PH_RESID2     = 5'd16;
parameter [4:0] PH_LOGITS     = 5'd17;
parameter [4:0] PH_DONE       = 5'd18;

function [17:0] phase_limit;
    input [4:0] current_phase;
    begin
        case (current_phase)
            PH_EMBED_TOK: phase_limit = `VERIRUST_SEQ_LEN * `VERIRUST_D_MODEL - 1;
            PH_EMBED_ADD: phase_limit = `VERIRUST_SEQ_LEN * `VERIRUST_D_MODEL - 1;
            PH_NORM1:    phase_limit = `VERIRUST_SEQ_LEN * ((2 * `VERIRUST_D_MODEL) + 1) - 1;
            PH_Q:        phase_limit = `VERIRUST_SEQ_LEN * `VERIRUST_D_MODEL * (`VERIRUST_D_MODEL + 1) - 1;
            PH_K:        phase_limit = `VERIRUST_SEQ_LEN * `VERIRUST_D_MODEL * (`VERIRUST_D_MODEL + 1) - 1;
            PH_V:        phase_limit = `VERIRUST_SEQ_LEN * `VERIRUST_D_MODEL * (`VERIRUST_D_MODEL + 1) - 1;
            PH_SCORE:    phase_limit = `VERIRUST_N_HEADS * `VERIRUST_SEQ_LEN * `VERIRUST_SEQ_LEN * (`VERIRUST_D_HEAD + 1) - 1;
            PH_SOFTMAX:  phase_limit = `VERIRUST_N_HEADS * `VERIRUST_SEQ_LEN * ((3 * `VERIRUST_SEQ_LEN) + 1) - 1;
            PH_CTX:      phase_limit = `VERIRUST_SEQ_LEN * `VERIRUST_D_MODEL * (`VERIRUST_SEQ_LEN + 1) - 1;
            PH_ATTN_OUT: phase_limit = `VERIRUST_SEQ_LEN * `VERIRUST_D_MODEL * (`VERIRUST_D_MODEL + 1) - 1;
            PH_RESID1:   phase_limit = `VERIRUST_SEQ_LEN * `VERIRUST_D_MODEL - 1;
            PH_NORM2:    phase_limit = `VERIRUST_SEQ_LEN * ((2 * `VERIRUST_D_MODEL) + 1) - 1;
            PH_FFN1:     phase_limit = `VERIRUST_SEQ_LEN * `VERIRUST_D_FF * (`VERIRUST_D_MODEL + 1) - 1;
            PH_FFN1_RELU: phase_limit = `VERIRUST_SEQ_LEN * `VERIRUST_D_FF - 1;
            PH_FFN2:     phase_limit = `VERIRUST_SEQ_LEN * `VERIRUST_D_MODEL * (`VERIRUST_D_FF + 1) - 1;
            PH_RESID2:   phase_limit = `VERIRUST_SEQ_LEN * `VERIRUST_D_MODEL - 1;
            PH_LOGITS:   phase_limit = `VERIRUST_SEQ_LEN * `VERIRUST_VOCAB_SIZE * (`VERIRUST_D_MODEL + 1) - 1;
            default:     phase_limit = 0;
        endcase
    end
endfunction

function [4:0] next_phase;
    input [4:0] current_phase;
    begin
        case (current_phase)
            PH_EMBED_TOK: next_phase = PH_EMBED_ADD;
            PH_EMBED_ADD: next_phase = PH_NORM1;
            PH_NORM1:    next_phase = PH_Q;
            PH_Q:        next_phase = PH_K;
            PH_K:        next_phase = PH_V;
            PH_V:        next_phase = PH_SCORE;
            PH_SCORE:    next_phase = PH_SOFTMAX;
            PH_SOFTMAX:  next_phase = PH_CTX;
            PH_CTX:      next_phase = PH_ATTN_OUT;
            PH_ATTN_OUT: next_phase = PH_RESID1;
            PH_RESID1:   next_phase = PH_NORM2;
            PH_NORM2:    next_phase = PH_FFN1;
            PH_FFN1:     next_phase = PH_FFN1_RELU;
            PH_FFN1_RELU: next_phase = PH_FFN2;
            PH_FFN2:     next_phase = PH_RESID2;
            PH_RESID2:   next_phase = PH_LOGITS;
            PH_LOGITS:   next_phase = PH_DONE;
            default:     next_phase = PH_DONE;
        endcase
    end
endfunction

always @(posedge clk) begin
    if (!rst_n) begin
        phase <= PH_IDLE;
        phase_index <= 0;
        phase_active <= 1'b0;
        done <= 1'b0;
    end else begin
        done <= 1'b0;
        if (phase == PH_IDLE) begin
            phase_index <= 0;
            phase_active <= 1'b0;
            if (start) begin
                phase <= PH_EMBED_TOK;
                phase_active <= 1'b1;
            end
        end else if (phase == PH_DONE) begin
            done <= 1'b1;
            phase <= PH_IDLE;
            phase_index <= 0;
            phase_active <= 1'b0;
        end else begin
            phase_active <= 1'b1;
            if (phase_index >= phase_limit(phase)) begin
                phase <= next_phase(phase);
                phase_index <= 0;
            end else begin
                phase_index <= phase_index + 1'b1;
            end
        end
    end
end

endmodule
