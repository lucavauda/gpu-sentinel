#!/usr/bin/env bash
#
# Phase 4 acceptance harness. Proves your Falco detection pack:
#   - FIRES on the Phase 2 attack (each core rule), and
#   - STAYS QUIET on a benign baseline + ordinary host activity (no false positives).
#
#     cd /Users/lucavaudano/myproject/GPU_Sec/04-detections
#     bash setup-baseline.sh        # once
#     bash test-rules.sh

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RULES="$HERE/falco/gpu-sec-rules.yaml"
SIGMA_DIR="$HERE/sigma"
ATTACK=/opt/gpu-sec/attack-bundle
BENIGN=/opt/gpu-sec/benign-bundle
MAL_OUT="$HERE/mal.out"; BEN_OUT="$HERE/ben.out"; ERR="$HERE/falco.err"

CORE=(
"GPUSEC LD_PRELOAD in Container Runtime Hook Chain"
"GPUSEC Unexpected Shared Object Loaded During Container Setup"
"GPUSEC Host Path Accessed by Container Runtime Hook"
)

PASS=0; FAIL=0
ok(){  echo "  [ok]   $1"; PASS=$((PASS+1)); }
bad(){ echo "  [FAIL] $1"; FAIL=$((FAIL+1)); }

echo "== Phase 4 test-rules =="
command -v falco >/dev/null || { echo "Falco not installed"; exit 1; }
[ -f "$RULES" ] || { echo "missing $RULES"; exit 1; }
[ -d "$ATTACK" ] || { echo "run ../02-attack/setup.sh first"; exit 1; }
[ -d "$BENIGN" ] || { echo "run ./setup-baseline.sh first"; exit 1; }

# Ignore comment lines — the sentinel also appears in the file's header comment.
if grep -v '^[[:space:]]*#' "$RULES" | grep -q "__TODO_REPLACE_ME__"; then
  bad "core rule conditions still stubbed (__TODO_REPLACE_ME__) — fill all three"
  echo; echo "Passed: $PASS  Failed: $FAIL"; echo "Fill the 3 core rules, then re-run."; exit 1
fi

start_falco(){ # $1 outfile
  : > "$1"; : > "$ERR"
  sudo falco -r "$RULES" -o json_output=true -o stdout_output.enabled=true \
       -o priority=debug -o log_level=error >"$1" 2>"$ERR" &
  sleep 8   # let the eBPF driver attach before we generate activity
}
stop_falco(){ sudo pkill -f "gpu-sec-rules.yaml" >/dev/null 2>&1 || true; sleep 1; }
run_bundle(){ # $1 bundle
  local cid="p4-$$-$RANDOM"
  sudo runc delete --force "$cid" >/dev/null 2>&1 || true
  sudo timeout 20 runc run -b "$1" "$cid" </dev/null >/dev/null 2>&1
  sudo runc delete --force "$cid" >/dev/null 2>&1 || true
}

# ---- malicious replay: every core rule must fire ----
echo "  [..]  malicious replay (the Phase 2 attack)..."
start_falco "$MAL_OUT"; run_bundle "$ATTACK"; sleep 2; stop_falco
for r in "${CORE[@]}"; do
  if grep -Fq "\"rule\":\"$r\"" "$MAL_OUT"; then ok "fires on attack:  $r"
  else bad "did NOT fire on attack:  $r   (check $ERR for load errors)"; fi
done

# ---- benign baseline + ordinary host activity: nothing may fire ----
echo "  [..]  benign baseline replay (+ ordinary host activity)..."
start_falco "$BEN_OUT"
run_bundle "$BENIGN"
# normal dynamically-linked host commands (load libc .so from standard dirs) —
# if a rule fires on these, it's too broad.
ls -la /usr/bin >/dev/null 2>&1; cat /etc/os-release >/dev/null 2>&1; head -c 16 /dev/urandom >/dev/null 2>&1
sleep 2; stop_falco
fp=0
for r in "${CORE[@]}"; do
  grep -Fq "\"rule\":\"$r\"" "$BEN_OUT" && { bad "FALSE POSITIVE on benign:  $r"; fp=1; }
done
[ "$fp" -eq 0 ] && ok "no core rule fired on the benign baseline (clean)"

# ---- Sigma structural check ----
if ls "$SIGMA_DIR"/*.yml >/dev/null 2>&1; then
  if grep -rqi "__TODO__" "$SIGMA_DIR"; then
    bad "Sigma rule(s) still contain __TODO__ — fill the detection"
  elif grep -rqi "detection:" "$SIGMA_DIR" && grep -rqi "condition:" "$SIGMA_DIR"; then
    ok "Sigma rule(s) present with detection logic"
  else
    bad "Sigma rule(s) missing detection/condition"
  fi
else
  bad "no Sigma rules found in $SIGMA_DIR"
fi

echo
echo "Passed: $PASS  Failed: $FAIL"
if [ "$FAIL" -eq 0 ]; then
  echo "PHASE 4 COMPLETE ✅  — the pack fires on the attack and stays quiet on the baseline."
  echo "Tell the assistant to scaffold Phase 5 (cryptominer ML) or Phase 6 (writeup)."
  exit 0
else
  echo "Not there yet. Fix the [FAIL] lines above."
  exit 1
fi
