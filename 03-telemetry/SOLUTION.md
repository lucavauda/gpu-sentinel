# Phase 3 — Solution notes (telemetry)

Standing up a runtime sensor (Falco/eBPF) and proving it *sees* the Phase 2
escape. The detection-engineer's prerequisite: you can't detect what you can't
observe. Blog material.

## Goal

Get Falco capturing syscall telemetry in the VM, replay the Phase 2 attack, and
confirm the sensor observes its footprint — then map each attack step to the event
a sensor sees. No rules yet; that's Phase 4.

## What I set up

- **Falco** (0.44.1) via the official apt repo. Recent Falco uses the **modern
  eBPF driver by default** — driverless (no kernel module to compile), which is
  exactly what you want in a nested VM.
- A **debug telemetry tap** (`capture.yaml`) — a deliberately broad ruleset that
  logs every `execve` and every open of a `.so` or a `/opt/gpu-sec` path. This is
  a *tap*, not a detection: it exists to prove the events are visible. Phase 4
  replaces this firehose with precise rules.
- `capture.sh` — starts Falco with the tap, replays the attack via `runc`, stops
  Falco, and greps the JSON output for attack-related events.

## Gotchas hit

1. **`--modern-bpf` flag removed.** On Falco ≥0.37 modern eBPF is the default, so
   the flag errors with "Option 'modern-bpf' does not exist." Just run `sudo
   falco` — no driver flag. (`event drop detected: 0` + `Events detected: 0` on an
   idle run = healthy sensor, not a failure.)
2. **Backgrounding Falco under sudo.** `sudo falco ... &` then killing the shell's
   `$!` doesn't reliably stop Falco (sudo's child). Use `sudo pkill -f capture.yaml`.
3. **Timing.** The eBPF driver takes a few seconds to attach; if you replay the
   attack too soon, the capture is empty. `capture.sh` sleeps before replaying.

## The attack's telemetry footprint (what the sensor saw)

Replaying the escape produced a clean, legible chain of events:

| Attack step | Event captured |
|-------------|----------------|
| runc runs the hook | `execve` of `vuln-hook.sh` (bash), parent `runc` |
| hook execs the helper | `execve` of `/bin/true`, parent `vuln-hook.sh` |
| `ld.so` loads the payload | `openat` of `evil.so` (a `.so` from a container/rootfs path) |
| payload reads the secret | `openat` of `/opt/gpu-sec/host-only/flag.txt` |
| payload writes proof | `openat`/write of `/opt/gpu-sec/escape-proof.txt` |

Seeing my own Phase 2 escape as a syscall stream — from the *defender's* seat — is
the whole point of the hat-swap.

## The detection-engineering takeaways (into Phase 4)

Filling `telemetry-map.md` forced the questions that actually matter for writing
good rules — recorded here as principles, with the concrete rules left to Phase 4:

- **Map before you detect.** Enumerate the observable events *first*; each strong
  signal becomes one rule.
- **Strong vs noisy.** A `.so` load on its own is hopelessly noisy (every process
  loads libraries constantly). The *context* is what makes a signal —
  e.g. a `.so` loaded by an **OCI hook / runtime helper**, or a hook process whose
  **environment carries `LD_PRELOAD`**. Falco exposes process env (`proc.env`),
  which is what lets you catch the *cause*, not just the *effect*.
- **Cause vs effect.** Detecting the *effect* (a write to a host path during a
  container launch) is easy but brittle — change the payload's target and it
  evades. Detecting the *cause* (a runtime hook running with an attacker
  `LD_PRELOAD`) generalises across payload variants. Prefer cause-level detections;
  keep effect-level ones as backstops.

## Next

The strong signals identified above are the Phase 4 rule set: turn each into a
precise Falco rule (+ a Sigma equivalent), with a harness that replays the attack
to prove each fires — and a benign baseline to prove it stays quiet. The
`check_escape.sh` fixture and this telemetry tap are what those rules run against.
