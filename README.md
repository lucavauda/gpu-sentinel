# gpu-sentinel: reproducing a GPU-cloud container escape with no GPU

The other day a question stuck in my head: what does security actually look like
in the context of GPUs?

My workflow for questions like this has changed. A few years ago I'd have spent an
evening watching a YouTube video and reading blog posts; today I can ask a language model and get a genuinely good answer back. So I asked. And the answer really struck, in one sentence: *the overwhelming majority of real GPU / AI-infrastructure security work is the software orchestration layer — containers, runtimes, drivers, and the detections on top.*

That was the useful part. I skipped the exotic "GPU security themes", such as MIG cache
side-channels, firmware reverse engineering, DMA exploits. They represent surely an interesting set of attacks but they are in the hands of more capable people. What I really want to focus is infra security (or even more specifically, Linux security). And the crown-jewel GPU-cloud vulnerability of the last year, **NVIDIAScape (CVE-2025-23266, CVSS 9.0)**, is a three-line Dockerfile that abuses
`LD_PRELOAD` and an over-trusting OCI (Open Container Initiative) hook. 

So I set myself a concrete goal: **reproduce the NVIDIAScape *class* of container escape from first principles with no GPU, entirely inside a VM on my own laptop, and then catch it two different ways.** This is the writeup of what I built, what broke along the way, and what I learned.

One sentence is the whole project, and it's worth stating up front as a promise the
rest of the piece will pay off:

> A host-privileged process trusted attacker-controlled input, an inherited
> `LD_PRELOAD` pointing at an attacker-supplied library, so the attacker's code
> ran as root on the host. That sentence is CVE-2025-23266.

The whole project is open source on GitHub: https://github.com/<your-username>/gpu-sentinel

## How I built it with a coding agent

I built this project with a coding agent (Claude Code). It is my third personal project with it, and I wanted to see how far this way of working could go. 
The rule I set for myself was simple: **the agent writes the specs, the diagrams, and the tests; I write the exploit, the detection rules, and the artifact.** So the agent never handed me the answer to the thing I was there to learn. When I got stuck I could ask for a hint, in small steps, but never the full solution.

In practice, every phase worked the same way. Starting from the original plan, the agent built a scaffold: a subfolder with everything I needed to begin. A `README.md` describing the task, a `verify.sh` script that tests my work for correctness, and, once I was done, a `SOLUTION.md` where it wrote up what I had built. The goals was to run `verify.sh` and becoming green.

It was not always smooth. Sometimes the scaffold, or the test harness itself, had subtle bugs. Noticing them, and then deciding whether to fix them by hand or hand them back to the agent, was part of the job. Honestly, that back-and-forth is the skill I think matters most now: not writing every single line yourself, but being able to work *with* these agents while staying in control of what they produce.

The agent was a scaffolder and a test harness. The whole project is a defensive, educational reproduction of a public CVE class, run inside my own lab against targets I built.

## Attack diagram

Before any of it, one diagram, because it tells you exactly which boundary the
whole project is about.

```
┌─────────────────────────────────────────┐
│  Application  (PyTorch / your training) │   ← tenant
├─────────────────────────────────────────┤
│  CUDA runtime + libraries               │
├─────────────────────────────────────────┤
│  Container image (what the tenant ships)│  ▓ attacker-controlled
├═════════════════════════════════════════┤
│  Container runtime: containerd / CRI    │  ▓
│  OCI runtime: runc / crun               │  ▓  ← OCI LIFECYCLE HOOKS run HERE,
│  NVIDIA Container Toolkit / CDI hooks   │  ▓    on the HOST, with HOST privilege
├═════════════════════════════════════════┤     ← this boundary is the whole game
│  NVIDIA kernel driver + kernel modules  │
│  Linux kernel  (namespaces, cgroups,    │
│                 capabilities, IOMMU)    │
├─────────────────────────────────────────┤
│  Hypervisor / bare metal                │   ← provider
├─────────────────────────────────────────┤
│  Physical GPU (PCIe, NVLink, MIG, DMA)  │
└─────────────────────────────────────────┘
```

A few terms that recur throughout, since not all of them were obvious to me
either when I started:

