#!/usr/bin/env python3
"""
Phase 5 — synthetic GPU-node telemetry generator.

Emits per-minute telemetry windows for a fleet of GPU nodes, labelled
is_cryptominer (a RARE positive class). The difficulty is baked in on purpose so
this is a REAL detection problem, not a toy:

  - legit TRAINING jobs also peg GPU util + power (high VRAM, bursty, chatty);
  - legit INFERENCE serving looks like a miner on the obvious axes — high util,
    LOW VRAM — but differs on steadiness (bursty) and network fan-out (many
    clients), so it's a genuine confuser;
  - the cryptominer is high-util, LOW-VRAM, VERY STEADY, few destinations;
  - distributions OVERLAP, and a few percent of labels are noisy.

So no single feature separates the classes, no threshold is perfect, and there is
a real precision/recall trade-off to reason about. Deterministic (seeded).
You do NOT edit this — it's the sensor. See FEATURES.md for the columns.
"""
import numpy as np
import pandas as pd

RNG = np.random.default_rng(1337)
POS_RATE = 0.015          # ~1.5% cryptominer windows
LABEL_NOISE_POS = 0.06    # 6% of miners mislabelled benign (caps achievable recall)
LABEL_NOISE_NEG = 0.004   # 0.4% of benign mislabelled miner (caps achievable precision)
N_TRAIN, N_TEST = 24000, 8000


def _c01(x):
    return np.clip(x, 0.0, 1.0)


def gen(n, rng):
    r = rng.random(n)
    is_miner = r < POS_RATE
    rest = ~is_miner
    r2 = rng.random(n)
    is_training = rest & (r2 < 0.32)
    is_inference = rest & (r2 >= 0.32) & (r2 < 0.55)     # the low-VRAM confuser
    idle = rest & (r2 >= 0.55)

    util = np.empty(n); ustd = np.empty(n); mem = np.empty(n); power = np.empty(n)
    temp = np.empty(n); net = np.empty(n); dsts = np.empty(n); ent = np.empty(n)

    def fill(m, u, us, me, po, te, ne, ds, en):
        k = m.sum()
        util[m]  = _c01(rng.normal(*u, k)) * 100
        ustd[m]  = rng.normal(*us, k).clip(0.3)
        mem[m]   = _c01(rng.normal(*me, k))
        power[m] = rng.normal(*po, k).clip(40)
        temp[m]  = rng.normal(*te, k)
        net[m]   = rng.gamma(ne[0], ne[1], k)
        dsts[m]  = rng.poisson(ds, k)
        ent[m]   = rng.normal(*en, k).clip(0)

    # idle/light (easy negatives)
    fill(idle,        (0.12, 0.09), (6, 3),  (0.12, 0.08), (75, 25), (42, 6),  (2, 45),  6,  (3.2, 0.5))
    # training: HIGH mem, bursty, chatty (overlaps miner on util only)
    fill(is_training, (0.82, 0.16), (16, 6), (0.55, 0.22), (320, 45),(70, 7),  (3, 1500),22, (3.6, 0.5))
    # inference: LOW mem like a miner, but BURSTY + MANY clients (the confuser)
    fill(is_inference,(0.80, 0.15), (13, 5), (0.20, 0.12), (250, 50),(66, 7),  (3, 900), 30, (3.4, 0.5))
    # miner: HIGH util, LOW mem, VERY STEADY, FEW destinations
    fill(is_miner,    (0.90, 0.09), (5, 3),  (0.20, 0.13), (310, 45),(72, 6),  (2.5, 130),3,  (2.8, 0.6))

    hour = rng.integers(0, 24, n)
    off = (hour < 6) | (hour >= 22)
    flip = is_miner & ~off & (rng.random(n) < 0.4)       # weak off-hours skew
    hour[flip] = rng.choice(np.r_[0:6, 22:24], flip.sum())

    label = is_miner.copy()
    # label noise — irreducible error, so no model/threshold is perfect
    label[is_miner   & (rng.random(n) < LABEL_NOISE_POS)] = False
    label[~is_miner  & (rng.random(n) < LABEL_NOISE_NEG)] = True

    df = pd.DataFrame({
        "gpu_util_mean": util.round(2),
        "gpu_util_std": ustd.round(2),
        "gpu_mem_used_frac": mem.round(3),
        "power_draw_w": power.round(1),
        "temp_c": temp.round(1),
        "net_out_kb": net.round(1),
        "distinct_dsts": dsts.astype(int),
        "proc_name_entropy": ent.round(3),
        "hour_of_day": hour.astype(int),
        "is_cryptominer": label.astype(int),
    })
    return df.sample(frac=1, random_state=int(rng.integers(1 << 30))).reset_index(drop=True)


def main():
    train = gen(N_TRAIN, RNG)
    test = gen(N_TEST, RNG)
    test.insert(0, "id", range(len(test)))
    train.to_csv("train.csv", index=False)
    test.to_csv("test.csv", index=False)
    print(f"train.csv: {len(train)} rows, {train.is_cryptominer.mean():.3%} positive")
    print(f"test.csv : {len(test)} rows, {test.is_cryptominer.mean():.3%} positive")
    print("Classes overlap on purpose — no single feature or threshold is perfect.")


if __name__ == "__main__":
    main()
