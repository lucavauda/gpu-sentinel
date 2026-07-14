#!/usr/bin/env bash
#
# Phase 1 acceptance test. Run INSIDE the lima VM, from this directory:
#
#     cd /Users/lucavaudano/myproject/GPU_Sec/01-boundaries
#     bash verify.sh
#
# Three gates:
#   A) your inject.so runs your code when LD_PRELOAD'd into /bin/true
#   B) an OCI hook in your Phase 0 bundle runs on the HOST (writes to a host path)
#   C) NOTES.md substantively explains why A + B = a container escape
#
# Overridable paths:
#   LAB=~/gpu-sec-lab  PRELOAD_SO=$LAB/inject.so  BUNDLE=~/gpu-sec-bundle

set -uo pipefail

LAB="${LAB:-$HOME/gpu-sec-lab}"
PRELOAD_SO="${PRELOAD_SO:-$LAB/inject.so}"
BUNDLE="${BUNDLE:-$HOME/gpu-sec-bundle}"
PRELOAD_PROOF="$LAB/preload_proof.txt"
HOOK_PROOF="$LAB/hook_proof.txt"
# Anchor NOTES.md to THIS script's directory, so verify.sh works from any cwd.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NOTES="$SCRIPT_DIR/NOTES.md"

PASS=0; FAIL=0
ok()   { echo "  [ok]   $1"; PASS=$((PASS+1)); }
bad()  { echo "  [FAIL] $1"; FAIL=$((FAIL+1)); }
info() { echo "  [..]   $1"; }

echo "== Phase 1 verify =="

[ "$(uname -s)" = "Linux" ] && ok "running on Linux" \
  || bad "not Linux — run inside 'limactl shell gpu-sec'"

# --- Gate A: LD_PRELOAD injection ---
rm -f "$PRELOAD_PROOF"
if [ -f "$PRELOAD_SO" ]; then
  LD_PRELOAD="$PRELOAD_SO" /bin/true >/dev/null 2>&1 || true
  if [ -f "$PRELOAD_PROOF" ] && grep -q "ld-preload-fired" "$PRELOAD_PROOF"; then
    ok "A: inject.so ran via LD_PRELOAD (wrote token into /bin/true's process)"
  else
    bad "A: preloading $PRELOAD_SO into /bin/true did not write 'ld-preload-fired' to $PRELOAD_PROOF"
  fi
else
  bad "A: no library at $PRELOAD_SO — build one whose code runs on load (see README Challenge A)"
fi

# --- Gate B: OCI hook runs on the host ---
rm -f "$HOOK_PROOF"
if [ -f "$BUNDLE/config.json" ]; then
  CID="gpu-sec-p1-$$"
  sudo runc delete --force "$CID" >/dev/null 2>&1 || true
  sudo timeout 15 runc run -b "$BUNDLE" "$CID" </dev/null >/dev/null 2>&1
  sudo runc delete --force "$CID" >/dev/null 2>&1 || true
  if [ -f "$HOOK_PROOF" ] && grep -q "oci-hook-ran-on-host" "$HOOK_PROOF"; then
    ok "B: an OCI hook ran on the host (created $HOOK_PROOF, which is outside the container rootfs)"
    UID_SEEN="$(grep -oE 'uid=[0-9]+' "$HOOK_PROOF" | head -1)"
    [ -n "$UID_SEEN" ] && info "B: hook recorded $UID_SEEN — note whether that's host root (uid=0)"
  else
    bad "B: running $BUNDLE produced no host-side $HOOK_PROOF — add a hook to config.json (see README Challenge B)"
  fi
else
  bad "B: no bundle at $BUNDLE/config.json — reuse your Phase 0 bundle"
fi

# --- Gate C: the write-up ---
if [ -f "$NOTES" ]; then
  if grep -qi "ld_preload" "$NOTES" && grep -qi "hook" "$NOTES" \
     && grep -qi "host" "$NOTES" && [ "$(wc -c < "$NOTES")" -gt 500 ]; then
    ok "C: NOTES.md explains the fusion (mentions LD_PRELOAD, hook, host; >500 chars)"
  else
    bad "C: NOTES.md is thin — explain why a hook inheriting the container's LD_PRELOAD is an escape (mention LD_PRELOAD, hook, host; >500 chars)"
  fi
else
  bad "C: no NOTES.md — copy NOTES.template.md to NOTES.md and fill it in"
fi

echo
echo "Passed: $PASS   Failed: $FAIL"
if [ "$FAIL" -eq 0 ]; then
  echo "PHASE 1 COMPLETE ✅  — tell the assistant to scaffold Phase 2."
  exit 0
else
  echo "Not done yet. Fix the [FAIL] lines above."
  exit 1
fi
