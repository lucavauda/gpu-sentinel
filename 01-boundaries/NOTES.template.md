# Phase 1 — My notes (copy to NOTES.md and fill in)

> Copy this file to `NOTES.md` (`cp NOTES.template.md NOTES.md`) and answer in
> your own words. Gate C of verify.sh checks NOTES.md exists and substantively
> covers the fusion. This is the raw material for the blog.

## A — LD_PRELOAD injection

- What mechanism did I use to make my code run inside `/bin/true`? (name it)
- *When* does that code run, relative to the program's `main()`?
- Why does this work on almost any dynamically-linked program?

## B — OCI hooks run on the host

- Which `hooks` lifecycle stage did I use, and where in `config.json`?
- What did the hook record for `id -u` and `hostname`? What does that tell me
  about the privilege and namespace the hook runs in?
- Why does a file appearing in `~/gpu-sec-lab` *prove* the hook ran on the host
  and not in the container?
- What made runc initially refuse my hook (if anything), and how did I fix it?

## C — The fusion (the important one)

In 3–6 sentences: **why is an OCI hook that inherits the container's environment
variables (like `LD_PRELOAD`) a container escape?** Connect A and B explicitly —
where does the attacker-controlled `.so` come from, whose process loads it, and
with what privilege? This is, in essence, CVE-2025-23266 (NVIDIAScape).

## D — The boundary pattern (from the IOMMU worksheet)

One or two sentences: how is "is the IOMMU/MIG/SR-IOV boundary real?" the *same
shape* of question as "can a container escape to the host?" — just at a different
layer.
