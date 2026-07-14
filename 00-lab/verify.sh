#!/usr/bin/env bash
#
# Phase 0 acceptance test. Run this INSIDE the lima VM:
#
#     limactl shell gpu-sec
#     cd ~/myproject/GPU_Sec/00-lab   # (or wherever the repo is mounted)
#     ./verify.sh
#
# It checks the toolchain is present AND that YOU completed the challenge:
# a hand-built OCI bundle at ./bundle/ that, when run with `runc`, prints the
# exact token below. Docker gives you a rootfs; assembling and launching the
# bundle by hand is the part you have to figure out (see README.md).

set -uo pipefail

TOKEN="gpu-sec-phase0-ok"
# Where your OCI bundle lives. Defaults to ./bundle, but you can point it at the
# VM's native filesystem (which handles a root filesystem better than the shared
# mount does):   BUNDLE=~/gpu-sec-bundle ./verify.sh
BUNDLE="${BUNDLE:-./bundle}"
PASS=0
FAIL=0

ok()   { echo "  [ok]   $1"; PASS=$((PASS+1)); }
bad()  { echo "  [FAIL] $1"; FAIL=$((FAIL+1)); }
info() { echo "  [..]   $1"; }

echo "== Phase 0 verify =="

# 1. We must be on Linux (i.e. inside the VM, not macOS).
if [ "$(uname -s)" = "Linux" ]; then ok "running on Linux ($(uname -r))"
else bad "not Linux — run this inside 'limactl shell gpu-sec', not on macOS"; fi

# 2. Toolchain.
command -v docker >/dev/null 2>&1 && ok "docker present" || bad "docker missing"
command -v runc   >/dev/null 2>&1 && ok "runc present"   || bad "runc missing"
command -v crun   >/dev/null 2>&1 && ok "crun present"   || info "crun missing (optional)"
command -v auditctl >/dev/null 2>&1 && ok "auditd present" || info "auditd missing (needed in Phase 3)"

# 3. Docker actually runs a container.
if docker run --rm hello-world >/dev/null 2>&1; then ok "docker can run a container"
else bad "docker cannot run a container (try 'newgrp docker' or re-login)"; fi

# 4. THE CHALLENGE: your hand-built OCI bundle prints the token via runc.
#    Expected layout you create:  ./bundle/config.json  +  ./bundle/rootfs/
#    Your config.json's process.args must run something that echoes:  $TOKEN
if [ -f "$BUNDLE/config.json" ] && [ -d "$BUNDLE/rootfs" ]; then
  ok "OCI bundle exists ($BUNDLE/config.json + $BUNDLE/rootfs)"
  # runc needs root. This assumes passwordless sudo in the lab VM (Lima default,
  # or a /etc/sudoers.d NOPASSWD rule). NOTE: don't use `sudo -v` here — it forces
  # credential validation and prompts for a password even under NOPASSWD, which
  # hangs on a passwordless account. A plain `sudo <cmd>` does not.
  CID="gpu-sec-p0-$$"
  sudo runc delete --force "$CID" >/dev/null 2>&1 || true   # clear any stale state
  # -b points runc at the bundle dir; without it runc looks for config.json in cwd.
  # </dev/null: never let runc block waiting on our stdin.
  # timeout 15: a hang becomes a clean failure instead of an infinite wait.
  OUT="$(sudo timeout 15 runc run -b "$BUNDLE" "$CID" </dev/null 2>/dev/null)"
  rc=$?
  sudo runc delete --force "$CID" >/dev/null 2>&1 || true
  if [ "$rc" -eq 124 ]; then
    bad "runc timed out (15s) — run the manual debug in README.md to see the error"
  elif echo "$OUT" | grep -q "$TOKEN"; then
    ok "bundle ran under runc and printed the token"
  else
    bad "bundle ran but did not print '$TOKEN' (got: '${OUT:0:60}...')"
  fi
else
  bad "no OCI bundle yet at '$BUNDLE' — build it so 'runc run' prints '$TOKEN' (see README.md)"
fi

echo
echo "Passed: $PASS   Failed: $FAIL"
if [ "$FAIL" -eq 0 ]; then
  echo "PHASE 0 COMPLETE ✅  — tell the assistant to scaffold Phase 1."
  exit 0
else
  echo "Not done yet. Fix the [FAIL] lines above."
  exit 1
fi
