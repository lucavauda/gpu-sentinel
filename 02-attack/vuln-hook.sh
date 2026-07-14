#!/usr/bin/env bash
#
# "AcmeGPU device-setup hook" — stands in for a vendor hook like nvidia-cdi-hook.
#
# It is wired into the runtime as an OCI *createRuntime* hook, which means runc
# runs it on the HOST, as ROOT, before the tenant's container starts. Its job is
# (pretend) to prepare the GPU for the tenant.
#
# You are NOT meant to edit this file. You're meant to READ it, exploit it, and
# then (in FINDINGS.md) point at the exact line that trusts attacker input.
#
# runc feeds every hook the container STATE as JSON on stdin; it includes the
# bundle path. See: https://github.com/opencontainers/runtime-spec (hooks).

state="$(cat)"
bundle="$(printf '%s' "$state" | jq -r '.bundle')"
log=/opt/gpu-sec/hook.log
echo "[vuln-hook] pid=$$ euid=$(id -u) bundle=$bundle" >> "$log"

# Be "helpful": set up our environment the same way the tenant asked for theirs,
# so the device-setup step below sees a consistent toolchain. We read the
# container's requested environment straight from its config and apply it.
if [ -f "$bundle/config.json" ]; then
  while IFS= read -r kv; do
    [ -n "$kv" ] && export "$kv"
  done < <(jq -r '.process.env[]?' "$bundle/config.json")
fi

# "Probe the GPU" with an ordinary dynamically-linked tool and finish.
exec /bin/true
