# Phase 4 — The detection pack (Falco + Sigma)

**Learning objective:** the portfolio centerpiece. Turn the strong signals from
your `telemetry-map.md` into **precise runtime detections** that catch your Phase 2
escape *without* drowning a SOC in false positives. This is your actual craft —
detection engineering — applied to GPU/AI-infra compromise.

## The bar (what "good" means here)

A detection that fires on the attack is easy. A detection that fires on the attack
**and stays silent on normal activity** is the job. The harness enforces both:
red→green on the attack, and a **benign baseline** that must produce zero alerts.

## What I gave you

- `falco/gpu-sec-rules.yaml` — the rule pack. **3 core rules** with intent, output,
  and field hints, but **stubbed conditions** (`__TODO_REPLACE_ME__`) for you to
  write. Plus 2 **bonus** rules (nvidia-smi/kmod) for breadth — not gated.
- `sigma/ld_preload_runtime_hook.yml` — a Sigma template (portable SIEM rule) to
  fill; includes a real-world lesson about env-var visibility in process logs.
- `setup-baseline.sh` — builds the benign baseline bundle.
- `test-rules.sh` — the acceptance harness (fires-on-attack + quiet-on-benign +
  Sigma structural check).

## What YOU build

Write the `condition:` for each of the 3 core rules, mapping your telemetry:

1. **LD_PRELOAD in Container Runtime Hook Chain** (cause) — an `execve` whose
   `proc.env` contains `LD_PRELOAD` and which descends from `runc` (`proc.aname`).
2. **Unexpected Shared Object Loaded During Container Setup** (artifact) — an open
   of a `.so` by a runc-descended process, from a **non-standard** path (exclude
   `/lib`, `/usr/lib`, … or the benign baseline will flag you).
3. **Host Path Accessed by Container Runtime Hook** (effect) — a runc-descended
   process opening a sensitive host prefix.

Then fill the **Sigma** rule (at least the one provided), and write your
false-positive reasoning into the rule `desc`/`falsepositives`.

## Run it

```bash
cd /Users/lucavaudano/myproject/GPU_Sec/04-detections
bash setup-baseline.sh                 # once
# ... edit falco/gpu-sec-rules.yaml + sigma/*.yml ...
bash test-rules.sh
```

## Definition of done

`test-rules.sh` prints `PHASE 4 COMPLETE ✅`:
- all 3 core rules **fire** on the replayed attack,
- **none** fire on the benign baseline + ordinary host activity,
- Sigma rule(s) are filled in.

## The design lessons to internalise (blog gold)

- **Cause > effect.** Rule 1 (LD_PRELOAD in the hook chain) catches the *mechanism*
  and survives payload changes. Rules 2–3 catch *this* payload's artifacts — good
  backstops, brittle alone. A mature pack has both, layered.
- **Context kills false positives.** `.so loaded` is noise; `.so loaded by a
  runc-descended process from a non-standard path` is signal. The anchor
  (`proc.aname in (runc)`, non-standard path) is what makes it deployable.
- **Know your telemetry's blind spots.** The Sigma template makes you confront that
  many process-creation log sources don't record env vars — so the *cause-level*
  detection you can do easily in Falco (eBPF sees `proc.env`) may be impossible in
  a plain SIEM. Naming that gap is senior-level analysis.

## Hint tiers (ask by number)

- **T1:** re-read your `telemetry-map.md` row for that rule — the fields you need
  are the ones you already wrote down.
- **T2:** the specific Falco fields/operators for that rule (e.g. `proc.env
  icontains "LD_PRELOAD"`, `proc.aname in (runc)`, `fd.name endswith ".so"`,
  `not fd.directory pmatch (/lib, /usr/lib, /lib64, /usr/lib64)`).
- **T3:** a worked condition for *one* rule, which you adapt to the others.

If a rule won't fire, check `falco.err` for load errors, and inspect `mal.out` to
see what events/fields the attack actually produced.

## Why Phases 5–6 build on this

Phase 5 adds the **cryptominer-on-GPU-node** detection as a class-imbalance ML
problem (your signature). Phase 6 turns this whole repo — attack, telemetry,
detections, ML — into the writeup. This pack is the spine of that story.
