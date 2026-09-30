"""
Run the Level 2 study.

    python scripts/run_level2.py              # full run (~2-4 min on a laptop)
    python scripts/run_level2.py --quick      # coarser grids, ~30 s
"""

from __future__ import annotations

import argparse
import sys
import time
from dataclasses import replace
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from cuas_l1 import ARCHITECTURE_CASES, Node  # noqa: E402
from cuas_l2 import DetectionModel, Level2Config, simulate  # noqa: E402
from cuas_l2 import experiments as ex, plots  # noqa: E402


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--quick", action="store_true")
    ap.add_argument("--out", type=Path, default=ROOT / "figures")
    args = ap.parse_args()
    q = args.quick
    n_big = 8_000 if q else 20_000
    n_grid = 1_000 if q else 3_000
    t0 = time.time()

    cfg = Level2Config()          # all defaults; see cuas_l2/models.py
    lines = []
    say = lambda s="": (print(s), lines.append(s))

    say("# Level 2 results")
    say()
    say("Baseline configuration (all provisional, see `cuas_l2/models.py`):")
    say(f"- Detection: {cfg.detection.kind}, Pd = {cfg.detection.pd_at_r_detect} at R_detect, "
        f"roll-off {cfg.detection.rolloff} × R_detect, Pd_max {cfg.detection.pd_max}")
    say(f"- Tracker: revisit {cfg.tracker.revisit_s} s, {cfg.tracker.m_of_n[0]}-of-{cfg.tracker.m_of_n[1]} confirmation, central fusion")
    say(f"- Latency: lognormal stages, median total ≈ {cfg.latency.median():.0f} s")
    say(f"- Availability: P(node up) {cfg.availability.p_node_up} × P(comms) {cfg.availability.p_comms_up} "
        f"= {cfg.availability.p_node_up*cfg.availability.p_comms_up:.3f}")
    say(f"- False tracks: {cfg.false_alerts.false_tracks_per_node_hour}/node/h; threat arrivals {cfg.false_alerts.threat_arrivals_per_hour}/h (for PPV)")
    say(f"- Threat: {cfg.threat.speed[0]:.0f} m/s head-on unless stated; requirement {cfg.t_required:.0f} s")
    say()

    # 1. Architecture cases, conservative and optimistic roll-off ------------
    say("## 1. Architecture cases under identical imperfections (head-on, 30 m/s)")
    say()
    say("| Case | R (km) | D (km) | P(meet) logistic | P(track) | p50 T_w (s) | mean R_track (km) | P(meet) Swerling-I | FA/h | PPV |")
    say("|---|---|---|---|---|---|---|---|---|---|")
    rows_log = ex.architecture_cases(cfg, n_big)
    rows_sw = ex.architecture_cases(replace(cfg, detection=DetectionModel(kind="swerling1")), n_big)
    for (c, r), (_, rs) in zip(rows_log, rows_sw):
        s = r.summary()
        say(f"| {c.name} | {c.r_detect/1000:.0f} | {c.d_forward/1000:.0f} | **{r.p_meet:.2f}** | {r.p_track:.2f} | "
            f"{s['T_warning p10/p50/p90 (s)'][1]:.0f} | {s['mean range at track (km)']:.1f} | {rs.p_meet:.2f} | "
            f"{r.false_alerts_per_hour:.1f} | {r.ppv:.2f} |")
    say()
    say(f"With a single node, P(track) is capped by availability "
        f"({cfg.availability.p_node_up*cfg.availability.p_comms_up:.3f}). The Level 1 "
        "equivalence of the three 9 km-depth architectures breaks once latency and "
        f"confirmation are charged: ~{cfg.latency.median():.0f} s of latency plus "
        f"{cfg.tracker.m_of_n[0]} looks to confirm costs "
        f"~{30*(cfg.latency.median()+cfg.tracker.m_of_n[0]*cfg.tracker.revisit_s):.0f} m of depth at 30 m/s, "
        "and the small forward nodes have no geometric margin to pay it. "
        "The Swerling-I column shows how much an optimistic long Pd tail hides this; "
        "the roll-off shape is a Level 3 deliverable.")
    say()
    plots.fig_warning_distributions(rows_log, args.out)

    # 2. P(meet) grid ---------------------------------------------------------
    say("## 2. P(meet) over range × placement")
    say()
    r_km = np.linspace(1, 5, 9 if q else 17)
    d_km = np.linspace(0, 10, 11 if q else 21)
    P = ex.pmeet_grid(cfg, r_km, d_km, n_grid)
    plots.fig_pmeet_grid(P, r_km, d_km, cfg, args.out)
    np.savetxt(ROOT / "docs" / "level2_pmeet_grid.csv",
               np.column_stack([np.repeat(r_km, len(d_km)), np.tile(d_km, len(r_km)), P.ravel()]),
               delimiter=",", header="r_detect_km,d_forward_km,p_meet", comments="")
    say("See `figures/fig6_pmeet_range_vs_placement.png`; raw grid in `docs/level2_pmeet_grid.csv`. "
        "The P = 0.8 contour sits to the right of the Level 1 ideal line by the placement "
        "penalty quantified in section 3, and nothing exceeds the availability ceiling of "
        f"{cfg.availability.p_node_up*cfg.availability.p_comms_up:.3f}.")
    say()

    # 3. Forward distance needed --------------------------------------------
    say("## 3. Forward placement needed to reach P(meet) = 0.9 (availability = 1)")
    say()
    curves = {}
    say("| Node R_detect | Level 1 ideal D | Level 2 D for P ≥ 0.9 | Extra placement |")
    say("|---|---|---|---|")
    for rk in (2.0, 3.0, 4.0):
        d, p, ds = ex.forward_distance_to_meet(cfg, rk * 1000, n_trials=2_000 if q else 6_000)
        curves[f"{rk:.0f} km node"] = (d, p, ds)
        ideal = 9.0 - rk
        say(f"| {rk:.0f} km | {ideal:.1f} km | {ds:.2f} km | +{ds-ideal:.2f} km |" if np.isfinite(ds)
            else f"| {rk:.0f} km | {ideal:.1f} km | not reached ≤ 12 km | — |")
    plots.fig_forward_distance(curves, args.out)
    say()
    say("The chain costs V_c × (latency + confirmation looks) ≈ "
        f"{30*(cfg.latency.median()+cfg.tracker.m_of_n[0]*cfg.tracker.revisit_s):.0f} m of depth at 30 m/s. "
        "Larger nodes pay part of it from their soft roll-off beyond R_detect (the tail is "
        "proportional to R_detect), which is why the extra placement shrinks with node "
        "range. Design rule: the Level 1 position is a floor; budget the chain on top of it "
        "in placement, not in radar range. Note the baseline 3 km node only reaches its "
        "score at all because of the tail beyond R_detect — with a hard edge "
        "(roll-off → 0, section 4) it fails outright. The tail shape is a Level 3 output.")
    say()

    # 4. Sensitivity -----------------------------------------------------------
    say("## 4. One-at-a-time sensitivity, 3 km node 6 km forward")
    say()
    node = Node(x=6000, r_detect=3000, sector_width=90)
    base = simulate([node], cfg, n_big).p_meet
    sens = ex.sensitivity(cfg, node, 4_000 if q else 10_000)
    plots.fig_sensitivity(sens, base, args.out)
    say(f"Baseline P(meet) = {base:.2f}.")
    say()
    for k, (x, p) in sens.items():
        say(f"- **{k}**: " + ", ".join(f"{xi} → {pi:.2f}" for xi, pi in zip(x, p)))
    say()

    # 5. Layouts under a corridor prior -----------------------------------------
    say("## 5. Node layouts, threat bearing uniform in ±30°")
    say()
    lay = ex.node_layouts(cfg, n_trials=n_big)
    plots.fig_layouts(lay, args.out)
    say("| Layout | P(meet) | P(track) | mean nodes up | FA/h | PPV |")
    say("|---|---|---|---|---|---|")
    for k, r in lay.items():
        say(f"| {k} | {r.p_meet:.2f} | {r.p_track:.2f} | {r.n_nodes_available.mean():.2f} | "
            f"{r.false_alerts_per_hour:.1f} | {r.ppv:.2f} |")
    say()
    say("Redundant co-location raises availability but not geometry; lateral offset "
        "raises geometry but each node still only covers its own ±~15° for full warning. "
        "The false-alert column is the price: every node added adds its own false-track "
        "rate, and PPV falls accordingly. This is the Level 2 form of the "
        "'more cheap nodes vs one better radar' trade, and it is where the false-alert "
        "rate per node (a Level 3 output) decides the answer.")
    say()

    # 6. Speed band --------------------------------------------------------------
    say("## 6. Closure-speed band 10-50 m/s, 3 km node 6 km forward")
    say()
    edges, p, rsp = ex.speed_band(cfg, node, n_big)
    plots.fig_speed_band(edges, p, args.out)
    say("| Speed bin (m/s) | " + " | ".join(f"{a:.0f}-{b:.0f}" for a, b in zip(edges[:-1], edges[1:])) + " |")
    say("|---|" + "---|" * (len(edges) - 1))
    say("| P(meet) | " + " | ".join(f"{v:.2f}" for v in p) + " |")
    say()
    say(f"Averaged over the band: P(meet) = {rsp.p_meet:.2f}. The requirement is met "
        "comfortably below ~25 m/s and essentially never above ~35 m/s with this geometry; "
        "the threat-speed assumption is therefore as decisive as any radar parameter and "
        "must be pinned down against a real CONOPS.")
    say()

    say(f"_Run time {time.time()-t0:.0f} s. Figures in `{args.out}`._")
    (ROOT / "docs" / "level2_results.md").write_text("\n".join(lines) + "\n")


if __name__ == "__main__":
    main()
