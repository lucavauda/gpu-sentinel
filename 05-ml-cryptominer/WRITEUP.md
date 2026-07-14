# Phase 5 — Detector writeup (copy to WRITEUP.md and fill in)

> Copy this to `WRITEUP.md` (`cp WRITEUP.template.md WRITEUP.md`) and answer each
> section in your own words. `verify_ml.sh` needs WRITEUP.md to exist, be >500
> chars, and discuss precision/recall. This is the plain-English analysis that
> shows you can reason about a detector — no code required.

## 1. The problem, and why accuracy is the wrong metric
- What are we detecting, and how rare is it (~1.5% positive)? The models is set to detect a cryptominer on a rented GPU. 
- Why would "accuracy" mislead here? (What accuracy do you get by predicting
  "never a miner", and what does it catch?) Accuracy in a heavy class-imbalanced dataset is not a great metric. 
- Which metric did we use instead, and why is it right for rare positives? PR-AUC (average precision), plus precision/recall at your threshold.

## 2. What separates a miner (the features)
- Why isn't "high GPU utilisation" enough? (Who else pegs the GPU?) I detect cryptominer activity on rented GPU nodes — a rare event (~1.5% of windows). Accuracy is misleading on such imbalance: a model that predicts "never a miner" scores ~98.5% accuracy while catching zero miners. So we score PR-AUC (average precision), the right summary for rare positives, and read precision/recall at the operating point.
- What actually distinguishes a miner from a legit **training** job? From an
  **inference-serving** job (the low-VRAM confuser)?
  - miners run **steady** (low `gpu_util_std`); training is **bursty**;
  - miners use **little VRAM** (`gpu_mem_used_frac` low) while pegging the GPU;
  training holds a big model in VRAM;
  - miners talk to **few** outbound destinations (a pool or two); training is chatty.
- Which features/combinations did you use, and what's the intuition behind each? "High GPU utilisation" is useless here because legit training and inference jobs also peg the GPU. The separators are combinations: util_per_mem (pegged GPU but low VRAM — miners barely use memory, training holds a big model), steadiness (low gpu_util_std — miners flat-line, training and inference are bursty), and distinct_dsts (miners talk to one or two pools; inference serves many clients). The inference class is the real confuser — it looks like a miner on util+VRAM, so you need steadiness and fan-out to separate them.

## 3. The operating point you'd ship
- Which threshold did you choose, and what precision/recall does it give? I compared thresholds: 0.70 gives precision 0.95 / recall 0.71 (107 caught, 6 false, 44 missed); 0.55 gives precision 0.95 / recall 0.77 (116 caught, 6 false, 35 missed). I shipped 0.55 because it catches 9 more miners for the same 6 false alerts — strictly better. Going below ~0.5 only piles on false positives without catching more. Cost: a missed miner = stolen compute burning on the victim's bill for hours or days; a false alert = an unnecessary page that erodes analyst trust. Here false positives are already low (6, 95% precision), and the cost of missing theft is ongoing — so I lean toward recall, which points at 0.55.
- Frame the **cost**: a missed miner = ______ ; a false alert = ______ . Which is
  worse in this context, and how did that shape your choice? A missed miner = stolen compute running for hours/days on the victim's bill; a false alert = an analyst paged to check a legit job, and at volume, alert fatigue. Here false positives are cheap (6 total, 95% precision) while a miss means ongoing theft — so the miss is the costlier error, which is why I favoured recall and shipped 0.55.

## 4. How you chose it honestly
- Why pick the threshold on the validation set rather than the test set? I chose the threshold on a held-out validation split, not the test set, tuning on test would leak information and inflate the final numbers, so test stays untouched for an honest estimate. 
- (Bonus) What's the difference between overfitting and an easy dataset, and how
  would you tell them apart from train vs. test scores? 
  Overfitting = the model memorizes the training data → scores great on train, poorly on test. (Train > test.)
  Easy dataset = the classes barely overlap, so the model does genuinely well on both → train ≈ test, both high. Not "low quality" — if anything, too clean.

## 5. Limitations
- What's synthetic/unrealistic about this data? (Label noise, clean features,
  no concept drift, miners that co-locate with real workloads, etc.) The data is synthetic: cleanly-generated features, fixed distributions, injected label noise, no concept drift, and miners modelled as their own tidy class — real miners co-locate with legit jobs and actively evade. The detector's recall ceilings around ~0.75 because label noise and miner/inference overlap make some windows genuinely indistinguishable. Before trusting this on a real fleet I'd run it in shadow mode (alert-only) against real telemetry, validate flags against confirmed incidents, measure the false-positive rate on known-benign nodes, and retrain on real data.

- What's your detector's recall ceiling, and why can't it catch everything? Recall ceilings around 0.75 because of irreducible error: ~6% of miner windows are mislabeled (unlearnable), and some miners overlap the inference class in feature space — indistinguishable on the available signals. No threshold recovers them; dropping the threshold only adds false positives.
- How would you validate this on a real GPU fleet before trusting it? Because it's trained on synthetic data, I'd validate before trusting it: run in shadow (alert-only) mode against real telemetry, investigate every flag to build real labels, measure the false-positive rate on known-benign nodes, retrain and re-pick the threshold on real data, and only then enable active alerting
