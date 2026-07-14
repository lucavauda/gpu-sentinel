# Phase 3 — Telemetry: make the sensor see the attack

**Learning objective:** stand up a runtime security sensor (**Falco**, eBPF) and
prove it observes your Phase 2 escape. This is the detection-engineer's
prerequisite: *you can't write a detection for something you can't see.* You'll
also map the attack to its observable events — the raw material for Phase 4's
rules.

This is the pivot to your actual strength. Phases 0–2 made you the attacker;
from here you're the defender.

## What I gave you

- `capture.yaml` — a broad **debug** ruleset (a telemetry *tap*, not a detection)
  that logs execs and `.so`/lab-path opens so you can see the attack in the event
  stream.
- `capture.sh` — starts Falco with that tap, replays the Phase 2 attack, prints
  the attack-related events.
- `verify_telemetry.sh` — the acceptance test.
- `telemetry-map.md` — the worksheet: map each attack step → observable event.

## What YOU build

1. **Install Falco** and get its eBPF sensor running in the VM (the ops skill).
2. **Run `capture.sh`** and *see your own attack* in the telemetry.
3. **Fill in `telemetry-map.md`** — this is the intellectual work: which events
   betray the attack, which are strong vs noisy signals.

## Install Falco

```bash
curl -fsSL https://falco.org/repo/falcosecurity-packages.asc \
  | sudo gpg --dearmor -o /usr/share/keyrings/falco-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/falco-archive-keyring.gpg] https://download.falco.org/packages/deb stable main" \
  | sudo tee /etc/apt/sources.list.d/falcosecurity.list
sudo apt-get update
sudo apt-get install -y dialog          # avoids the install prompt hanging
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y falco
```

Recent Falco (≥0.37) uses the **modern eBPF** driver by **default** — driverless,
no kernel module to build (the old `--modern-bpf` flag was removed). Test it runs:

```bash
sudo falco -M 5 -o stdout_output.enabled=true
```

If it starts, loads rules, and reports `event drop detected: 0` after ~5s, the
sensor works (`Events detected: 0` is fine — nothing malicious happened yet).

## Run it

```bash
cd /Users/lucavaudano/myproject/GPU_Sec/03-telemetry
bash capture.sh            # start sensor, replay attack, show captured events
# ... fill in telemetry-map.md using what you saw ...
bash verify_telemetry.sh   # acceptance test
```

## Definition of done

`verify_telemetry.sh` prints `PHASE 3 (telemetry) COMPLETE ✅` — Falco captured the
hook exec, the `evil.so` load, and the escape-file access, and `telemetry-map.md`
is filled in.

## Troubleshooting (nested VM gotchas)

- **`modern-bpf` won't load / no events.** Check `falco.err`. Modern eBPF needs
  kernel BTF (`ls /sys/kernel/btf/vmlinux` should exist — it does on 6.8). If it
  still fails in this nested Apple VM, try the kernel-module driver:
  `sudo falcoctl driver config --type kmod && sudo falcoctl driver install`,
  then run `sudo falco` (no `--modern-bpf`). You installed kernel headers in
  Phase 0, so the module can build.
- **Falco starts but captures nothing.** Give it more time to initialise before
  the replay (raise the wait in `capture.sh`), and confirm the attack still works
  (`bash ../02-attack/check_escape.sh`).
- **Truly stuck on Falco in this VM?** Tell me — the detection *logic* is
  identical on `auditd`, and we can switch the telemetry source without losing the
  Phase 4 work. Falco is the preferred (marketable) path, so try it first.

## Why Phase 4 needs this

Every green line here is a candidate detection. In Phase 4 you turn the strongest
signals from `telemetry-map.md` into precise Falco rules (and Sigma equivalents),
with a test harness that replays the attack and proves each rule fires — while
staying quiet on a benign baseline.
