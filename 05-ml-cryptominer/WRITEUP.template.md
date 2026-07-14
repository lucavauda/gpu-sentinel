# Phase 5 — Detector writeup (copy to WRITEUP.md and fill in)

> Copy this to `WRITEUP.md` (`cp WRITEUP.template.md WRITEUP.md`) and answer each
> section in your own words. `verify_ml.sh` needs WRITEUP.md to exist, be >500
> chars, and discuss precision/recall. This is the plain-English analysis that
> shows you can reason about a detector — no code required.

## 1. The problem, and why accuracy is the wrong metric
- What are we detecting, and how rare is it (~1.5% positive)?
- Why would "accuracy" mislead here? (What accuracy do you get by predicting
  "never a miner", and what does it catch?)
- Which metric did we use instead, and why is it right for rare positives?

## 2. What separates a miner (the features)
- Why isn't "high GPU utilisation" enough? (Who else pegs the GPU?)
- What actually distinguishes a miner from a legit **training** job? From an
  **inference-serving** job (the low-VRAM confuser)?
- Which features/combinations did you use, and what's the intuition behind each?

## 3. The operating point you'd ship
- Which threshold did you choose, and what precision/recall does it give?
- Why that one? Reference the trade-off: what does moving the threshold up or down
  do to false pages vs. missed miners? (You found 0.55 beats 0.70 — say why.)
- Frame the **cost**: a missed miner = ______ ; a false alert = ______ . Which is
  worse in this context, and how did that shape your choice?

## 4. How you chose it honestly
- Why pick the threshold on the validation set rather than the test set?
- (Bonus) What's the difference between overfitting and an easy dataset, and how
  would you tell them apart from train vs. test scores?

## 5. Limitations
- What's synthetic/unrealistic about this data? (Label noise, clean features,
  no concept drift, miners that co-locate with real workloads, etc.)
- What's your detector's recall ceiling, and why can't it catch everything?
- How would you validate this on a real GPU fleet before trusting it?
