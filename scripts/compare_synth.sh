#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${ROOT}/reports/yosys"
MODE="${1:-quick}"

case "${MODE}" in
  quick)
    FLEX_SCRIPT="synth/verirust_flexible_quick.ys"
    FROZEN_SCRIPT="synth/verirust_frozen_quick.ys"
    FLEX_LOG="${OUT_DIR}/flexible_quick.log"
    FROZEN_LOG="${OUT_DIR}/frozen_quick.log"
    ;;
  full)
    FLEX_SCRIPT="synth/verirust_flexible.ys"
    FROZEN_SCRIPT="synth/verirust_frozen.ys"
    FLEX_LOG="${OUT_DIR}/flexible_full.log"
    FROZEN_LOG="${OUT_DIR}/frozen_full.log"
    ;;
  *)
    echo "usage: $0 [quick|full]" >&2
    exit 2
    ;;
esac

mkdir -p "${OUT_DIR}"

cd "${ROOT}"

"${ROOT}/scripts/synth_flexible.sh" "${MODE}" >/dev/null
"${ROOT}/scripts/synth_frozen.sh" "${MODE}" >/dev/null

extract_metric() {
    local label="$1"
    local file="$2"
    awk -v label="$label" '
        $1 == label ":" { print $2; exit }
    ' "$file"
}

extract_cells() {
    local file="$1"
    awk '
        /^Number of cells:/ { print $4; exit }
    ' "$file"
}

FLEX_CELLS="$(extract_cells "${FLEX_LOG}")"
FROZEN_CELLS="$(extract_cells "${FROZEN_LOG}")"

echo
echo "Synthesis comparison (${MODE})"
echo "Flexible cells: ${FLEX_CELLS:-unknown}"
echo "Frozen cells:   ${FROZEN_CELLS:-unknown}"

if [[ -n "${FLEX_CELLS:-}" && -n "${FROZEN_CELLS:-}" ]]; then
    python3 - "$FLEX_CELLS" "$FROZEN_CELLS" <<'PY'
import sys
flex = int(sys.argv[1])
frozen = int(sys.argv[2])
delta = frozen - flex
pct = (delta / flex * 100.0) if flex else 0.0
print(f"Delta cells:    {delta} ({pct:+.2f}%)")
PY
fi

echo
echo "Logs:"
echo "  ${FLEX_LOG}"
echo "  ${FROZEN_LOG}"
