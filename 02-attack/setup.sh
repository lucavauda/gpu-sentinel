#!/usr/bin/env bash
#
# Phase 2 setup — provisions the "cloud vendor" side of the lab (the part YOU,
# as a tenant, do not control). Run once, inside the VM:
#
#     cd /Users/lucavaudano/myproject/GPU_Sec/02-attack
#     bash setup.sh
#
# It creates /opt/gpu-sec containing:
#   - a HOST-ONLY secret the container can never see (proof target for an escape)
#   - a benign busybox "base image" rootfs
#   - the vulnerable vendor hook, wired into the bundle as a createRuntime hook
#   - a config.json with a benign tenant process and NO attacker payload yet
#
# After this runs, everything the vendor controls is in place. Your job (README)
# is to weaponise the image: add your evil.so and set LD_PRELOAD.

set -euo pipefail
BASE=/opt/gpu-sec
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "[*] Creating $BASE (needs sudo)"
sudo mkdir -p "$BASE/host-only" "$BASE/attack-bundle/rootfs"

echo "[*] Planting a host-only secret (root:600, outside the container rootfs)"
FLAG="FLAG-$(head -c 8 /dev/urandom | od -An -tx1 | tr -d ' \n')"
printf '%s\n' "$FLAG" | sudo tee "$BASE/host-only/flag.txt" >/dev/null
sudo chmod 600 "$BASE/host-only/flag.txt"

echo "[*] Building a benign base-image rootfs (busybox)"
if [ ! -e "$BASE/attack-bundle/rootfs/bin" ]; then
  docker create --name gpu-sec-p2 busybox >/dev/null
  docker export gpu-sec-p2 | sudo tar -xf - -C "$BASE/attack-bundle/rootfs"
  docker rm gpu-sec-p2 >/dev/null
fi

echo "[*] Installing the (vulnerable) vendor hook"
sudo cp "$HERE/vuln-hook.sh" "$BASE/vuln-hook.sh"
sudo chmod +x "$BASE/vuln-hook.sh"

echo "[*] Generating the bundle config (benign process + hook wired at top level)"
cd "$BASE/attack-bundle"
[ -f config.json ] || sudo runc spec
sudo bash -c 'cd '"$BASE"'/attack-bundle && jq "
    .process.args = [\"/bin/echo\", \"tenant-workload-ran\"] |
    .process.terminal = false |
    .hooks.createRuntime = [ { \"path\": \"/opt/gpu-sec/vuln-hook.sh\", \"args\": [\"/opt/gpu-sec/vuln-hook.sh\"] } ]
  " config.json > config.tmp && mv config.tmp config.json'

echo "[*] Handing the bundle to you (so you can edit config.json and add files)"
sudo chown -R "$(id -u):$(id -g)" "$BASE/attack-bundle"

echo
echo "[+] Vendor side provisioned."
echo "    Secret:  $BASE/host-only/flag.txt   (root:600 — the container can't read it)"
echo "    Bundle:  $BASE/attack-bundle        (yours to weaponise)"
echo "    Hook:    $BASE/vuln-hook.sh         (read it — do not edit it)"
echo "    Now build your exploit — see README.md."
