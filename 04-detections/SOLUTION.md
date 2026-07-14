# Phase 4 — Solution notes (detection pack)

Turning the attack's telemetry footprint into a Falco + Sigma detection pack that
**fires on the escape and stays silent on a benign baseline.** The bar isn't
"can I alert on it" — it's "can I alert on it without drowning a SOC." Blog gold.

## The three core rules (final)

All syscall rules pin `evt.dir=<` (syscall exit, where `proc.*`/`fd.*` are
populated) and anchor on `proc.aname in (runc)` — "any ancestor is the runtime."

**1. Cause — LD_PRELOAD in the runtime hook chain**
```
evt.type=execve and evt.dir=< and
proc.env contains "LD_PRELOAD=" and
proc.aname in (runc)
```
Catches the *mechanism*: a runtime-hook-descended process whose environment
carries `LD_PRELOAD`. Lowest false positive, survives payload changes.

**2. Artifact — unexpected shared object during container setup**
```
evt.type in (open,openat,openat2) and evt.dir=< and
fd.name endswith ".so" and
proc.aname in (runc) and
not fd.name startswith "/lib" and not fd.name startswith "/usr/lib"
```
Catches `evil.so`. The `/lib` `/usr/lib` excludes are what keep it quiet when
`ls`/`cat` load libc in the baseline.

**3. Effect — host-only path accessed by the runtime hook**
```
evt.type in (open,openat,openat2) and evt.dir=< and
proc.aname in (runc) and
fd.name startswith "/opt/gpu-sec/host-only"
```
Catches the escaped code reading the host secret. Scoped to `host-only` (not a
broad `/opt/gpu-sec`) so the benign bundle's own rootfs under `/opt/gpu-sec/…`
can't trip it.

## Design lessons (the senior-level bits)

- **Cause > effect.** Rule 1 catches the *why* and generalises; Rules 2–3 catch
  *this* payload's artifacts — good backstops, brittle alone. A mature pack layers
  both.
- **Context kills false positives.** `.so loaded` is noise. `.so loaded by a
  runc-descended process from a non-standard path` is signal. The anchors
  (`proc.aname in (runc)`, path scoping, standard-dir excludes) are the whole game.
- **The baseline forces precision.** The false-positive check runs real host
  activity (`ls`, `cat` → libc loads). A lazy "any `.so`" or "any `/opt/gpu-sec`"
  rule fails it — which is the point. It made me scope Rule 2's paths and Rule 3's
  prefix. A detection isn't done when it fires; it's done when it *only* fires.

## Gotchas hit

- **`proc.aname in (runc)`, not `contains`.** `proc.aname` is the ancestor *set*;
  membership uses `in`, and it matches any ancestor. `contains` misbehaves.
- **`evt.dir=<` matters.** Without it the rule also evaluates on syscall enter,
  where `proc.env`/`fd.name` aren't ready → empty fields / double eval.
- **`container.rootfs` is not a Falco field** — referencing it fails rule load.
- **Rule 3 target.** First draft used generic sensitive prefixes (`/etc`, `/root`,
  …) that the attack never touches, so it never fired. The lab's host-only
  resource is `/opt/gpu-sec/host-only` — detect the thing the attack actually hits.
- **Harness self-bug.** The stub-check grepped the whole file for the TODO
  sentinel, matching the *header comment*; fixed to ignore comment lines.

## Sigma — and the blind spot worth naming

The Sigma (portable/SIEM) equivalent runs into a real limitation: many
`process_creation` log sources (Sysmon-for-Linux, auditd) **don't capture a
process's environment**, so `LD_PRELOAD` — trivial for Falco via eBPF (`proc.env`)
— may be *invisible* to a plain SIEM. The portable rule therefore has to fall back
to the **process relationship** (a runtime/hook parent spawning a dynamically-linked
child) rather than the env var itself. *Knowing which detections your telemetry can
and can't support* is the senior-analyst move — call it out explicitly in the blog.

## What this pack is

A detection suite that provably catches a real-CVE-class (NVIDIAScape) GPU-infra
escape, cause + artifact + effect layered, with a documented false-positive
profile. That's the spine of the Phase 6 writeup.
