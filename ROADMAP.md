# GPU-Sec — Project Roadmap

> A self-directed lab that builds one portfolio artifact: **`gpu-sentinel`** — a
> reproducible attack lab + detection pack for GPU / AI-infrastructure compromise.
>
> Design contract: *I (the assistant) give you the idea, the scaffolding, and the
> acceptance tests. You write the exploits and the detections yourself.* The point
> is the struggle, not the answer.

---

## 1. The thesis (why this project is the right one)

The seductive part of "GPU security" — MIG cache side-channels, firmware reverse
engineering, novel DMA exploits — is ~5% of the jobs and needs hardware, NDAs, or
an academic lab. **Don't anchor here.**

The other 95% — the container toolkit, the OCI runtime, the Kubernetes device
plugin, drivers, IOMMU config, and the *detections* on top — is where the actual
CVEs land, and you can do essentially all of it **solo, on a laptop, with no
GPU.** The crown-jewel GPU-cloud vulnerability of the last year, **NVIDIAScape
(CVE-2025-23266, CVSS 9.0)**, is a three-line Dockerfile that abuses `LD_PRELOAD`
and an over-trusting OCI hook. That is Linux, containers, and the dynamic
linker — not silicon.

So the whole project routes through **containers → runtime hooks → detection
engineering**, which is exactly where your existing strengths (Linux depth,
Kubernetes exposure, detection-engineering, class-imbalance modeling) compound.

## 2. What you will have at the end

A public repo (`gpu-sentinel`) containing:

1. A **reproducible lab** that stands up the vulnerable surface on a Linux VM.
2. A **from-scratch container escape** you built, demonstrating the NVIDIAScape
   *class* of bug (LD_PRELOAD into a privileged OCI hook) **with no GPU required**.
3. A **detection pack**: Falco rules + Sigma rules that catch the escape and
   related GPU-node abuse, with a test harness proving each rule fires.
4. A **class-imbalance ML detector** for "cryptominer on a rented GPU node,"
   framed as a rare-event detection problem — your signature move.
5. A **writeup** in the style of your Cyber Threat Hunting series.

That single repo demonstrates GPU-infra security fluency better than any cert.

## 3. Environment constraint (read this first)

You're on **macOS**. The NVIDIA Container Toolkit, `runc`, Falco's eBPF probe,
`auditd`, and IOMMU sysfs are all **Linux-only**. So Phase 0 stands up a Linux VM.

- **Default plan:** a local Linux VM via **Lima** (`brew install lima`) or
  **multipass**. Recent kernel → Falco modern-eBPF works, Docker + runc work,
  namespaces/cgroups/capabilities are all real. Costs nothing.
- **Optional, one afternoon:** rent a single consumer GPU on RunPod/Vast.ai
  (cents/hr) *only* when you want real GPU telemetry for Phase 5. Everything
  else needs no GPU.
