#!/usr/bin/env bash
#
# Phase 2 acceptance oracle. Run INSIDE the VM after setup.sh:
#
#     cd /Users/lucavaudano/myproject/GPU_Sec/02-attack
#     bash check_escape.sh
#
# It runs the tenant's (your) bundle through runc and checks whether your payload
# escaped: i.e. ran on the HOST as root and read the host-only secret the
# container cannot see.

set -uo pipefail
BASE=/opt/gpu-sec
BUNDLE="$BASE/attack-bundle"
PROOF="$BASE/escape-proof.txt"
FLAG_FILE="$BASE/host-only/flag.txt"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PASS=0; FAIL=0
ok(){  echo "  [ok]   $1"; PASS=$((PASS+1)); }
bad(){ echo "  [FAIL] $1"; FAIL=$((FAIL+1)); }

echo "== Phase 2 check_escape =="
[ -d "$BUNDLE" ] || { echo "  run 'bash setup.sh' first"; exit 1; }

# Preflight: did you actually weaponise the image?
if jq -e '.process.env[]? | select(startswith("LD_PRELOAD="))' "$BUNDLE/config.json" >/dev/null 2>&1; then
  ok "image carries an LD_PRELOAD in process.env (attacker-controlled)"
else
  bad "no LD_PRELOAD in the container's process.env yet — set one (README, step 2)"
fi

FLAG="$(sudo cat "$FLAG_FILE" 2>/dev/null || true)"
sudo rm -f "$PROOF"

CID="gpu-sec-p2-$$"
sudo runc delete --force "$CID" >/dev/null 2>&1 || true
sudo timeout 20 runc run -b "$BUNDLE" "$CID" </dev/null >/dev/null 2>&1
sudo runc delete --force "$CID" >/dev/null 2>&1 || true

if sudo test -f "$PROOF"; then
  CONTENT="$(sudo cat "$PROOF" 2>/dev/null)"
  echo "  proof: $CONTENT"
  echo "$CONTENT" | grep -q "uid=0" \
    && ok "payload executed as ROOT on the host (uid=0)" \
    || bad "payload ran but not as uid=0 (did it run via the hook?)"
  if [ -n "$FLAG" ] && printf '%s' "$CONTENT" | grep -qF "$FLAG"; then
    ok "payload exfiltrated the host-only secret the container cannot see — ESCAPE CONFIRMED"
  else
    bad "payload did not read the host-only flag ($FLAG_FILE)"
  fi
else
  bad "no escape-proof.txt — your payload never executed on the host (see hint tiers). Check $BASE/hook.log"
fi

# Reflection gate: understand the root cause, don't just pop the shell.
FIND="$SCRIPT_DIR/FINDINGS.md"
if [ -f "$FIND" ] && grep -qi "ld_preload" "$FIND" && grep -qi "hook" "$FIND" && [ "$(wc -c < "$FIND")" -gt 300 ]; then
  ok "FINDINGS.md documents the root cause"
else
  bad "write FINDINGS.md: name the exact line in vuln-hook.sh that trusts attacker input and why it's the bug (>300 chars; mention LD_PRELOAD, hook)"
fi

echo
echo "Passed: $PASS  Failed: $FAIL"
if [ "$FAIL" -eq 0 ]; then
  echo "PHASE 2 COMPLETE ✅  — you reproduced the NVIDIAScape class from first principles."
  echo "Tell the assistant to scaffold Phase 3 (catch what you just did)."
  exit 0
else
  echo "Not there yet. Fix the [FAIL] lines above."
  exit 1
fi
