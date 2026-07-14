# Phase 0 — Build the lab

**Learning objective:** understand the real GPU-node stack by standing it up, and
get intimate with the OCI runtime layer where the whole project lives. By the end
you'll launch a container *without Docker* — straight from a raw OCI bundle via
`runc` — because Phase 2's attack is all about what happens at that layer.

Read [`stack-diagram.md`](stack-diagram.md) first. It shows exactly which box
you're attacking and defending.

---

## What I gave you

- `lima-gpu-sec.yaml` — a Lima VM definition with Docker, runc, crun, auditd, and
  build tools. Recent kernel so Falco's eBPF probe works in Phase 3.
- `stack-diagram.md` — the GPU-node stack with the acronyms placed on it.
- `verify.sh` — the acceptance test. Green = Phase 0 done.

## What YOU build (the struggle)

1. **Stand up the VM.**
   ```
   brew install lima
   limactl start --name=gpu-sec ./lima-gpu-sec.yaml
   limactl shell gpu-sec
   ```
   If `docker` needs sudo on first boot, run `newgrp docker` or log out/in.

2. **Launch a container from a raw OCI bundle.** This is the real exercise —
   *not* `docker run`. You must produce, at `00-lab/bundle/`:
   - `bundle/rootfs/` — a root filesystem.
   - `bundle/config.json` — the OCI runtime spec.

   …such that `sudo runc run <id>` from inside `00-lab/` **prints the token
   `gpu-sec-phase0-ok`**.

   Figure out *how* — that's the point. Some things worth discovering on your own:
   how to get a rootfs out of a container image without running it; what
   `runc spec` generates for you; which field in `config.json` controls what
   command the container runs; why `terminal: true` will fight with a script.

3. **Run the test.**
   ```
   cd ~/myproject/GPU_Sec/00-lab
   ./verify.sh
   ```

## Definition of done

`verify.sh` prints `PHASE 0 COMPLETE ✅`. That means the toolchain is present,
Docker runs a container, **and** your hand-built OCI bundle runs under `runc` and
prints the token.

## Hint tiers (ask me for these by number)

- **Tier 1 (nudge):** you don't need to build a rootfs by hand — a well-known
  Docker subcommand hands you a container's filesystem as a tarball.
- **Tier 2 (concept + where to look):** `man runc`, and `runc spec` generates a
  starter `config.json`; look at `process.args`, `process.terminal`, and `root.path`.
- **Tier 3 (analogous worked example):** I'll walk you through building a bundle
  that prints a *different* token from a *busybox* rootfs, and you adapt it.

## Why this matters for later phases

In Phase 2 you'll attack the exact layer you just learned: an OCI **hook** defined
in `config.json` that runs on the host before your container starts. You can't
reason about hijacking a hook until you've written a `config.json` by hand. That's
why Phase 0 ends here and not at "docker works."
