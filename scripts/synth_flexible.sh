#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${ROOT}/reports/yosys"
MODE="${1:-quick}"
LIBRARY="${2:-nangate}"

case "${LIBRARY}" in
  nangate)
    LIBERTY="${ROOT}/synth/lib/NangateOpenCellLibrary_typical.lib"
    ;;
  sky130)
    LIBERTY="${ROOT}/synth/lib/sky130_fd_sc_hd__tt_025C_1v80.lib"
    ;;
  plain)
    LIBERTY=""
    ;;
  *)
    echo "usage: $0 [lite|quick|full] [nangate|sky130|plain]" >&2
    exit 2
    ;;
esac

case "${MODE}" in
  lite)
    SCRIPT="synth/verirust_flexible_lite.ys"
    LOG="${OUT_DIR}/flexible_lite.log"
    ;;
  quick)
    SCRIPT="synth/verirust_flexible_quick.ys"
    LOG="${OUT_DIR}/flexible_quick.log"
    ;;
  full)
    SCRIPT="synth/verirust_flexible.ys"
    LOG="${OUT_DIR}/flexible_full.log"
    ;;
  *)
    echo "usage: $0 [lite|quick|full] [nangate|sky130|plain]" >&2
    exit 2
    ;;
esac

mkdir -p "${OUT_DIR}"
cd "${ROOT}"

echo "[flexible/${MODE}] start: $(date '+%Y-%m-%d %H:%M:%S')"
echo "[flexible/${MODE}] yosys script: ${SCRIPT}"
if [[ "${MODE}" == "full" && -n "${LIBERTY}" && -f "${LIBERTY}" ]]; then
  echo "[flexible/${MODE}] liberty: ${LIBERTY}"
  yosys -p "read_verilog -Irtl rtl/verirust_ctrl.v rtl/verirust_flexible_store.v rtl/verirust_stage_embed_tok.v rtl/verirust_stage_embed_add.v rtl/verirust_stage_rmsnorm.v rtl/verirust_stage_matmul.v rtl/verirust_stage_score.v rtl/verirust_stage_softmax.v rtl/verirust_stage_ctx.v rtl/verirust_stage_resid.v rtl/verirust_stage_ffn1.v rtl/verirust_stage_relu.v rtl/verirust_flexible_synth.v; hierarchy -check -top verirust_flexible_synth; check; proc; opt; memory; opt; techmap; opt; abc -liberty ${LIBERTY}; stat" | tee "${LOG}"
else
  [[ "${MODE}" == "full" ]] && echo "[flexible/${MODE}] using plain abc"
  yosys -s "${SCRIPT}" | tee "${LOG}"
fi
echo "[flexible/${MODE}] end:   $(date '+%Y-%m-%d %H:%M:%S')"

echo
echo "Flexible synthesis (${MODE}) log:"
echo "  ${LOG}"
