# Phase 2 — Reproduce the escape (NVIDIAScape class, no GPU)

**Learning objective:** stop building the two primitives separately and **fuse
them into one working exploit.** You'll ship a malicious container image that
escapes to the host through a vendor hook you don't control — reproducing the
CVE-2025-23266 class from first principles. This is your C paragraph, as code.

## The threat model (this is the whole point)

You are the **tenant/attacker**. You control **only the container image** — its
filesystem and its environment variables. You do **not** control the runtime, the
hook, or the host. The "cloud vendor" side is provisioned for you by `setup.sh`:

- a **host-only secret** at `/opt/gpu-sec/host-only/flag.txt` (`root:600`) — the
  container cannot see it (wrong mount namespace *and* wrong permissions);
- a benign busybox base image;
- a **vulnerable vendor hook** (`vuln-hook.sh`, stands in for `nvidia-cdi-hook`)
  wired as an OCI `createRuntime` hook — so it runs **on the host, as root**,
  before your container starts.

Your escape succeeds when *your* code runs on the host as root and reads that
secret — using nothing but a crafted image.

## What I gave you

- `setup.sh` — provisions the vendor side into `/opt/gpu-sec`. Run once.
- `vuln-hook.sh` — the vulnerable hook. **Read it. Do not edit it.** Your exploit
  must work against it as-is (a real attacker can't patch the vendor's hook).
- `check_escape.sh` — the oracle: runs your bundle and confirms the escape.

## What YOU build

1. **The payload — `evil.so`.** Same constructor trick as Phase 1 Challenge A,
   but now the constructor does something that *proves host compromise*: it reads
   the host-only secret and writes proof of who it ran as. Specifically, make its
   constructor:
   - read `/opt/gpu-sec/host-only/flag.txt`,
   - write `/opt/gpu-sec/escape-proof.txt` containing `uid=<effective uid>` and
     the flag contents.
   Compile it (`gcc -shared -fPIC -o evil.so evil.c`) and place it where the
   host hook can load it (e.g. inside the image: `/opt/gpu-sec/attack-bundle/rootfs/evil.so`).

2. **The delivery — set `LD_PRELOAD`.** As the tenant you control the container's
   `process.env`. Add an `LD_PRELOAD` entry pointing at your `evil.so`. That's the
   only "delivery" you need — the vendor hook does the rest, unwittingly.

3. **`FINDINGS.md`.** After it works, name the **exact line in `vuln-hook.sh`**
   that trusts attacker-controlled input, and explain why it's the bug. (>300
   chars, mention `LD_PRELOAD` and the hook.) This is the writeup that turns an
   exploit into a vulnerability report.

## Run it

```bash
cd /Users/lucavaudano/myproject/GPU_Sec/02-attack
bash setup.sh                 # once: provisions the vendor side
# ... build evil.so, set LD_PRELOAD in /opt/gpu-sec/attack-bundle/config.json ...
bash check_escape.sh          # the oracle
```

## Definition of done

`check_escape.sh` prints `PHASE 2 COMPLETE ✅` — your payload ran as **uid=0 on
the host** and exfiltrated the host-only flag, and `FINDINGS.md` explains the root
cause. You reproduced NVIDIAScape with no GPU and no kernel bug.

## Hint tiers (ask by number)

**Payload (`evil.so`)**
- **P1:** you already wrote 90% of this in Phase 1 Challenge A — a constructor
  that writes a file. Change *what* it writes: read one file, write another,
  include `geteuid()`.
- **P2:** `#include <unistd.h>` for `geteuid()`; `fopen` the flag for read, `fopen`
  the proof for write, `fprintf(proof, "uid=%d flag=%s", geteuid(), buf)`.
- **P3:** near-complete `evil.c`, you fill the two paths.

**Delivery (`LD_PRELOAD`)**
- **D1:** which env var makes the host's dynamic linker load your library into the
  hook's exec'd process? You control `process.env`.
- **D2:** `jq '.process.env += ["LD_PRELOAD=/opt/gpu-sec/attack-bundle/rootfs/evil.so"]' config.json` (point it at *your* .so path).

**If nothing happens**
- Read `/opt/gpu-sec/hook.log` — did the hook run, and as what uid?
- Is your `evil.so` path readable by root? Is it actually a valid shared object
  (`file evil.so`)?
- Did the hook see your env? (`jq '.process.env' config.json`)

## Why Phase 3 needs this

Everything you just did is *observable*: a hook spawning with `LD_PRELOAD`, an
unexpected `.so` loaded into a host process, a write to a host path from a
container launch. Phase 3 turns `check_escape.sh` into a **detection** target —
you'll catch this attack with Falco and Sigma. Keep the working exploit; it's your
red-team fixture.