- IOMMU/DMA (Phase 1's boundary module) is limited inside a nested VM; you'll
  *read and inspect* the boundary there, and can optionally confirm on a bare
  cloud Linux box.

## 4. The phases

Each phase has the same shape:
**Learning objective** · **What I scaffold** · **What YOU build (the struggle)** ·
**Definition of done** (an objective test you can run).

### Phase 0 — Build the lab  ·  `00-lab/`
- **Objective:** understand the real GPU-node stack by standing it up.
- **I scaffold:** a Lima config, a bootstrap checklist, a stack diagram, and a
  `verify.sh` that asserts the toolchain is present.
- **You build:** the working VM; install Docker, runc/crun, and (later) the
  NVIDIA toolkit; get one GPU-less container running under an explicit runc spec.
- **Done when:** `verify.sh` passes and you can hand-launch a container from a
  raw OCI bundle (not just `docker run`).

### Phase 1 — Feel the isolation boundaries  ·  `01-boundaries/`
- **Objective:** internalize *why* isolation breaks — namespaces, cgroups,
  capabilities, the dynamic linker, and OCI lifecycle hooks. Map the acronyms
  (PCIe, DMA/IOMMU, MIG, SR-IOV) onto "is this boundary real?"
- **I scaffold:** a set of small guided experiments (specs + expected outcomes)
  and an IOMMU/DMA inspection worksheet.
- **You build:** a demonstration that `LD_PRELOAD` injects your code into a
  target process; a minimal OCI `prestart`/`createRuntime` hook that runs on the
  host; and notes on what IOMMU groups you can see.
- **Done when:** you can explain, in your own words in `01-boundaries/NOTES.md`,
  exactly why an OCI hook that inherits container env vars is dangerous.

### Phase 2 — Reproduce the escape (no GPU)  ·  `02-attack/`
- **Objective:** reproduce the **NVIDIAScape class** of container escape from
  first principles.
- **I scaffold:** a *deliberately vulnerable toy OCI hook* spec + a test target
  (a file on the "host" you must read/write from inside the container), plus a
  `check_escape.sh` oracle. No NVIDIA code, no GPU — the toy hook stands in for
  `nvidia-cdi-hook`.
- **You build:** the malicious container image (the LD_PRELOAD payload + the
  `.so`) that escapes through the toy hook and proves host access.
- **Done when:** `check_escape.sh` confirms your payload touched the host target,
  and you can point to the exact line in the hook that trusted attacker input.

### Phase 3 — Telemetry & detection  ·  `03-telemetry/`  +  `04-detections/`
- **Objective:** the core deliverable — catch what you just did.
- **I scaffold:** a Falco install note, a rules skeleton with rule *names and
  intent* but empty conditions, a Sigma template set, and a `test-rules.sh`
  harness that replays the attack and asserts each rule fires (red → green).
- **You build:** the actual Falco conditions and Sigma detections —
  LD_PRELOAD into a runtime hook, unexpected `.so` loads, `nvidia-ctk`/hook
  spawning a shell, container writes to host paths, unexpected kernel-module
  loads, `nvidia-smi` from an unusual parent.
- **Done when:** every rule in the pack goes green in `test-rules.sh`, with a
  documented false-positive check against a benign baseline.

### Phase 4 — Class-imbalance cryptominer detector  ·  `05-ml-cryptominer/`
- **Objective:** your signature move — rare-event detection on node telemetry.
- **I scaffold:** a synthetic telemetry generator skeleton (GPU-util / process /
  netflow time series with a *rare* miner class), a feature-spec, and an
  evaluation harness that scores you on precision/recall/PR-AUC, not accuracy.
- **You build:** the feature engineering + the imbalanced-classification model
  (sampling strategy, threshold, the works) and a short justification of the
  operating point you'd ship to a SOC.
- **Done when:** you beat the naive baseline on PR-AUC and can defend your
  precision/recall trade-off for an on-call analyst.

### Phase 5 — Writeup  ·  `06-writeup/`
- **Objective:** turn the repo into the portfolio piece.
- **I scaffold:** an outline mirroring your Cyber Threat Hunting series.
- **You build:** the post — threat model, the escape, the detections, the ML,
  what a defender should do.
- **Done when:** it reads like something a hiring manager forwards to their team.

## 5. Rules of engagement (our collaboration contract)

- I write **specs, stubs, diagrams, and acceptance tests**. I do **not** write
  your Falco conditions, your exploit payload, or your model for you.
- When you're stuck, ask for a **hint tier**: (1) a nudge, (2) the relevant
  concept + where to look, (3) a worked *analogous* example on different code.
  I default to tier 1.
- Each phase ends at a **green test**, so "done" is never subjective.
- Security scope: everything here runs **inside your own lab VM against targets
  you built**. This is defensive/educational reproduction of a public CVE class,
  not operational offense.

## 6. Suggested pace

~2–3 focused evenings per phase. Phases 0–2 are the foundation; Phase 3 is the
portfolio core; Phases 4–5 are the differentiators. Total: a solid month, and you
have a shareable artifact after Phase 3 alone.

---

*Next step: confirm the environment default (Lima VM) and pick where to start —
recommended is Phase 0. Then I build that phase's scaffolding and hand you the
first challenge.*
