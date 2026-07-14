#!/usr/bin/env bash
#
# Phase 5 acceptance test. Runs the scorer and gates on:
#   1. data + predictions present,
#   2. your model beats the naive "high GPU%" baseline on PR-AUC,
#   3. WRITEUP.md defends your operating point.
#
#     cd /Users/lucavaudano/myproject/GPU_Sec/05-ml-cryptominer
#     python3 generate_data.py         # once
#     python3 model.py                 # yours: writes predictions.csv
#     bash verify_ml.sh

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PY="${PYTHON:-python3}"
PASS=0; FAIL=0
ok(){  echo "  [ok]   $1"; PASS=$((PASS+1)); }
bad(){ echo "  [FAIL] $1"; FAIL=$((FAIL+1)); }

echo "== Phase 5 verify_ml =="

[ -f "$HERE/test.csv" ]        || bad "no test.csv — run: $PY generate_data.py"
[ -f "$HERE/predictions.csv" ] || bad "no predictions.csv — run your model.py"

if [ -f "$HERE/test.csv" ] && [ -f "$HERE/predictions.csv" ]; then
  if "$PY" "$HERE/evaluate.py"; then
    ok "beat the naive baseline on PR-AUC"
  else
    bad "did not beat the naive baseline on PR-AUC (see output above)"
  fi
fi

if [ -f "$HERE/WRITEUP.md" ] && [ "$(wc -c < "$HERE/WRITEUP.md")" -gt 500 ]; then
  if grep -qiE "precision|recall" "$HERE/WRITEUP.md"; then
    ok "WRITEUP.md defends the operating point"
  else
    bad "WRITEUP.md must discuss your precision/recall trade-off for a SOC (>500 chars)"
  fi
else
  bad "write WRITEUP.md: which operating point you'd ship and why (>500 chars)"
fi

echo
echo "Passed: $PASS  Failed: $FAIL"
if [ "$FAIL" -eq 0 ]; then
  echo "PHASE 5 COMPLETE ✅  — a defensible rare-event detector. Tell the assistant to scaffold Phase 6 (writeup)."
  exit 0
else
  echo "Not there yet. Fix the [FAIL] lines above."
  exit 1
fi
