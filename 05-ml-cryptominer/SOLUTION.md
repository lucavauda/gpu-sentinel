# Phase 5 — Solution notes (cryptominer detection as class imbalance)

Detecting a cryptominer on a rented GPU node as a rare-event problem. The craft
here isn't the code — it's the metric choice, the feature reasoning, and the
operating-point decision. Blog material. (The SOC-facing operating-point *defense*
lives separately in `WRITEUP.md`.)

## The problem

Per-minute GPU-node telemetry, ~1.5% miner windows hidden among idle nodes, legit
**training** jobs, and legit **inference** serving. Rare positive class →
imbalance.

## Why accuracy is a trap

Predicting "never a miner" scores ~98.5% accuracy and catches zero miners. So the
harness ignores accuracy and scores **PR-AUC** (average precision) — the right
summary when positives are rare — plus precision/recall at the chosen threshold.

## The features (why "high GPU%" isn't enough)

The naive "alert on high GPU utilisation" detector scores **PR-AUC ≈ 0.04** — it's
buried, because training jobs *also* peg the GPU. Two confusers force you to use
more than one feature:
- **training** — high util, but **high VRAM**, bursty, chatty (many peers);
- **inference** — high util, **low VRAM** like a miner, but **bursty** and **many
  clients**.

The miner is high-util, **low-VRAM**, **very steady**, **few destinations**. So
the separating signal is a *combination*:
- `util_per_mem` = `gpu_util_mean * (1 - gpu_mem_used_frac)` — pegged GPU, little VRAM;
- steadiness (low `gpu_util_std`) — miners flat-line, inference is bursty;
- `distinct_dsts` — miners talk to a pool or two; inference serves many clients.

A RandomForest with `class_weight="balanced"` over these reaches **PR-AUC ≈ 0.73** —
well past the 0.04 baseline. Beating the baseline *is* the proof you used more than
the obvious feature.

## The insight that fixed the phase (mine)

First run scored a perfect 1.0 at every threshold. I flagged it as overfitting —
but it wasn't: the **held-out test** was also perfect, so the model *generalised*.
The real cause was **too-easy synthetic data** (classes barely overlapped). The
fix was more overlap + an inference confuser + label noise, so no single feature
or threshold is perfect.

The tell to distinguish the two, for the blog:
- **overfitting** → train score ≫ test score;
- **easy data** → train ≈ test, both high.

This also fixed the threshold table: it must be computed on a **held-out
validation split**, not on training data (where a RandomForest scores ~1.0 by
memorisation and the table *lies*).

## The operating point

On validation, precision/recall trade off with the threshold. On test:
- **0.70** → precision 0.95, recall 0.71 (107 caught, 6 false, 44 missed);
- **0.55** → precision 0.95, recall 0.77 (116 caught, 6 false, 35 missed).

**0.55 dominates 0.70** — 9 more miners caught for the *same* 6 false alerts. Below
~0.5, precision collapses (false positives pile up) without catching more. Shipped
threshold: **0.55**. (Chosen on validation, not by tuning on the test set.)

## Gotchas / lessons

- **Accuracy lies on imbalance** → use PR-AUC + precision/recall.
- **Don't judge a threshold on training data** → held-out validation.
- **Don't tune the threshold on the test set** → that's leakage; choose on val,
  report test once.
- **Label noise caps performance** → recall ceiling ~0.72; a perfect detector is a
  red flag, not a goal.

## What's the separate deliverable

`WRITEUP.md` — the plain-English SOC justification: metric choice, features,
threshold and its cost (missed miner = stolen compute; false page = eroded analyst
trust), and limitations. That argument, not the code, is the senior-level artifact.
