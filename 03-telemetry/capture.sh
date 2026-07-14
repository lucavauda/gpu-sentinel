#!/usr/bin/env bash
#
# Phase 3 telemetry tap. Starts Falco with the DEBUG ruleset, replays the Phase 2
# attack, stops Falco, and prints the events that relate to the attack.
#
#     cd /Users/lucavaudano/myproject/GPU_Sec/03-telemetry
#     bash capture.sh
#
# Proves the sensor SEES the attack. It is not a detection (Phase 4 is).

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="$HERE/falco.out"
ERR="$HERE/falco.err"
: > "$OUT"; : > "$ERR"

command -v falco >/dev/null || { echo "Falco not installed — see README.md"; exit 1; }
[ -d /opt/gpu-sec/attack-bundle ] || { echo "Run Phase 2 setup.sh first"; exit 1; }

echo "[*] Starting Falco (modern eBPF is the default driver now) with the debug ruleset..."
sudo falco -r "$HERE/capture.yaml" \
     -o json_output=true -o stdout_output.enabled=true -o log_level=info \
     >"$OUT" 2>"$ERR" &

# Give Falco time to load its driver before we replay the attack.
sleep 8

echo "[*] Replaying the Phase 2 attack (runc run of your weaponised bundle)..."
CID="gpu-sec-p3-$$"
sudo runc delete --force "$CID" >/dev/null 2>&1 || true
sudo timeout 20 runc run -b /opt/gpu-sec/attack-bundle "$CID" </dev/null >/dev/null 2>&1
sudo runc delete --force "$CID" >/dev/null 2>&1 || true
sleep 2

echo "[*] Stopping Falco..."
sudo pkill -f "capture.yaml" >/dev/null 2>&1 || true
sleep 1

echo
echo "=== attack-related events the sensor captured ==="
grep -E "GPUSEC_(EXEC|OPEN)" "$OUT" \
  | grep -Ei "vuln-hook|/bin/true|evil\.so|escape-proof|/opt/gpu-sec" \
  || echo "(none matched — see README troubleshooting; check $ERR for driver errors)"
echo
echo "Full capture: $OUT   |   Falco log: $ERR"