> - **OCI (Open Container Initiative)** — the open standard for what a container
>   image and its runtime config look like, so different tools interoperate.
> - **OCI bundle** — the on-disk form of a container: a `rootfs/` directory (its
>   filesystem) plus a `config.json` describing how to run it.
> - **`runc`** — the low-level program that reads that bundle and actually creates
>   the container. Docker, containerd, and Kubernetes all ultimately call it (or a
>   sibling like `crun`).
> - **OCI hook** — a program declared in `config.json` that the runtime runs
>   automatically around container start. Crucially it runs on the *host*, as
>   *root*, outside the container. This is the boundary the whole attack turns on.
> - **`LD_PRELOAD`** — a Linux environment variable that tells the dynamic linker
>   to load a shared library of your choosing into a program before it starts,
>   letting your code run inside a process you don't own.
> - **namespaces / cgroups / capabilities** — the kernel features that *are*
>   container isolation: separate views of filesystem, processes, and network
>   (namespaces), resource limits (cgroups), and slices of root's power
>   (capabilities).

The GPU-specific acronyms along the bottom (PCIe, DMA/IOMMU, MIG, SR-IOV) are the
*hardware* isolation boundaries. I studied their threat models, but they need real
hardware to be studied, so they stay out of scope here.

When a tenant "rents an H100," they touch the top box. The provider owns almost everything below it. The project lives in the middle because the **container image is attacker-controlled**, and an OCI hook that *runs on the host* while *trusting values from that image* collapses the tenant↔host boundary. Everything below follows from that one fact.

The attack fuses two ordinary Linux mechanisms. It is worth naming them now, because the whole of Part One is about building each one:

1. **`LD_PRELOAD` injection:** making the dynamic linker run *my* code inside a program I did not write.
2. **OCI hooks that run on the host:** a program declared in the container config that the runtime runs on the host, as root, outside the container.

Neither is a bug on its own. The escape is what happens when they meet: an attacker-controlled `LD_PRELOAD` reaches a host-side hook, so the attacker's code runs as root on the host. Phase 1 builds each mechanism by hand; Phase 2 fuses them.

The article has two parts. In the first I put on the attacker's hat and build the escape. In the second I swap it for the defender's and catch what I just did, once with runtime detection rules, once with machine learning.

---

# Part One — Red Team

## Phase 0 — Build the lab

I'm on macOS, and the entire toolchain I needed — `runc`, Falco's eBPF probe, `auditd` — is Linux-only. So the first move was a Lima VM running Ubuntu 24.04 on a recent kernel (6.8), recent enough that Falco's modern-eBPF driver would work later without compiling a kernel module.

The exercise of Phase 0 was to launch a container **without Docker at all**, straight from a raw OCI bundle via `runc`, because that's the exact layer the attack targets. And doing that teaches you the thing every abstraction hides: a container is not magic. 

An OCI bundle is a directory with exactly two things:
- `rootfs/` — the container's root filesystem.
- `config.json` — the **OCI runtime spec**: what to run, as whom, with which
  namespaces / capabilities / mounts, and — critically for later — **hooks**.

Getting a `rootfs` without running anything is a nice trick in itself: create a container but never start it, export its flattened filesystem, unpack it as root.

```bash
docker create --name temp busybox
docker export temp | sudo tar -xf - -C "$BUNDLE/rootfs"
docker rm temp
```
A couple of details make that work. `docker export` gives you the flattened
filesystem (what a `rootfs` needs), not the layered image tarball you'd get from
`docker save`. The `sudo` matters too: a root filesystem is full of root-owned
files, and an unprivileged extract just dies with permission errors. Then
`runc spec` writes a starter `config.json`, and I change two fields: the command to
run, and `process.terminal` to `false` (the default `true` makes runc allocate a
PTY, which fights a non-interactive test).

So how do I know the phase is actually done? With a small test. The agent's
`verify.sh` checks three things: that the tools are installed, that Docker can run a
normal container, and (the real point) that my hand-built bundle runs under `runc`
and prints a secret token, `gpu-sec-phase0-ok`. If that exact token comes back, my
bundle really did run straight from `runc`, with no Docker involved. 

