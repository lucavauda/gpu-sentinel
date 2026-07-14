# Phase 5 — the data

Per-minute telemetry windows for a fleet of GPU nodes. Each row is one node-minute.
`generate_data.py` is your sensor; you don't edit it.

## Columns (train.csv / test.csv)

| Column | Meaning |
|--------|---------|
| `id` | row id (test.csv only) — align your predictions to this |
| `gpu_util_mean` | mean GPU utilisation % over the minute |
| `gpu_util_std` | within-window variability of utilisation |
| `gpu_mem_used_frac` | fraction of VRAM used |
| `power_draw_w` | mean power draw (W) |
| `temp_c` | mean temperature (°C) |
| `net_out_kb` | outbound traffic (KB) in the window |
| `distinct_dsts` | distinct outbound destinations |
| `proc_name_entropy` | entropy of the process-name distribution |
| `hour_of_day` | 0–23 |
| `is_cryptominer` | **label** (1 = miner). Rare (~1.5%). |

## The trap (why this is a real problem)

Legit **ML training** jobs *also* peg `gpu_util_mean` and `power_draw_w`. So a
detector that keys on "high GPU utilisation" fires constantly on training and is
useless. That naive detector is exactly the baseline `evaluate.py` scores you
against (`gpu_util_mean` as the miner score). **Beating it requires finding what
separates a miner from a training job** — think about combinations, not single
columns. A few starting intuitions (verify them in the data yourself):

- miners run **steady** (low `gpu_util_std`); training is **bursty**;
- miners use **little VRAM** (`gpu_mem_used_frac` low) while pegging the GPU;
  training holds a big model in VRAM;
- miners talk to **few** outbound destinations (a pool or two); training is chatty.

None of these is clean on its own — they overlap. That's the point: engineer
features (ratios, interactions) and let an imbalance-aware model combine them.

## Your deliverable

Write `model.py` that:
1. trains on `train.csv` (do **not** peek at the test label),
2. predicts on `test.csv`,
3. writes `predictions.csv` with columns `id, score[, pred]`
   (`score` = miner probability in [0,1]; optional `pred` = your 0/1 decision).

Then defend your choices in `WRITEUP.md`.
