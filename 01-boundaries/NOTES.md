# Phase 1 — My notes (copy to NOTES.md and fill in)

> Copy this file to `NOTES.md` (`cp NOTES.template.md NOTES.md`) and answer in
> your own words. Gate C of verify.sh checks NOTES.md exists and substantively
> covers the fusion. This is the raw material for the blog.

## A — LD_PRELOAD injection

- What mechanism did I use to make my code run inside `/bin/true`? (name it) Constructor 
- *When* does that code run, relative to the program's `main()`? Before main()
- Why does this work on almost any dynamically-linked program? Because I'm hooking the dynamic linker itself, not the program. It works because it rides the loader that every dynamically-linked program depends on; fails on static binaries.

## B — OCI hooks run on the host

- Which `hooks` lifecycle stage did I use, and where in `config.json`? The stage is createRuntime — it runs on the host after the container's namespaces are created but before the container's own process starts.
- What did the hook record for `id -u` and `hostname`? What does that tell me
  about the privilege and namespace the hook runs in? "root" privilege: yes — UID: 0 = host root. But you skipped the namespace half, and it's the subtle one. What hostname did it print? lima-gpu-sec — the host's hostname. Your config.json sets the container's hostname to "runc". So the hook saw lima-gpu-sec, not runc → the hook is not inside the container's UTS namespace. Together: the hook runs as root, in the host's namespaces — fully outside the container.
- Why does a file appearing in `~/gpu-sec-lab` *prove* the hook ran on the host
  and not in the container? The reason is mount-namespace isolation: the container's root filesystem is the busybox rootfs/. Inside the container, /home/lucavaudano.guest/... does not exist — the container literally cannot see the host's filesystem. So a file appearing at that host path could only have been written by a process running outside the container's mount namespace — i.e. on the host. The hook is that process. (This is the same reason the token file couldn't have been faked by the container's echo.)
- What made runc initially refuse my hook (if anything), and how did I fix it? 

1. First it wouldn't parse — bad JSON (missing comma, and wrong .guest paths). Fixed by correcting paths and validating with jq ..
2. Then it parsed but the hook never ran — because you'd placed hooks inside linux, and runc only reads hooks at the top level, so it silently ignored it (jq '.hooks' returned null). Fixed by moving it up: jq '.hooks = .linux.hooks | del(.linux.hooks)'.
3. Also: the hook script had to be chmod +x with an absolute path.

## C — The fusion (the important one)

In 3–6 sentences: **why is an OCI hook that inherits the container's environment
variables (like `LD_PRELOAD`) a container escape?** Connect A and B explicitly —
where does the attacker-controlled `.so` come from, whose process loads it, and
with what privilege? This is, in essence, CVE-2025-23266 (NVIDIAScape).

An attacker can edit the LD_PRELOAD environment variable; because the attacker controls the image's filesystem (and its env), he can place evil.so there and set LD_PRELOAD, the host's dynamic linker loads evil.so and runs its constructor before main, so the attacker's code executes as root. The OCI hook runs on the host, as root, outside the container's namespaces. The hook inherits LD_PRELOAD from the attacker-controlled container config. That's the boundary crossing — an attacker's value flows into a host-root process. A host-root process trusted attacker-controlled input (the inherited LD_PRELOAD pointing at an attacker-supplied library), and that trust is the vulnerability.
Ultimately the attacker is able to run code as root on the host.

## D — The boundary pattern (from the IOMMU worksheet)

One or two sentences: how is "is the IOMMU/MIG/SR-IOV boundary real?" the *same
shape* of question as "can a container escape to the host?" — just at a different
layer.