One lesson from this phase is the kind you only get by hitting it. My repo lives on
a macOS-backed virtiofs mount, so I can edit files from the Mac and run them from
inside the VM. But that shared mount *cannot correctly host a Linux root filesystem*, and the extract simply breaks on it. The bundle had to live on the VM's own disk instead. So the code stays on the shared mount, and the Linux rootfs lives on native disk. That split was the most important practical lesson of Phase 0.

By the end, `config.json`, the file where OCI *hooks* are declared, was something I had written by hand. 

## Phase 1 — Boundaries
I named the two mechanisms in the intro. Phase 1 is where I build each one by hand,
on its own. Seeing them work separately is what makes their fusion in Phase 2 feel
obvious instead of magic.

**Primitive one: `LD_PRELOAD` runs your code inside a process you didn't write.**
The goal was a shared library that, when preloaded into `/bin/true` (a program
that does nothing and exits) writes a token to a file. If the token appears, it
can *only* be because my code ran, because `/bin/true` calls nothing.

The mechanism is a **constructor**. `LD_PRELOAD` has two powers. One is *interposition*: define a function with the same name as one the target calls (say `puts`). The other is a function marked `__attribute__((constructor))`, which the compiler places in the library's `.init_array`, which the dynamic linker runs **at load time, before `main()`, unconditionally.** That's what fires inside a program that does nothing.

```c
__attribute__((constructor))
void go(void) {
    FILE *f = fopen("/home/.../gpu-sec-lab/preload_proof.txt", "w");
    if (f) { fputs("ld-preload-fired\n", f); fclose(f); }
}
```

The lesson here is that the constructor runs *inside the target process* and inherits **the caller's** working directory, not the directory where I built the `.so`. 

A relative `fopen` path looked fine when I tested from the build directory and failed the moment the test harness ran from somewhere else. Absolute paths fixed it, and the principle is:
**injected code has no home of its own, it borrows the victim process's context: its cwd, its privileges, its environment.** This part is really important.

**Primitive two: OCI hooks run on the host, as root, outside the container.** An OCI bundle can declare programs that `runc` runs automatically around the container
lifecycle. I added a `createRuntime` hook that wrote its `id -u` and `hostname` to
a *host* path, one outside the container's `rootfs` that the container cannot
reach. It printed:

```
UID: 0            ← host root  (vs UID 501 when I ran the script myself)
Hostname: lima-gpu-sec   ← the host's name, not the container's "runc"
```
Here's the hook for context in the config.json:
```json
"hooks": {
  "createRuntime": [
    { "path": "/home/.../gpu-sec-lab/hook.sh",
      "args": ["/home/.../gpu-sec-lab/hook.sh"] }
  ]
}
```

Both halves of that output are the point. `UID 0` proves it runs as root. The
hostname (note that this is the *host's* name, not the container's configured `runc`) proves it
runs *outside* the container's UTS namespace. The hook is a root process living in
the host's world, and a file appearing on a host path the container can't see is
proof enough.

What took a bit of time to fix was that `hooks` is a **top-level** key in `config.json` (see how it looks like above), a sibling of `process` and `root` and **not** a child of `linux`. Nest it under
`linux` and the JSON still *parses cleanly*, but runc only reads `hooks` at the top level, so it silently ignores it and the hook never runs.

Learning how to use `jq ` was really useful, for this particular task (moving it up safely): 
```bash
jq '.hooks = .linux.hooks | del(.linux.hooks)' config.json > config.tmp && mv config.tmp config.json
```

Having built those two primitives by hand was the necessary prerequisite for building the attack.

## Phase 2 — The Attack

This is Phase 1's lesson turned into working code, under a threat model that makes
it real: **I control only the container image, its filesystem and its environment variables. Nothing else.** Not the runtime, not the hook, not the host. The "cloud vendor" side is fixed infrastructure I'm handed: a host-only secret at `/opt/gpu-sec/host-only/flag.txt` (`root:600`, invisible to the container), and a vulnerable vendor hook. 

