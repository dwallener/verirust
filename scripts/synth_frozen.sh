#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${ROOT}/reports/yosys"
MODE="${1:-quick}"

case "${MODE}" in
  quick)
    SCRIPT="synth/verirust_frozen_quick.ys"
    LOG="${OUT_DIR}/frozen_quick.log"
    ;;
  full)
    SCRIPT="synth/verirust_frozen.ys"
    LOG="${OUT_DIR}/frozen_full.log"
    ;;
  *)
    echo "usage: $0 [quick|full]" >&2
    exit 2
    ;;
esac

mkdir -p "${OUT_DIR}"
cd "${ROOT}"

echo "[frozen/${MODE}] start: $(date '+%Y-%m-%d %H:%M:%S')"
echo "[frozen/${MODE}] regenerating frozen constants"
cargo run --bin generate_frozen_rtl >/dev/null
echo "[frozen/${MODE}] yosys script: ${SCRIPT}"
yosys -s "${SCRIPT}" | tee "${LOG}"
echo "[frozen/${MODE}] end:   $(date '+%Y-%m-%d %H:%M:%S')"

echo
echo "Frozen synthesis (${MODE}) log:"
echo "  ${LOG}"
