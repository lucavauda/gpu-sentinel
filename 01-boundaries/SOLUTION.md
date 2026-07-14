# Phase 1 — Solution notes (Challenges A & B)

The two isolation primitives, built by hand, with the *why* and the gotchas —
raw material for the blog. **Challenge C (the fusion) is intentionally left to
`NOTES.md`; it's the reflective deliverable, not documented here.**

Environment recap: work inside the Lima VM; build artifacts live on the VM's
native fs at `~/gpu-sec-lab` (= `/home/lucavaudano.guest/gpu-sec-lab`), off the
shared mount. Passwordless sudo lets `runc` run.

---

## Challenge A — `LD_PRELOAD` injection

**Goal:** make *your* code run inside a process you didn't write (`/bin/true`),
proving it by writing the token `ld-preload-fired` to a proof file.

**The mechanism — a constructor, not interposition.** LD_PRELOAD has two distinct
powers, and this challenge needs the second:
- *Interposition* — define a function with the same name as one the target calls
  (e.g. `puts`); yours is found first and wins. But it only runs *if* the target
  calls it — and `/bin/true` calls nothing worth overriding.
- *Constructor* — a function marked `__attribute__((constructor))` is placed in
  the library's `.init_array`, which the dynamic linker runs **at load time,
  before `main()`, unconditionally.** That's what fires inside `/bin/true`.

```c
// inject.c (shape)
__attribute__((constructor))
void go(void) {
    FILE *f = fopen("/home/lucavaudano.guest/gpu-sec-lab/preload_proof.txt", "w");
    if (f) { fputs("ld-preload-fired\n", f); fclose(f); }
}
```

```bash
gcc -shared -fPIC -o ~/gpu-sec-lab/inject.so ~/gpu-sec-lab/inject.c
LD_PRELOAD=~/gpu-sec-lab/inject.so /bin/true       # proof file appears
```

**The gotcha worth remembering (cwd inheritance).** The constructor runs *inside
the target process* and inherits **the caller's** current working directory — not
the directory where you built `inject.so`. A **relative** `fopen` path therefore
lands wherever the caller happened to be:
- testing by hand from `~/gpu-sec-lab`, a relative path looked fine;
- `verify.sh` running from another cwd wrote the file somewhere else → FAIL.

Fix: use an **absolute** path. Lesson: *injected code has no home of its own — it
borrows the victim process's context (cwd, privileges, environment).* Hold onto
that; it's the same reason the Phase 2 payload runs with the hook's privileges.

## Challenge B — OCI hooks run on the host

**Goal:** prove a hook declared in `config.json` runs on the **host as root**, by
having it write to a host path the container can't reach.

**The mechanism.** The OCI runtime spec lets you declare programs that `runc` runs
automatically around the container lifecycle. A `createRuntime` hook runs on the
host, before the container's own process, as the user running `runc` (root here).

**Placement — the bug that ate an afternoon.** `hooks` is a **top-level** key —
a sibling of `process` / `root` / `mounts` / `linux` — **not** a child of `linux`.
`linux` is for kernel-specific config (namespaces, cgroups, masked paths); `hooks`
is lifecycle. Nested in the wrong place the JSON still *parses*, but `runc` reads
`hooks` only at the top level and silently ignores it → the hook never runs.

Diagnose placement (don't trust `jq .` alone — it only checks validity):
```bash
jq 'keys'  ~/gpu-sec-bundle/config.json     # must list "hooks"
jq '.hooks' ~/gpu-sec-bundle/config.json     # must be your object, not null
```
Move it up safely:
```bash
jq '.hooks = .linux.hooks | del(.linux.hooks)' config.json > config.tmp && mv config.tmp config.json
```

Top-level shape:
```json
"hooks": {
  "createRuntime": [
    { "path": "/home/lucavaudano.guest/gpu-sec-lab/hook.sh",
      "args": ["/home/lucavaudano.guest/gpu-sec-lab/hook.sh"] }
  ]
}
```

**The payoff.** Running the bundle produced `hook_proof.txt` **without touching
`hook.sh`**, containing:
```
oci-hook-ran-on-host
UID: 0            ← host root  (vs UID: 501 when I ran the script myself)
Hostname: lima-gpu-sec
```
That `UID: 0` is the entire lesson: the hook runs **as root on the host**, outside
the container's namespaces. A file landing in `~/gpu-sec-lab` (outside the
container `rootfs/`) *proves* it — the container's own process physically cannot
write there.

**Other gotchas hit:**
- `.guest` home — the real home is `/home/lucavaudano.guest`, not
  `/home/lucavaudano`; wrong in the hook `path` *and* inside `hook.sh` broke it
  twice.
- **root's environment** — inside `hook.sh`, `~` expands to `/root` when root runs
  it, not to your home. Use absolute paths in the hook. (Same "borrowed context"
  lesson as A: the hook runs in *root's* world, not yours.)
- hook script must be `chmod +x` and its `path` absolute; missing comma between
  `path` and `args` is the classic "runc doesn't like it."

## Running verify from anywhere

`verify.sh` anchors `NOTES.md` to its own directory, so you can run it by absolute
path from any cwd:
```bash
/Users/lucavaudano/myproject/GPU_Sec/01-boundaries/verify.sh
```

## Challenge C

An attacker can edit the LD_PRELOAD environment variable; because the attacker controls the image's filesystem (and its env), he can place evil.so there and set LD_PRELOAD, the host's dynamic linker loads evil.so and runs its constructor before main, so the attacker's code executes as root. The OCI hook runs on the host, as root, outside the container's namespaces. The hook inherits LD_PRELOAD from the attacker-controlled container config. That's the boundary crossing — an attacker's value flows into a host-root process. A host-root process trusted attacker-controlled input (the inherited LD_PRELOAD pointing at an attacker-supplied library), and that trust is the vulnerability.
Ultimately the attacker is able to run code as root on the host.
