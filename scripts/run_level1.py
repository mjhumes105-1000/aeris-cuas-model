"""
Run the full Level 1 study: reproduce the handoff table, generate figures,
and write a results summary.

    python scripts/run_level1.py            # figures -> figures/, summary -> docs/
    python scripts/run_level1.py --vc 40    # different closure speed
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from cuas_l1 import (ARCHITECTURE_CASES, BASELINE_REQ, SECTOR_WIDTHS,  # noqa: E402
                     V_C_BASELINE, Node, WarningRequirement, cost_per_warning_depth,
                     coverage_vs_bearing, first_detection_range, Threat,
                     warning_depth_required, warning_time_headon)
from cuas_l1 import plots  # noqa: E402


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--vc", type=float, default=V_C_BASELINE, help="closure speed m/s")
    ap.add_argument("--latency", type=float, default=BASELINE_REQ.t_latency)
    ap.add_argument("--buffer", type=float, default=BASELINE_REQ.r_action,
                    help="action buffer R_action in metres")
    ap.add_argument("--treq", type=float, default=BASELINE_REQ.t_required)
    ap.add_argument("--out", type=Path, default=ROOT / "figures")
    args = ap.parse_args()

    req = WarningRequirement(t_required=args.treq, t_latency=args.latency,
                             r_action=args.buffer)
    v_c = args.vc
    lines = []
    say = lambda s="": (print(s), lines.append(s))

    say(f"# Level 1 results  (V_c = {v_c:.0f} m/s, T_req = {req.t_required:.0f} s, "
        f"latency = {req.t_latency:.0f} s, buffer = {req.r_action:.0f} m)")
    say()
    depth = warning_depth_required(v_c, req.t_required, req.t_latency, req.r_action)
    say(f"Required total warning depth along the approach axis: **{depth/1000:.1f} km**")
    say()

    # --- Handoff architecture table ---------------------------------------
    say("## Architecture cases (head-on, ideal)")
    say()
    say("| Case | R_detect (km) | D_forward (km) | T_warning (s) | Meets? | PA proxy | PA per km depth |")
    say("|---|---|---|---|---|---|---|")
    for case in ARCHITECTURE_CASES:
        t = float(warning_time_headon(case.d_forward, case.r_detect, v_c,
                                      req.t_latency, req.r_action))
        node = case.node(sector_width=90)
        d = first_detection_range(Threat(speed=v_c, bearing=0.0), [node])
        pa = (case.r_detect / 3000.0) ** 4
        cpd = cost_per_warning_depth([node], d)
        say(f"| {case.name} | {case.r_detect/1000:.0f} | {case.d_forward/1000:.0f} | "
            f"{t:.0f} | {'yes' if t >= req.t_required else 'no'} | {pa:.2f} | {cpd:.3f} |")
    say()

    # --- Sector coverage ---------------------------------------------------
    say("## Sector coverage, one 3 km node 6 km forward")
    say()
    say("Warning time (s) by approach bearing relative to boresight. A forward node "
        "meets the 300 s requirement only on-axis: off-axis threats pass through "
        "the coverage disc closer to the defended point, so warning depth shrinks "
        "even before the sector edge is reached. The last column is the bearing at "
        "which the node stops seeing the threat at all.")
    say()
    probe = [0, 10, 20, 30, 45, 60]
    say("| Sector width | " + " | ".join(f"{b}°" for b in probe) + " | Loses track beyond |")
    say("|---|" + "---|" * len(probe) + "---|")
    bearings = np.arange(-90, 90.5, 0.5)
    for w in list(SECTOR_WIDTHS) + [360.0]:
        node = Node(x=6000.0, r_detect=3000.0, sector_width=w)
        res = coverage_vs_bearing([node], v_c, req, bearings)
        vals = []
        for b in probe:
            t = res.t_warning[np.argmin(np.abs(bearings - b))]
            vals.append(f"{t:.0f}" if np.isfinite(t) else "—")
        seen = np.isfinite(res.t_warning)
        edge = float(np.max(np.abs(bearings[seen]))) if seen.any() else 0.0
        say(f"| {w:.0f}° | " + " | ".join(vals) + f" | ±{edge:.1f}° |")
    say()
    say("Note the 360° row: with the node this far forward, going omnidirectional "
        "buys nothing beyond ±~27°, because past that bearing the threat's path "
        "misses the 3 km disc entirely. Sector width and placement are coupled.")
    say()

    # --- Two-node overlap example -----------------------------------------
    say("## Two 3 km nodes vs one, 6 km forward, 90° sectors")
    say()
    say("Bearing half-angle over which warning stays at or above a given fraction "
        "of the requirement.")
    say()
    single = [Node(x=6000, r_detect=3000, sector_width=90)]
    pair = [Node(x=6000 * np.cos(np.deg2rad(+20)), y=6000 * np.sin(np.deg2rad(+20)),
                 r_detect=3000, sector_width=90, boresight=+20),
            Node(x=6000 * np.cos(np.deg2rad(-20)), y=6000 * np.sin(np.deg2rad(-20)),
                 r_detect=3000, sector_width=90, boresight=-20)]
    say("| Layout | ≥300 s | ≥270 s | ≥240 s | ≥180 s | any detection |")
    say("|---|---|---|---|---|---|")
    for label, nodes in (("one node on axis", single), ("two nodes at ±20°", pair)):
        res = coverage_vs_bearing(nodes, v_c, req, bearings)
        cells = []
        for thr in (300, 270, 240, 180, 0):
            ok = res.t_warning >= thr - 1e-6 if thr > 0 else np.isfinite(res.t_warning)
            cells.append(f"±{float(np.max(np.abs(bearings[ok]))):.0f}°" if ok.any() else "—")
        say(f"| {label} | " + " | ".join(cells) + " |")
    say()

    # --- Figures -----------------------------------------------------------
    out = args.out
    plots.fig_range_vs_placement(v_c, req, out)
    plots.fig_isolines_by_speed(req=req, out=out)
    plots.fig_latency_sensitivity(v_c, out=out)
    plots.fig_sector_coverage(v_c=v_c, req=req, out=out)
    plots.fig_power_aperture(out=out)
    say(f"Figures written to `{out}`")

    (ROOT / "docs").mkdir(exist_ok=True)
    (ROOT / "docs" / "level1_results.md").write_text("\n".join(lines) + "\n")


if __name__ == "__main__":
    main()
