#!/usr/bin/env bash
#
# Phase 4 — build the BENIGN baseline bundle (a normal tenant workload: no hook,
# no LD_PRELOAD, no payload). test-rules.sh runs it to prove your detections stay
# quiet on ordinary activity. Run once:
#
#     bash setup-baseline.sh

set -euo pipefail
BASE=/opt/gpu-sec
sudo mkdir -p "$BASE/benign-bundle/rootfs"

if [ ! -e "$BASE/benign-bundle/rootfs/bin" ]; then
  docker create --name gpu-sec-benign busybox >/dev/null
  docker export gpu-sec-benign | sudo tar -xf - -C "$BASE/benign-bundle/rootfs"
  docker rm gpu-sec-benign >/dev/null
fi

cd "$BASE/benign-bundle"
[ -f config.json ] || sudo runc spec
# benign process, NO hooks at all, NO LD_PRELOAD
sudo bash -c 'cd '"$BASE"'/benign-bundle && jq "
    .process.args = [\"/bin/echo\", \"benign-workload\"] |
    .process.terminal = false |
    del(.hooks)
  " config.json > config.tmp && mv config.tmp config.json'
sudo chown -R "$(id -u):$(id -g)" "$BASE/benign-bundle"

echo "[+] Benign baseline ready at $BASE/benign-bundle (no hook, no payload)."
