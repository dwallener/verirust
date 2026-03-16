#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "${ROOT}"

echo "[elab/frozen] start: $(date '+%Y-%m-%d %H:%M:%S')"
echo "[elab/frozen] regenerating frozen constants"
cargo run --bin generate_frozen_rtl >/dev/null
echo "[elab/frozen] top: verirust_frozen"

yosys -p "read_verilog -Irtl -Irtl/generated rtl/verirust_ctrl.v rtl/verirust_stage_embed_tok.v rtl/verirust_stage_embed_add.v rtl/verirust_stage_rmsnorm.v rtl/verirust_stage_matmul.v rtl/verirust_stage_score.v rtl/verirust_stage_softmax.v rtl/verirust_stage_ctx.v rtl/verirust_stage_resid.v rtl/verirust_stage_ffn1.v rtl/verirust_stage_relu.v rtl/verirust_frozen.v; hierarchy -check -top verirust_frozen; ls"

echo "[elab/frozen] end:   $(date '+%Y-%m-%d %H:%M:%S')"
