The export-the-container's-env loop is the vulnerability; exec /bin/true is just where it goes off. In the real CVE it's the same split — the nvidia hook trusts container-supplied env vars (the bug), and any dynamically-linked execution in the hook is the trigger.


The exact lines for the vulnerable loop is (24-27):
if [ -f "$bundle/config.json" ]; then
  while IFS= read -r kv; do
    [ -n "$kv" ] && export "$kv"
  done < <(jq -r '.process.env[]?' "$bundle/config.json")
fi

This reads the container's process.env — which you, the attacker, control — and exports it straight into the hook's own environment, no validation. That is the line that trusts attacker input. Your LD_PRELOAD becomes the hook's LD_PRELOAD right here.

The hook should be in the vuln-hook.sh — a vulnerable host hook (stands in for nvidia-cdi-hook), wired to run on the host as root before your container. Read it, don't edit it — a real attacker can't patch the vendor's code.

