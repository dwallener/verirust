#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${ROOT}/reports/yosys"
MODE="${1:-quick}"

case "${MODE}" in
  quick)
    SCRIPT="synth/verirust_flexible_quick.ys"
    LOG="${OUT_DIR}/flexible_quick.log"
    ;;
  full)
    SCRIPT="synth/verirust_flexible.ys"
    LOG="${OUT_DIR}/flexible_full.log"
    ;;
  *)
    echo "usage: $0 [quick|full]" >&2
    exit 2
    ;;
esac

mkdir -p "${OUT_DIR}"
cd "${ROOT}"

echo "[flexible/${MODE}] start: $(date '+%Y-%m-%d %H:%M:%S')"
echo "[flexible/${MODE}] yosys script: ${SCRIPT}"
yosys -s "${SCRIPT}" | tee "${LOG}"
echo "[flexible/${MODE}] end:   $(date '+%Y-%m-%d %H:%M:%S')"

echo
echo "Flexible synthesis (${MODE}) log:"
echo "  ${LOG}"
