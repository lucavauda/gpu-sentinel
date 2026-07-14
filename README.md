# gpu-sentinel

A self-directed lab that reproduces the **NVIDIAScape** container-escape class
(**CVE-2025-23266**, CVSS 9.0) from first principles — **with no GPU** — and then
catches it two ways: a Falco + Sigma detection pack, and a class-imbalance ML
detector for cryptominers on GPU nodes.

> A host-privileged process trusted attacker-controlled input — an inherited
> `LD_PRELOAD` pointing at an attacker-supplied library — so the attacker's code
> ran as root on the host. That sentence is CVE-2025-23266.

The whole thing routes through **containers → OCI runtime hooks → detection
engineering**, because that's where the real GPU-cloud CVEs land and where one
person can work solo on a laptop. "GPU security" turns out to be mostly Linux
security.

## 📖 The writeup

The full story on how I built it, what broke, and what I learned is the artifact:

**→ [`06-writeup/final.md`](06-writeup/final.md)**

Start there for the narrative. The folders below are the lab it's built on.

## Repo layout

Each phase is a self-contained folder with a `README.md` (the task), a `verify.sh`
(the acceptance test), and a `SOLUTION.md` (what I did and why).

| Phase | Folder | What it does |
|-------|--------|--------------|
| 0 | [`00-lab/`](00-lab/) | Stand up the Linux VM; launch a container from a raw OCI bundle via `runc` (no Docker) |
| 1 | [`01-boundaries/`](01-boundaries/) | Build the two primitives by hand: `LD_PRELOAD` injection and host-side OCI hooks |
| 2 | [`02-attack/`](02-attack/) | Fuse them into the NVIDIAScape-class escape and read a host-only secret as root |
| 3 | [`03-telemetry/`](03-telemetry/) | Stand up Falco (eBPF) and prove the sensor sees the attack |
| 4 | [`04-detections/`](04-detections/) | The detection pack: 3 layered Falco rules + a Sigma rule, red→green harness + benign baseline |
| 5 | [`05-ml-cryptominer/`](05-ml-cryptominer/) | Cryptominer-on-GPU-node detection as a class-imbalance problem (pure Python) |
| — | [`06-writeup/`](06-writeup/) | The writeup |

See [`ROADMAP.md`](ROADMAP.md) for the original phase-by-phase plan.

## Run it yourself

Phases 0–4 need a Linux VM (the toolchain — `runc`, Falco eBPF, `auditd` — is
Linux-only). On macOS I used [Lima](https://lima-vm.io/):

```bash
brew install lima
limactl start --name=gpu-sec 00-lab/lima-gpu-sec.yaml
limactl shell gpu-sec
```

Then each phase ends at a green test, e.g.:

```bash
cd 00-lab && ./verify.sh          # PHASE 0 COMPLETE ✅
```

Phase 5 needs no VM and no GPU — just Python:

```bash
cd 05-ml-cryptominer
pip install -r requirements.txt
python3 generate_data.py && python3 model.py && bash verify_ml.sh
```

Some artifacts are generated and git-ignored (the OCI `rootfs`, the ML datasets,
Falco run logs); the scripts above rebuild them.

## Scope & safety

This is a **defensive, educational** reproduction of a public, patched CVE class.
Everything runs **inside my own lab VM, against targets I built** — the "vulnerable
vendor hook" is a deliberately-written stand-in, not real NVIDIA code. Nothing here
is operational offense.

## Built with a coding agent

I built this with [Claude Code](https://claude.com/claude-code) under a strict
contract: the agent writes the specs, diagrams, and acceptance tests; I write the
exploit, the detection rules, and the model. Every phase ends at an objective green
test. More on that in the [writeup](06-writeup/final.md).
