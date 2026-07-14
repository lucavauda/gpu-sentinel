# Worksheet — map the attack to observable telemetry

This is the detection-engineer's first move: before you can *detect* something, you
have to know what it *looks like* to a sensor. For each step of your Phase 2
escape, name the observable kernel/syscall event(s) a runtime sensor (Falco / EDR /
auditd) would see. Fill the right column, then answer the questions.

(Run `bash capture.sh` first — the real captured events are your evidence.)

| # | Attack step | Observable event(s) a sensor sees |
|---|-------------|-----------------------------------|
| 1 | runc invokes the `createRuntime` hook | `execve` of `vuln-hook.sh` (a bash proc) whose **parent is `runc`** — _fill in details_ |
| 2 | hook exports the container's env (incl. `LD_PRELOAD`) | _____ (hint: hard to see as an event — but the *result* shows up in step 3's process env) |
| 3 | hook `exec`s `/bin/true` with the poisoned env | _____ |
| 4 | host `ld.so` loads `evil.so` | _____ (hint: a `.so` opened from an unusual path) |
| 5 | `evil.so` reads the host-only secret | _____ |
| 6 | `evil.so` writes `escape-proof.txt` | _____ |

## Questions (answer below each)

1. Which of these events is the **strongest, lowest-false-positive** signal of
   *this specific attack*? Why that one?

2. Which would be **noisy** on a real GPU node, i.e. a bad detection on its own?
   (Think about how often `.so` files get loaded normally.)

3. Can a sensor see the **`LD_PRELOAD` value itself**, not just that a process
   exec'd? (Hint: Falco exposes process environment via `proc.env` — what would a
   rule keying on "a runtime hook whose env contains `LD_PRELOAD`" catch?)

4. What's the difference between detecting the **cause** (a hook running with an
   attacker `LD_PRELOAD`) vs the **effect** (a write to a host path from a
   container launch)? Which generalises better to variants of the attack?

These answers become your Phase 4 rules: each strong signal → one detection.