The agent created a file called `vuln-hook.sh`, a stand-in for the real `nvidia-cdi-hook`. It is wired into the runtime as an OCI *createRuntime* hook, so runc runs it on the host, as root, before the tenant's container starts. Its job is (pretend) to prepare the GPU for the tenant. This is where the coding agent really pays off: it builds the infrastructure while I focus on the valuable part, the
attack itself.

I'm only allowed to read that hook, not change it, and that is what makes the
scenario realistic: a real attacker can't patch the vendor's code either. Here's
the part that matters:

```bash
if [ -f "$bundle/config.json" ]; then
  while IFS= read -r kv; do
    [ -n "$kv" ] && export "$kv"          # <-- the trust
  done < <(jq -r '.process.env[]?' "$bundle/config.json")   # <-- the source
fi
exec /bin/true                            # <-- the trigger
```

The comment in the hook frames it as being "helpful": it sets up its environment
the same way the tenant asked for theirs, "so the toolchain is consistent." That
helpfulness is the vulnerability, and it decomposes into three parts:

- **The source:** `jq -r '.process.env[]?'` reads the container's `process.env`. I
  own this because `process.env` is part of the container spec that the tenant
  ships. As the tenant, I write the image and its config, so I decide every
  environment variable inside it. It is my input, and the hook reads it directly, no
  questions asked.
- **The trust:** `export "$kv"` pulls those attacker-controlled values straight into
  a host-root process, with no validation at all.
- **The trigger:** `exec /bin/true` is an ordinary dynamically-linked program. The
  moment it runs, the host's `ld.so` acts on the now-poisoned `LD_PRELOAD`.

A simple test helped me pin down which line is really the bug, and it was useful
during the validation work too. Remove the `export` loop and the `exec` becomes
harmless. Keep the loop but change `exec /bin/true` to `exit 0`, and again nothing
happens (though any later program that loads a library would still set it off). So
the bug is the `export` loop that trusts my environment; the `exec` is only where
it goes off. The real nvidia hook has the exact same split.

Here is the whole escape in one picture, read from top to bottom. I control only
the top box, the container image. Everything below it runs on the host, as root,
doing my work for me:

```
  ┌──────────────────────────────────────────────┐
  │ container image            (I control this)  │
  │   • evil.so   = my payload                   │
  │   • process.env:  LD_PRELOAD = …/evil.so      │
  └──────────────────────┬───────────────────────┘
                         │  runc starts the container and
                         │  runs the vendor hook first
                         ▼
  ┌──────────────────────────────────────────────┐
  │ vuln-hook.sh    (host hook, runs as root)    │
  │   export $(container's process.env)  ← trust │
  │   exec /bin/true                     ← fires │
  └──────────────────────┬───────────────────────┘
                         │  the host's ld.so sees the inherited
                         │  LD_PRELOAD and loads evil.so
                         ▼
  ┌──────────────────────────────────────────────┐
  │ evil.so constructor      (still host root)   │
  │   reads  /opt/gpu-sec/host-only/flag.txt     │
  │   writes uid=0 + flag  → escape-proof.txt    │
  └──────────────────────┬───────────────────────┘
                         ▼
     ESCAPE: my code ran as root on the host and read
     a secret the container could never see.
```

The exploit is two things a tenant controls. First, the payload (the Phase 1 constructor), now doing something that proves host compromise:

```c
__attribute__((constructor))
void init(void) {
    char buf[256] = "";
    FILE *f = fopen("/opt/gpu-sec/host-only/flag.txt", "r");   // read the secret — we're root
    if (f) { fgets(buf, sizeof(buf), f); fclose(f); }
    FILE *proof = fopen("/opt/gpu-sec/escape-proof.txt", "w"); // write proof of who we ran as
    if (proof) { fprintf(proof, "uid=%d flag=%s", geteuid(), buf); fclose(proof); }
}
```

Second, the delivery, one line that sets `LD_PRELOAD` in the container's env, pointing at that `.so`. That's the entire attack. The vendor hook does the rest, unwittingly.

```
$ bash check_escape.sh
proof: uid=0 flag=FLAG-48c89a9cb00c7968
[ok] payload executed as ROOT on the host (uid=0)
[ok] payload exfiltrated the host-only secret the container cannot see — ESCAPE CONFIRMED
```

