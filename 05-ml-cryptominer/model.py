#!/usr/bin/env python3
"""
Phase 5 — model SKELETON.

The plumbing is DONE. Run it as-is and it will train, score, and write
predictions.csv end-to-end (and it should already beat the naive baseline). Your
job is not to build this from scratch — it's to make the two DECISIONS marked
`TODO`, which are the actual class-imbalance craft:

  1. which FEATURES separate a miner from a legit training job, and
  2. where you set the alert THRESHOLD (the operating point you'd ship to a SOC).

Read every line so you can defend it in WRITEUP.md. Then improve the TODOs.
"""
import pandas as pd
from sklearn.ensemble import RandomForestClassifier
from sklearn.model_selection import train_test_split

train = pd.read_csv("train.csv")
test = pd.read_csv("test.csv")


def add_features(df):
    df = df.copy()
    # Example engineered feature: "GPU pegged, but barely using VRAM" — a miner
    # tell, because training jobs hold a big model in memory.
    df["util_per_mem"] = df["gpu_util_mean"] * (1 - df["gpu_mem_used_frac"])
    df["steadiness"] = df["gpu_util_mean"] * (df["gpu_util_std"] + 1)
    # TODO (decision 1): add 1–2 more features that separate miner vs training.
    #   Ideas from FEATURES.md — steadiness: gpu_util_mean / (gpu_util_std + 1);
    #   few destinations; an off-hours flag. The separation you find IS the model.
    return df


FEATURES = [
    "gpu_util_mean", "gpu_util_std", "gpu_mem_used_frac", "power_draw_w",
    "temp_c", "net_out_kb", "distinct_dsts", "proc_name_entropy", "hour_of_day",
    "util_per_mem", "steadiness"
    # TODO: append the names of any features you add in add_features().
]

tr, te = add_features(train), add_features(test)

# Split OFF a validation set so we judge the threshold on data the model did NOT
# train on. This is exactly the point you raised: a Random Forest scores ~1.0 on
# its own TRAINING data even when it hasn't truly generalised — so a threshold
# table built on training data lies. Judge it on held-out data instead.
X_tr, X_val, y_tr, y_val = train_test_split(
    tr[FEATURES], tr["is_cryptominer"],
    test_size=0.25, stratify=tr["is_cryptominer"], random_state=0,
)

# class_weight="balanced" makes the rare miner class "count more" during training
# — the simplest imbalance lever. (Optional: try SMOTE / undersampling instead.)
clf = RandomForestClassifier(
    n_estimators=200, class_weight="balanced", random_state=0, n_jobs=-1
)
clf.fit(X_tr, y_tr)

# score = the model's probability that a window is a miner (in [0, 1]).
score = clf.predict_proba(te[FEATURES])[:, 1]

# --- precision/recall trade-off, measured on the held-out VALIDATION set ---
val_score = clf.predict_proba(X_val)[:, 1]
yv = y_val.values
print("threshold  precision  recall   (higher threshold = fewer false pages, more misses)")
for t in [0.1, 0.2, 0.3, 0.5, 0.7, 0.9]:
    flagged = val_score >= t
    precision = yv[flagged].mean() if flagged.sum() else 0.0
    recall = yv[flagged].sum() / yv.sum()
    print(f"   {t:<4}     {precision:6.3f}    {recall:6.3f}")

# TODO (decision 2): pick the threshold you'd actually deploy, and justify it in
# WRITEUP.md — what's the cost of a MISSED miner vs. a false 3am page?
THRESHOLD = 0.55

pred = (score >= THRESHOLD).astype(int)
pd.DataFrame({"id": te["id"], "score": score, "pred": pred}).to_csv(
    "predictions.csv", index=False
)
print(f"\nwrote predictions.csv — flagged {int(pred.sum())} of {len(pred)} windows")
