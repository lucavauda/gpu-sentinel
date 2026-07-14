#!/usr/bin/env python3
"""
Phase 5 — scoring harness. Scores YOUR predictions the way a SOC would care about,
on an imbalanced problem: PR-AUC (average precision), plus precision/recall at your
chosen operating point. Accuracy is deliberately ignored — predicting "never a
miner" scores 98.5% accuracy and catches nothing.

You provide predictions.csv with columns:
    id     — matching test.csv
    score  — your model's miner probability/score in [0,1]
    pred   — (optional) your 0/1 decision at your chosen threshold

The harness compares your PR-AUC to a NAIVE baseline: "alert on high GPU util"
(using gpu_util_mean as the score). Beating it means you used more than the obvious
feature. Exit code 0 iff you beat the baseline.
"""
import sys
import pandas as pd
from sklearn.metrics import average_precision_score, precision_score, recall_score, f1_score, confusion_matrix

def main():
    try:
        test = pd.read_csv("test.csv")
        pred = pd.read_csv("predictions.csv")
    except FileNotFoundError as e:
        print(f"missing file: {e.filename} — run generate_data.py and produce predictions.csv")
        sys.exit(2)

    df = test.merge(pred, on="id", how="inner")
    if len(df) != len(test):
        print(f"predictions cover {len(df)}/{len(test)} test rows — need a score for every id")
        sys.exit(2)
    if "score" not in df:
        print("predictions.csv needs a 'score' column (miner probability in [0,1])")
        sys.exit(2)

    y = df["is_cryptominer"].values
    ap_model = average_precision_score(y, df["score"].values)
    ap_baseline = average_precision_score(y, df["gpu_util_mean"].values)   # "high GPU% = miner"

    print("=== Phase 5 evaluation (imbalanced: %.2f%% positive) ===" % (100 * y.mean()))
    print(f"PR-AUC  your model : {ap_model:.4f}")
    print(f"PR-AUC  naive baseline (gpu_util_mean): {ap_baseline:.4f}")

    if "pred" in df:
        p = precision_score(y, df["pred"], zero_division=0)
        r = recall_score(y, df["pred"], zero_division=0)
        f = f1_score(y, df["pred"], zero_division=0)
        tn, fp, fn, tp = confusion_matrix(y, df["pred"]).ravel()
        print(f"\nAt your operating point: precision={p:.3f} recall={r:.3f} f1={f:.3f}")
        print(f"  TP={tp}  FP={fp}  FN={fn}  TN={tn}")
        alerts = tp + fp
        print(f"  analyst sees {alerts} alerts; {tp} real, {fp} false ({(fp/alerts if alerts else 0):.1%} noise)")
    else:
        print("\n(no 'pred' column — add one to report precision/recall at your threshold)")

    beat = ap_model > ap_baseline + 1e-6
    print(f"\n{'BEAT' if beat else 'DID NOT BEAT'} the naive baseline on PR-AUC.")
    sys.exit(0 if beat else 1)


if __name__ == "__main__":
    main()
