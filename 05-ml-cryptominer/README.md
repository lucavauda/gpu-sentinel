# Phase 5 — Cryptominer-on-GPU-node as class-imbalance detection

**Learning objective:** the phase that's unmistakably *yours*. Detecting a
cryptominer on a rented GPU node is a **rare-event / class-imbalance** problem — a
handful of miner windows hidden among thousands of legit (and GPU-hungry) training
jobs. You bring the imbalanced-ML craft; I bring the data and the SOC-realistic
scoring.

This needs **no GPU and no VM** — pure Python on synthetic telemetry. Run it
wherever you have Python + scikit-learn.

## What I gave you

- `generate_data.py` — the sensor. Emits `train.csv` / `test.csv` of per-minute
  GPU-node telemetry with a **~1.5% miner** class. The classes overlap on the
  obvious features on purpose (training jobs also peg the GPU).
- `FEATURES.md` — the columns, the trap, and your I/O contract.
- `evaluate.py` — scores you on **PR-AUC** (average precision) and precision/recall
  at your operating point — *not accuracy* — and compares you to the naive
  "high GPU% = miner" baseline.
- `verify_ml.sh` — the acceptance test.

## What YOU build

1. **`model.py`** — read `train.csv`, engineer features, train an
   **imbalance-aware** classifier, predict on `test.csv`, and write
   `predictions.csv` (`id, score[, pred]`). Your call on everything: feature
   engineering, resampling vs class weights vs threshold-moving, model family,
   and where to set the operating point.
2. **`WRITEUP.md`** — defend the operating point you'd actually ship to an on-call
   analyst: your precision/recall trade-off and *why*. (What's the cost of a
   missed miner vs. the cost of paging someone at 3am for a training job?)

## Run it

```bash
pip install -r requirements.txt          # numpy pandas scikit-learn
python3 generate_data.py                 # once — writes train.csv / test.csv
python3 model.py                         # yours — writes predictions.csv
bash verify_ml.sh
```

## Definition of done

`verify_ml.sh` prints `PHASE 5 COMPLETE ✅`:
- your model **beats the naive baseline on PR-AUC** (i.e. you used more than
  `gpu_util_mean`), and
- `WRITEUP.md` defends your precision/recall operating point for a SOC.

## Why the scoring is what it is (the craft)

- **Accuracy is a trap here.** "Never a miner" scores ~98.5% accuracy and catches
  nothing. `evaluate.py` ignores accuracy and uses **PR-AUC**, the right summary
  for rare positives.
- **The baseline is the lazy analyst.** "Alert on high GPU utilisation" is what an
  untrained detector does — and it's buried under training jobs. Beating it is the
  whole exercise: find what separates a miner from a heavy-but-legit workload.
- **The operating point is a business decision.** PR-AUC ranks your model; the
  *threshold* is where you trade missed miners (cost: stolen compute) against false
  pages (cost: analyst trust). That judgement, argued well in `WRITEUP.md`, is what
  a hiring manager reads.

## Hint tiers (ask by number)

- **M1:** explore first — plot/inspect miner vs training on `gpu_mem_used_frac` and
  `gpu_util_std`; the separation you find is your best engineered feature.
- **M2:** the standard imbalance levers — `class_weight="balanced"` (or
  `scale_pos_weight`), or resampling (SMOTE / undersampling), and pick the
  threshold from the precision-recall curve, not the default 0.5.
- **M3:** a concrete recipe (one model + one feature-engineering move + one
  threshold-selection method) that you then tune.

## Why Phase 6 is next

Phase 6 turns the whole repo — the escape, the telemetry, the Falco/Sigma pack,
and this rare-event detector — into the writeup. This is the artifact that shows
you can *both* find the attack and detect it two ways (rules + ML).
