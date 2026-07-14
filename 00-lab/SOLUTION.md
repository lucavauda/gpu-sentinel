# Phase 0 — Solution notes (for the blog)

What I actually did to stand up the lab and launch a container from a raw OCI
bundle — the operations, and the *why* behind each one.

## Goal

Launch a container **without Docker** — straight from an OCI bundle via `runc` —
so it prints the token `gpu-sec-phase0-ok`. This forces you to learn the layer
where Phase 2's attack (NVIDIAScape-class OCI-hook escape) actually happens.

## The environment

- **Host:** macOS. **Lab:** an Ubuntu 24.04 Linux VM via **Lima**
  (`limactl start --name=gpu-sec ./lima-gpu-sec.yaml`), because the whole
  toolchain (runc, Falco eBPF, auditd, IOMMU) is Linux-only.
- Kernel `6.8.x` — recent enough for Falco's modern-eBPF probe in Phase 3.

## The key mental model: two locations, on purpose

| What | Where | Why there |
|------|-------|-----------|
| **Repo** (code, `verify.sh`, phase docs) | `/Users/lucavaudano/myproject/GPU_Sec` — the macOS-backed Lima **mount**, same path on Mac and VM | edit from macOS, run from VM |
| **OCI bundle** (`rootfs/` + `config.json`) | `~/gpu-sec-bundle` — the VM's **native disk** | the mount is virtiofs and can't faithfully host a Linux **root filesystem** |

This split is the single most important operational lesson of Phase 0.

## What an OCI bundle is

A directory with exactly two things:
- `rootfs/` — the container's root filesystem.
- `config.json` — the **OCI runtime spec**: what to run, as whom, with which
  namespaces / capabilities / mounts, and — critically for later — **hooks**.

`runc run -b <bundle> <id>` is all it takes. Docker/containerd are just fancy
front-ends that assemble this bundle for you.

## The build, step by step

```bash
# 1. Bundle on the VM's NATIVE fs (not the mount)
BUNDLE=~/gpu-sec-bundle
rm -rf "$BUNDLE"; mkdir -p "$BUNDLE/rootfs"

# 2. Get a rootfs WITHOUT running anything: create a container, export its
#    flattened filesystem as a tar stream, unpack it. Extract as root because a
#    root filesystem is full of root-owned files.
docker create --name temp-container busybox
docker export temp-container | sudo tar -xf - -C "$BUNDLE/rootfs"
docker rm temp-container

# 3. Generate a starter spec, then change two fields:
cd "$BUNDLE"
runc spec
#   process.args     -> the command that prints the token
#   process.terminal -> false  (no TTY: our test captures stdout non-interactively)
jq '.process.args = ["/bin/echo","gpu-sec-phase0-ok"] | .process.terminal = false' \
   config.json > config.tmp && mv config.tmp config.json

# 4. Run it straight from the bundle
sudo runc run test1            # -> gpu-sec-phase0-ok
sudo runc delete --force test1
```

## Why each non-obvious choice

- **`docker export` (not `save`)** → gives the *flattened filesystem*, not layered
  image tarballs. Exactly what a `rootfs/` needs.
- **`sudo tar`** → a rootfs contains root-owned files + symlink/hardlink entries;
  an unprivileged extract fails with `Cannot open: Permission denied`.
- **Native fs, not the mount** → the macOS-backed virtiofs mount can't represent
  full Linux fs semantics, so a rootfs extract breaks there.
- **`process.terminal = false`** → `runc spec` defaults it to `true`, which makes
  runc allocate a PTY; the acceptance test has no TTY, so `true` would error.
- **`runc run -b <bundle>`** → without `-b`, runc looks for `config.json` in the
  current directory.

## Verifying

```bash
cd /Users/lucavaudano/myproject/GPU_Sec/00-lab
BUNDLE=~/gpu-sec-bundle ./verify.sh     # -> PHASE 0 COMPLETE
```

## Gotchas I hit (good blog material — these are the real lessons)

1. **`docker` needs the group, and group changes don't apply to an open shell.**
   `sudo usermod -aG docker $USER` then `newgrp docker` (or restart the VM).
2. **Path nesting** — running `mkdir -p 00-lab/...` *while inside* `00-lab`
   created `00-lab/00-lab`. Watch your cwd.
3. **Rootfs on the shared mount fails** — moved the bundle to native disk.
4. **`sudo` inside a script with `2>/dev/null` looks like a hang** — its password
   prompt is hidden. On a passwordless (NOPASSWD) lab VM the real fix is to make
   sudo passwordless and just call `sudo <cmd>` directly.
5. **`sudo -v` prompts even under NOPASSWD** — the `-v` flag forces credential
   validation and asks for a password regardless of NOPASSWD rules, so it *hangs*
   on an account with no password. Plain `sudo <cmd>` doesn't. (I hit this by
   adding `sudo -v` as a "warm-up" — it was the bug, not the fix.)
6. **Broken multi-line paste** — pasting a whole command block into the terminal
   corrupted input (`<d`, `<UNDLE` fragments) and even fed garbage into a prompt.
   Run scripts as a file (`bash verify.sh`), not by pasting their contents.
7. **`runc run` hangs inside a script but not by hand** — when its stdout is a
   pipe (e.g. `OUT="$(sudo runc run …)"`), runc's stdio forwarding waits on the
   inherited terminal stdin and never returns EOF, so the command substitution
   hangs forever. The same command run interactively (stdout = TTY) is fine. Fix:
   redirect stdin with `</dev/null` (and wrap in `timeout` so a hang fails fast
   instead of blocking). This is a great "works on my terminal, hangs in CI" lesson.

## What this sets up

`config.json` is where OCI **hooks** are declared — programs that run *on the host*
around container start. Phase 2 hijacks exactly that mechanism. You can't reason
about hijacking a hook until you've written a `config.json` by hand, which you now
have.