`uid=0` on the host, plus the host-only flag the container was never supposed to
see, in a file I wrote. Full container escape, achieved by shipping an image. No kernel bug, no GPU.

(A small confession, because it taught me something: I'm not a C person, and my
first `evil.c` opened the secret with `"w"` instead of `"r"`. I would have *erased
the very file I was trying to steal.* Guarding every `fopen` with `if (f)`, so a
wrong path fails softly and still leaves a proof file to debug, is a habit worth
keeping. In the end, the idea is the hard part; getting the exact C right is
something an agent can help with.)

---

# Part Two — Blue team

Here's the part I'm most interested in. Phases 0–2 made me the attacker; from here I'm the defender,
and I've got a working exploit. Now it's time to detect it.

## Phase 3 — Telemetry

> **Falco** is a runtime security tool that watches Linux **syscalls** (the calls
> a program makes into the kernel to open files, run programs, and so on) and
> raises an alert when they match a rule you write. **eBPF** is the modern kernel
> technology that lets it observe those syscalls safely, without loading a custom
> kernel module.

Before writing a single detection rule, you have to prove the sensor can see the
attack at all. I stood up **Falco** with its modern-eBPF driver (driverless, no
kernel module to compile, exactly what you want in a nested VM) and pointed a
deliberately broad "telemetry tap" at the box: log every `execve` and every open of
a `.so` or a lab path. Then I replayed the Phase 2 escape and watched my own attack
come back as a syscall stream:

| Attack step | Event the sensor saw |
|-------------|----------------------|
| runc runs the hook | `execve` of `vuln-hook.sh`, parent `runc` |
| hook execs the helper | `execve` of `/bin/true`, parent `vuln-hook.sh` |
| `ld.so` loads the payload | `openat` of `evil.so` from a rootfs path |
| payload reads the secret | `openat` of `/opt/gpu-sec/host-only/flag.txt` |
| payload writes proof | write of `/opt/gpu-sec/escape-proof.txt` |

Seeing my own escape from the defender's seat is the whole point of the swap, but
the real insight was a distinction that drives everything after it:
**cause vs. artifact vs. effect.** The *effect* (a write to a host path during a
container launch) is easy to spot but brittle: change the payload's target and it
evades. The *cause* (a runtime hook running with an attacker-controlled
`LD_PRELOAD`) generalizes across every payload variant. And crucially, Falco's eBPF
sensor exposes process *environment* via `proc.env`, which means I can detect the
cause, not just the effect. That single capability shapes the entire rule pack.


## Phase 4 — Detection 

Anyone can write a rule that fires on the attack. The job is a rule that fires on the attack **and stays silent on everything normal** — so the harness enforces both: red→green on the replayed escape, and a benign baseline that must produce **zero** alerts. That baseline is what turns rule-writing into
craft, because a lazy rule fails it instantly.

I wrote three rules, layered by the cause/artifact/effect distinction from Phase 3.

**Rule 1 — the cause (lowest false positive, survives payload changes):**
```
evt.type=execve and evt.dir=< and
proc.env contains "LD_PRELOAD=" and
proc.aname in (runc)
```
A process in the runtime-hook chain whose environment carries `LD_PRELOAD`. This
catches the *mechanism*, and it doesn't care what the payload does.

**Rule 2 — the artifact (catches `evil.so`):**
```
evt.type in (open,openat,openat2) and evt.dir=< and
fd.name endswith ".so" and proc.aname in (runc) and
not fd.name startswith "/lib" and not fd.name startswith "/usr/lib"
```
The `/lib` and `/usr/lib` exclusions are fundamental. Without them the rule
fires on every normal libc load, and the benign baseline (which runs `ls` and
`cat`) catches you immediately.

**Rule 3 — the effect (backstop):**
```
evt.type in (open,openat,openat2) and evt.dir=< and
proc.aname in (runc) and fd.name startswith "/opt/gpu-sec/host-only"
```
Scoped tightly to `host-only`, not a broad `/opt/gpu-sec`, so the benign bundle's
own rootfs under `/opt/gpu-sec/…` can't trip it.

The design principles that make this deployable rather than noisy:

