# Phase 1 — Feel the isolation boundaries

**Learning objective:** internalize *why* container isolation breaks, by building
the two primitives NVIDIAScape combines:

1. **`LD_PRELOAD` injection** — make the dynamic linker run *your* code inside a
   process you didn't write.
2. **OCI hooks run on the host** — prove that a program declared in `config.json`
   executes on the **host**, as **root**, *outside* the container's namespaces.

Phase 2 fuses these: a container-controlled `LD_PRELOAD` reaches a host-side OCI
hook → your library loads into a host-root process → escape. You can't feel that
until you've built each half yourself. That's this phase.

You'll also map the scary acronyms (PCIe, DMA/IOMMU, MIG, SR-IOV) onto one
question — *"is this boundary real?"* — in [`iommu-worksheet.md`](iommu-worksheet.md).

---

## What I gave you

- `verify.sh` — the acceptance test (three gates below).
- `iommu-worksheet.md` — a guided DMA/IOMMU inspection + acronym worksheet.
- `NOTES.template.md` — copy to `NOTES.md` and fill in; the write-up *is* the
  deliverable that proves you understood it.

## Setup

Work in the VM. Put your build artifacts in a native-fs lab dir (same reason as
Phase 0 — off the shared mount):

```bash
mkdir -p ~/gpu-sec-lab
```

## Challenge A — `LD_PRELOAD` injection

Build a shared library so that preloading it into **any** dynamically-linked
program makes *your* code run inside that process — with no cooperation from the
program.

- **Target proof:** produce `~/gpu-sec-lab/inject.so` such that
  `LD_PRELOAD=~/gpu-sec-lab/inject.so /bin/true` writes the token
  `ld-preload-fired` into `~/gpu-sec-lab/preload_proof.txt`.
- `/bin/true` does nothing and exits — so if your token appears, it can *only* be
  because your library ran. That's the whole point of the primitive.

Figure out: how does the dynamic linker let a library run code *before* the host
program's `main()`? (That mechanism is the entire trick behind NVIDIAScape's
payload.)

## Challenge B — OCI hooks execute on the host

Prove that a hook declared in an OCI bundle runs on the **host as root**, not in
the container.

- **Target proof:** add a hook to your Phase 0 bundle (`~/gpu-sec-bundle/config.json`)
  that runs a script writing the token `oci-hook-ran-on-host` into
  `~/gpu-sec-lab/hook_proof.txt`.
- Why this proves it: `~/gpu-sec-lab` is a **host** path — it is *not* inside the
  container's `rootfs/`, so the container's own process (the `echo` from Phase 0)
  physically cannot create that file. If it appears, a host-side process did it.
- Make your hook script *also* record `id -u` and `hostname` into that file, and
  **read what it captured** — that's the lesson: the hook is uid 0 on the host.

Figure out: where in the OCI runtime spec do hooks live, which lifecycle stage
runs on the host, and what makes runc refuse to run your hook (a very common
gotcha — think permissions).

## Challenge C — Explain the fusion (the real deliverable)

Copy `NOTES.template.md` to `NOTES.md` and answer, in your own words, the
central question: *why is an OCI hook that inherits the container's environment
variables (like `LD_PRELOAD`) a container-escape?* Tie A and B together. This is
what you'll expand into the blog.

## Definition of done

`bash verify.sh` prints `PHASE 1 COMPLETE ✅`. It checks:
1. your `inject.so` fires via `LD_PRELOAD`,
2. your bundle's hook runs on the host,
3. `NOTES.md` exists and substantively explains the fusion.

## Hint tiers (ask by number)

**Challenge A**
- **A1 (nudge):** the linker runs specially-marked functions in a shared library
  *before* the host program's `main()`. You want to mark one of your functions
  that way.
- **A2 (concept + how):** GCC's `__attribute__((constructor))`; build with
  `gcc -shared -fPIC inject.c -o inject.so`. Your constructor opens the proof file
  and writes the token.
- **A3 (analogous worked example):** I'll show a constructor that writes to
  *stderr* for a *different* token; you adapt it to write the proof file.

**Challenge B**
- **B1 (nudge):** the OCI spec has a top-level `hooks` object; runc runs those
  programs on the host around container start.
- **B2 (concept + how):** look at `hooks.createRuntime` (or `prestart`); each
  entry is `{"path": "...", "args": [...]}` with an **absolute** path; patch
  `config.json` with `jq`; and remember the script must be `chmod +x`.
- **B3 (analogous worked example):** I'll show a `config.json` `hooks` snippet
  with a placeholder script that touches a file; you adapt the path and token.

## Why this matters for Phase 2

In Phase 2 you stop running A and B separately and make **one** malicious
container image whose `LD_PRELOAD` gets picked up by a (deliberately vulnerable)
host-side hook — the NVIDIAScape reproduction. Everything you build here is a
component of that.
