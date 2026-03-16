#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "${ROOT}"

echo "[elab/flexible] start: $(date '+%Y-%m-%d %H:%M:%S')"
echo "[elab/flexible] top: verirust_flexible_synth"

yosys -p "read_verilog -Irtl rtl/verirust_ctrl.v rtl/verirust_flexible_store.v rtl/verirust_stage_embed_tok.v rtl/verirust_stage_embed_add.v rtl/verirust_stage_rmsnorm.v rtl/verirust_stage_matmul.v rtl/verirust_stage_score.v rtl/verirust_stage_softmax.v rtl/verirust_stage_ctx.v rtl/verirust_stage_resid.v rtl/verirust_stage_ffn1.v rtl/verirust_stage_relu.v rtl/verirust_flexible_synth.v; hierarchy -check -top verirust_flexible_synth; ls"

echo "[elab/flexible] end:   $(date '+%Y-%m-%d %H:%M:%S')"