- **Cause > effect.** Rule 1 catches the *why* and generalizes; Rules 2–3 catch
  *this* payload's artifacts. Good backstops, brittle alone. A mature pack layers
  all three.
- **Context kills false positives.** "`.so` loaded" is pure noise — every process
  loads libraries constantly. "`.so` loaded by a runc-descended process from a
  non-standard path" is signal. The anchors (`proc.aname in (runc)`, path scoping,
  standard-dir excludes) are the entire difference.
- **A detection isn't done when it fires; it's done when it *only* fires.** The
  benign baseline forced me to scope Rule 2's paths and Rule 3's prefix.

Some gotchas worth recording, because they're the difference between a rule that
loads and one that lies: membership on the ancestor set is `proc.aname in (runc)`,
not `contains`; `evt.dir=<` (syscall exit) is mandatory, or the rule also evaluates
on syscall *enter* where `proc.env` and `fd.name` aren't populated yet;
`container.rootfs` isn't a real Falco field and referencing it fails rule load.

> **Sigma** is a vendor-neutral format for writing detection rules once and translating them to
> whichever SIEM an org runs, so a rule isn't locked to one tool like Falco.

The scaffolding agent suggested I write a **Sigma** equivalent of Rule 1. This part
is extremely interesting, because it forces you to face a real limitation.
Specifically, many `process_creation` log sources, such as Sysmon-for-Linux and
auditd, **do not capture a process's environment.** So the `LD_PRELOAD` detection
that's trivial for Falco via eBPF may be *impossible* in a plain SIEM. When that
happens, the portable rule has to fall back to the process *relationship* (a
runtime/hook parent spawning a dynamically-linked child) instead of the env var
itself. Knowing which detections your telemetry can and can't support is exactly
where the security analyst work shines.

Here is the rule I wrote:

```sigma
detection:
  selection:
    Image|endswith:
      - '/ldconfig'
      - '/nvidia-modprobe'
      - '/nvidia-smi'
      - '/nvidia-container-cli'
    EnvironmentVariables|contains: 'LD_PRELOAD='
  condition: selection
```

It is simple: it fires when one of the known GPU or runtime helper binaries (like
`nvidia-smi` or `nvidia-container-cli`) is launched with `LD_PRELOAD` sitting in its
environment. Same idea as Falco's Rule 1, just written for a SIEM. It works well
where the log source does capture environment variables, and it quietly misses
everything where it doesn't, which is the limitation above in one concrete example.

All of these artifacts, the Falco rules, the Sigma rule, the attack, and the test
harness, live in the repo if you want to read or run them.

## Phase 5 — Cryptominer as a class-imbalanced problem detection

Over the last few months I became fascinated by class-imbalanced problems. How do you find if someone is cheating at chess? How do you spot a malicious actor in a network? How do you tell if a cryptominer is quietly using a rented GPU, on your compute and your bill?
Class-imbalance here means recognizing a handful of miner windows hidden among thousands of legitimate, GPU-hungry jobs. That is a really cool class of problems, and in my other blog posts I explored some of these themes. This one, though, I did with the help of the coding agent.

> A few metrics to have in hand. **Precision** answers "of everything I alerted on,
> how much was really a miner?" **Recall** answers "of every real miner, how much
> did I catch?" The two trade off against each other as you move the alert
> threshold. **PR-AUC** (area under the precision-recall curve, also called average
> precision) rolls that whole trade-off into one number, and unlike plain accuracy
> it isn't fooled when the positive class is rare.

The first trap is the metric. **Accuracy is useless here**: a model that predicts
"never a miner" scores ~98.5% accuracy and catches exactly zero miners. So the
harness scores **PR-AUC** (average precision), the right summary when positives are
rare, plus precision/recall at the chosen threshold.

The second trap is the naive detector: "alert on high GPU utilization." It scores a
PR-AUC of about **0.04**, buried, because *legitimate training jobs also peg the GPU.* Beating that baseline is the entire exercise, and it means finding what separates a miner from a heavy-but-legitimate workload. There are two confusers:

- **Training:** high utilization, but holds a big model in **high VRAM**, and runs
  **bursty**.
- **Inference:** high utilization and **low VRAM** *just like a miner*, but
  **bursty** and talking to **many** clients.

