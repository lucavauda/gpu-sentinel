#!/usr/bin/env bash
#
# Phase 3 acceptance test. Confirms:
#   1. Falco is installed and can run,
#   2. replaying the attack produces telemetry that captures the tell-tales
#      (the hook exec, the evil.so load, the escape-proof write),
#   3. telemetry-map.md is filled in.
#
#     cd /Users/lucavaudano/myproject/GPU_Sec/03-telemetry
#     bash verify_telemetry.sh

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="$HERE/falco.out"
MAP="$HERE/telemetry-map.md"

PASS=0; FAIL=0
ok(){  echo "  [ok]   $1"; PASS=$((PASS+1)); }
bad(){ echo "  [FAIL] $1"; FAIL=$((FAIL+1)); }

echo "== Phase 3 verify_telemetry =="

command -v falco >/dev/null && ok "Falco installed ($(falco --version 2>/dev/null | head -1))" \
  || { bad "Falco not installed — see README.md"; }

echo "  [..]   capturing telemetry (runs Falco + replays attack; needs sudo)..."
bash "$HERE/capture.sh" >/dev/null 2>&1 || true

if [ -f "$OUT" ]; then
  grep -Eiq "GPUSEC_EXEC.*(vuln-hook|/bin/true)" "$OUT" \
    && ok "captured the hook / injected-exec running on the host" \
    || bad "did not capture the hook exec — check falco.err for driver errors"
  grep -Eiq "GPUSEC_OPEN.*evil\.so" "$OUT" \
    && ok "captured the malicious .so being loaded" \
    || bad "did not capture evil.so load"
  grep -Eiq "GPUSEC_OPEN.*(escape-proof|host-only)" "$OUT" \
    && ok "captured the escape file access on the host" \
    || bad "did not capture the escape-proof / host-only access"
else
  bad "no capture output ($OUT) — Falco likely didn't start; see README troubleshooting"
fi

if [ -f "$MAP" ] && [ "$(wc -c < "$MAP")" -gt 900 ]; then
  ok "telemetry-map.md filled in"
else
  bad "fill in telemetry-map.md (map each attack step to the event a sensor sees)"
fi

echo
echo "Passed: $PASS  Failed: $FAIL"
if [ "$FAIL" -eq 0 ]; then
  echo "PHASE 3 (telemetry) COMPLETE ✅  — the sensor sees the attack."
  echo "Tell the assistant to scaffold Phase 4 (write the real Falco + Sigma detections)."
  exit 0
else
  echo "Not there yet. Fix the [FAIL] lines above."
  exit 1
fi
