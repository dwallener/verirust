# Verirust Sequential Microarchitecture

This document defines the intended synthesizable hardware architecture for the
Verilog implementation.

Design rules:

- Synthesizable logic lives in plain Verilog (`.v`) only.
- SystemVerilog is reserved for harnesses and test benches.
- No single-cycle whole-model evaluation is permitted.
- Major transformer stages execute over many cycles under explicit control.
- Flexible and frozen implementations share the same controller/datapath shape.
- The only difference between flexible and frozen implementations is how model
  parameters are stored.

## Top-level architecture

The RTL is organized into:

- a controller FSM
- stage-local enabled clocked blocks
- scratch memories / register files
- parameter memories or constant-ROM functions
- token input memory
- logits output memory

The controller advances through the following phase sequence:

1. `PH_IDLE`
2. `PH_EMBED_TOK`
3. `PH_EMBED_ADD`
4. `PH_NORM1`
5. `PH_Q`
6. `PH_K`
7. `PH_V`
8. `PH_SCORE`
9. `PH_SOFTMAX`
10. `PH_CTX`
11. `PH_ATTN_OUT`
12. `PH_RESID1`
13. `PH_NORM2`
14. `PH_FFN1`
15. `PH_FFN1_RELU`
16. `PH_FFN2`
17. `PH_RESID2`
18. `PH_LOGITS`
19. `PH_DONE`

Each phase is multi-cycle and uses explicit loop counters. No phase implies a
fully combinational tensor evaluation.

Each major phase family has its own clocked block with an explicit enable:

- `en_embed_tok`
- `en_embed_add`
- `en_norm1`
- `en_q`
- `en_k`
- `en_v`
- `en_score`
- `en_softmax`
- `en_ctx`
- `en_attn_out`
- `en_resid1`
- `en_norm2`
- `en_ffn1`
- `en_ffn1_relu`
- `en_ffn2`
- `en_resid2`
- `en_logits`

This is intended to resemble a tiny dedicated accelerator pipeline rather than
one monolithic clocked process.

The current implementation packages those enabled blocks as standalone reusable
stage modules:

- `verirust_stage_embed_tok`
- `verirust_stage_embed_add`
- `verirust_stage_rmsnorm`
- `verirust_stage_matmul`
- `verirust_stage_score`
- `verirust_stage_softmax`
- `verirust_stage_ctx`
- `verirust_stage_resid`
- `verirust_stage_ffn1`
- `verirust_stage_relu`

## Flexible design

`verirust_flexible_synth` contains mutable memories for:

- tokens
- weights
- LUTs
- scratch tensors
- logits

A small configuration bus writes tokens, weights, and LUT contents before
`start`.

The mutable token / weight / LUT state is now grouped behind
`verirust_flexible_store`, which gives the compute top generic read ports
instead of keeping every mutable parameter array directly in the top module.

## Frozen design

`verirust_frozen` reuses the same controller/datapath and stage-module set, but
replaces mutable weight/LUT memories with constant ROM functions generated from
the canonical artifacts.

## Current implementation scope

The current RTL implements a phase-by-phase multi-cycle datapath for the
baseline single-block transformer:

- embedding gather and position add
- RMSNorm 1
- Q / K / V projection
- score generation and scaling
- causal masking and softmax
- context accumulation and output projection
- first residual
- RMSNorm 2
- FFN first and second projection with ReLU
- second residual
- final logits projection

The flexible and frozen tops follow the same phase schedule and scratch-tensor
layout. The remaining work is functional verification against the Rust
reference and then checkpoint-level comparison infrastructure for the RTL path.