No single feature separates all three. The miner is high-util, low-VRAM, *very
steady*, and talks to *few* destinations. So the signal is a combination, such as:
`util_per_mem` (pegged GPU but little VRAM), steadiness (low `gpu_util_std`), and
`distinct_dsts` (a pool or two, not a fleet of clients). A RandomForest classifier with
`class_weight="balanced"` over those engineered features reaches **PR-AUC ≈ 0.73**,
well past 0.04. Beating the baseline *is* the proof that I used more than the obvious column. Still not an expert on ML though, just to be clear.

One detective story from this phase, because it's a lesson I'll reuse. My first run
scored a *perfect* 1.0 at every threshold. My instinct was "overfitting", but it
wasn't: the held-out test was also perfect, meaning the model genuinely generalized. The real cause was **synthetic data that was too easy**. The classes barely overlapped. The tell that distinguishes the two is simple and worth memorizing: overfitting means train ≫ test; an easy dataset means train ≈ test, both high. The fix was to inject more class overlap, add the inference confuser, and add label noise, so that no single feature or threshold is ever perfect.

Which brings the real value of this particular phase: **the operating point is a business decision.**
PR-AUC ranks the model; the *threshold* is where you trade missed miners against false pages. On a held-out validation split (not the test set, since tuning the threshold on test is leakage), 0.70 gives precision 0.95 / recall 0.71, and 0.55 gives precision 0.95 / recall 0.77. **0.55 strictly dominates 0.70**: nine more miners caught for the *same* six false alerts. Below ~0.5, precision collapses without catching more. So I ship 0.55, and I can defend it in one breath: a missed
miner is stolen compute burning on the victim's bill for hours or days; a false alert is an unnecessary page that ruins an analyst's day.

Limits for this context: the data is synthetic, the recall ceiling is ~0.72 because label noise and miner/inference overlap make some windows genuinely indistinguishable, and a perfect detector on data like this would be a red flag, not a goal. Before trusting this on a real fleet I'd run it in shadow (alert-only) mode against real telemetry, build labels from confirmed incidents, measure the
false-positive rate on known-benign nodes, and retrain and re-pick the threshold on real data.

---

# What a defender should actually do

The root cause is a privileged hook that trusts tenant-controlled input, so every fix lives on that trust boundary. The main one is simple: **don't inherit the container's environment into a host-root hook.** That is the whole vulnerability. If the hook really needs some variables, allowlist them by name instead of importing all of `process.env`, and never let `LD_PRELOAD`, `LD_LIBRARY_PATH`, or similar linker variables through. On top of that, **drop privileges** in the hook wherever the work doesn't truly need root.

On the detection side, ship the layered pack: the cause-level Falco rule as the main signal, the artifact and effect rules as backstops, and, if you're stuck with a SIEM that can't see process environments, the process-relationship rule, with the blind spot written down so nobody assumes coverage they don't have. The upstream fix for the real CVE is the same shape: stop the hook from honoring attacker-supplied linker variables.

# What I actually learned

I learned a tonne during this little project, but two things are worth sharing, one technical and one about method.

The technical one is the thesis I started with, now earned rather than assumed: **"GPU security" is mostly Linux security.** The most valuable GPU-cloud vulnerability of the year is a container image, an environment variable, and a host-side hook that trusted it. Namespaces, the dynamic linker, and the OCI runtime, not firmware or silicon.

The method one is about learning with a coding agent. The rule I set (the agent scaffolds and writes the tests, I build the exploit and the detections, a green test is the only "done") kept it from doing the learning for me. Every "gotcha-moment" in this writeup was something I actually hit and had to understand: the rootfs that broke on the shared mount, the hooks key that runc silently ignored, the C that would have erased the secret, the model that scored a suspicious perfect 1.0. None of it was handed to me. That is the difference between having a project done *for* you and using a tool to learn faster than you could alone.

This repo was a really fun artifact to build. It showed me, first-hand, what these models are capable of: genuinely useful for building the harness, and good guidance for putting a project like this together. It won't be the last, I think.

Thanks for reading! Feel free to ping me if you have any question or see any errors.