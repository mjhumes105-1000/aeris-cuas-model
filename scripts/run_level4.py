"""
Level 4 study: placement on terrain for the MEU beach vignette.

    python scripts/run_level4.py                         # synthetic beach
    python scripts/run_level4.py --dem path/to/tile.tif --lon -117.40 --lat 33.23 \
        [--landcover path/to/worldcover.tif] [--axis 90]
    python scripts/run_level4.py --quick
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

from cuas_l1 import Node  # noqa: E402
from cuas_l2 import Level2Config, ThreatPrior  # noqa: E402
from cuas_l4 import (Terrain, viewshed, placement_grid, altitude_mast_matrix,  # noqa: E402
                     los_along_axis, evaluate_candidate)
from cuas_l4 import plots  # noqa: E402


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dem", type=Path, default=None)
    ap.add_argument("--landcover", type=Path, default=None)
    ap.add_argument("--lon", type=float, default=None)
    ap.add_argument("--lat", type=float, default=None)
    ap.add_argument("--axis", type=float, default=90.0, help="compass bearing of +x (threat) axis")
    ap.add_argument("--half", type=float, default=12000.0)
    ap.add_argument("--quick", action="store_true")
    ap.add_argument("--out", type=Path, default=ROOT / "figures")
    args = ap.parse_args()
    q = args.quick
    t0 = time.time()

    if args.dem:
        T = Terrain.from_geotiff(args.dem, args.lon, args.lat, args.half, 30.0, args.axis,
                                 args.landcover)
    else:
        T = Terrain.synthetic_beach(args.half)

    # Corridor prior: threats from inland within ±30° of the axis, 30 m/s.
    cfg = replace(Level2Config(), threat=ThreatPrior(speed=(30.0, 30.0), bearing=(-30.0, 30.0)))
    H_TGT = 30.0    # terrain-following threat altitude AGL
    H_OBS = 2.0     # vehicle-mounted / tripod mast

    lines = []
    say = lambda s="": (print(s), lines.append(s))
    say(f"# Level 4 results — {T.name}")
    say()
    say(f"Grid {T.nx}×{T.ny} at {T.dx:.0f} m, elevation {T.z.min():.0f}–{T.z.max():.0f} m. "
        f"Threat: 30 m/s, bearing uniform ±30° from the axis, {H_TGT:.0f} m AGL terrain-following. "
        f"Node: 3 km, 90° sector on-axis, mast {H_OBS:.0f} m. Level 2 chain defaults otherwise.")
    if T.meta.get("source"):
        say(f"DEM source: `{T.meta['source']}` centred {T.meta['center_lat']:.4f}N "
            f"{-T.meta['center_lon']:.4f}W, axis bearing {T.meta['axis_bearing_deg']:.0f}°.")
    say()

    # 1. LOS along the axis ----------------------------------------------------
    d_km = np.arange(2.0, 8.01, 0.25 if not q else 0.5)
    curves = {}
    for ho, ht in ((2.0, 30.0), (6.0, 30.0), (2.0, 100.0)):
        curves[f"mast {ho:.0f} m, threat {ht:.0f} m AGL"] = los_along_axis(T, d_km * 1000, 3000, 90, ho, ht)
    plots.fig_los_along_axis(d_km, curves, args.out)
    say("## 1. LOS fraction of the 90° × 3 km footprint along the axis")
    say()
    say("| D_forward (km) | " + " | ".join(f"{d:.2f}" for d in d_km) + " |")
    say("|---|" + "---|" * len(d_km))
    for k, v in curves.items():
        say(f"| {k} | " + " | ".join(f"{x:.2f}" for x in v) + " |")
    say()

    # 2. Placement grid -----------------------------------------------------------
    say("## 2. Placement candidates (corridor prior ±30°)")
    say()
    d_grid = np.arange(3000, 8001, 500 if not q else 1000)
    y_grid = np.arange(-3000, 3001, 1000 if not q else 1500)
    cands = placement_grid(T, cfg, d_grid, y_grid, r_detect=3000, sector=90, boresight=0,
                           h_obs=H_OBS, h_tgt=H_TGT, n_trials=1_500 if q else 4_000)
    plots.fig_terrain(T, candidates=cands, out=args.out)
    cands_sorted = sorted(cands, key=lambda c: -c.p_meet)
    say("| rank | x (km) | y (km) | ground (m) | LOS frac | P(track) | P(meet) | dominant cover |")
    say("|---|---|---|---|---|---|---|---|")
    for i, c in enumerate(cands_sorted[:10], 1):
        dom = max(c.landcover, key=c.landcover.get) if c.landcover else "-"
        say(f"| {i} | {c.x/1000:.1f} | {c.y/1000:.1f} | {c.z_ground:.0f} | {c.los_fraction:.2f} | "
            f"{c.p_track:.2f} | **{c.p_meet:.2f}** | {dom} |")
    say()
    best = cands_sorted[0]
    on_axis_6 = evaluate_candidate(T, cfg, 6000, 0, 3000, 90, 0, H_OBS, H_TGT,
                                   n_trials=4_000, flat_baseline=True)
    say(f"Flat-earth Level 2 at the nominal (6.0, 0.0) km position: P(meet) = {on_axis_6.p_meet_flat:.2f}. "
        f"On this terrain the same position gives {on_axis_6.p_meet:.2f} (LOS {on_axis_6.los_fraction:.0%}); "
        f"the best candidate on the grid is ({best.x/1000:.1f}, {best.y/1000:.1f}) km at "
        f"{best.z_ground:.0f} m ground with P(meet) = {best.p_meet:.2f} (LOS {best.los_fraction:.0%}).")
    say()

    # 3. Viewsheds: nominal vs best -----------------------------------------------
    node_nom = Node(x=6000, y=0, r_detect=3000, sector_width=90)
    node_best = Node(x=best.x, y=best.y, r_detect=3000, sector_width=90)
    plots.fig_viewshed(T, viewshed(T, (6000, 0), H_OBS, H_TGT, 4800), node_nom, args.out, tag=" nominal")
    plots.fig_viewshed(T, viewshed(T, (best.x, best.y), H_OBS, H_TGT, 4800), node_best, args.out, tag=" best")

    # 4. Mast vs altitude at the nominal and best sites -----------------------------------
    say("## 3. Mast height vs threat altitude")
    say()
    mats = {}
    for label, (sx, sy) in (("nominal (6.0, 0.0) km", (6000.0, 0.0)),
                            (f"best ({best.x/1000:.1f}, {best.y/1000:.1f}) km", (best.x, best.y))):
        ho, ht, P, L = altitude_mast_matrix(T, cfg, sx, sy, n_trials=2_000 if q else 6_000)
        mats[label] = (ho, ht, P, L)
        say(f"**{label}** — cells are P(meet) (LOS fraction); rows mast height, columns threat AGL.")
        say()
        say("| mast \\ AGL | " + " | ".join(f"{h:.0f} m" for h in ht) + " |")
        say("|---|" + "---|" * len(ht))
        for i, h in enumerate(ho):
            say(f"| {h:.0f} m | " + " | ".join(f"{P[i,j]:.2f} ({L[i,j]:.2f})" for j in range(len(ht))) + " |")
        say()
    ho, ht, P, L = mats[list(mats)[1]]
    plots.fig_altitude_mast(ho, ht, P, L, args.out)

    # Data-driven interpretation ------------------------------------------------------
    hoN, htN, PN, LN = mats[list(mats)[0]]
    mast_gain_nom = float(LN[-1, 1] - LN[0, 1])     # LOS gain from mast at 30 m AGL
    alt_gain_nom = float(LN[0, -1] - LN[0, 0])      # LOS gain from altitude at 2 m mast
    say("## Interpretation")
    say()
    say(f"- Terrain masking is first-order. At the nominal (6.0, 0.0) km position flat-earth "
        f"Level 2 gives P(meet) = {on_axis_6.p_meet_flat:.2f}; on this terrain it gives "
        f"{on_axis_6.p_meet:.2f} with {on_axis_6.los_fraction:.0%} of the footprint in line of sight. "
        f"Moving to the best grid site, ({best.x/1000:.1f}, {best.y/1000:.1f}) km at {best.z_ground:.0f} m, "
        f"recovers {best.p_meet:.2f} with {best.los_fraction:.0%} LOS.")
    say("- The Level 2 placement rule ('Level 1 position plus a chain budget') must be applied on "
        "the ground: the useful forward distance is the nearest crest, saddle or shoulder that "
        "looks into the corridor, not a number on a map. Placement is a terrain problem before "
        "it is a range problem.")
    say(f"- At the nominal site, raising the mast from {hoN[0]:.0f} to {hoN[-1]:.0f} m adds "
        f"{mast_gain_nom:+.2f} to the LOS fraction (30 m AGL threat), while a threat at {htN[-1]:.0f} m "
        f"instead of {htN[0]:.0f} m AGL adds {alt_gain_nom:+.2f} (2 m mast); P(meet) there is "
        f"at most {PN.max():.2f} in any cell. " +
        ("Neither a practical mast nor a higher-flying threat rescues a masked site — only moving "
         "does. Threat altitude still outweighs mast height and belongs next to threat speed on "
         "the list of open assumptions." if PN.max() < 0.05 else
         ("Threat altitude matters more than mast height here." if abs(alt_gain_nom) > abs(mast_gain_nom)
          else "Mast height matters more than threat altitude at this site.")))
    say("- Land-cover shares of each candidate's visible footprint are recorded for Level 3 clutter "
        "modelling (a site looking over shrub and trees is a different radar problem from one "
        "looking over grass or water).")
    say()
    say(f"_Run time {time.time()-t0:.0f} s._")
    (ROOT / "docs").mkdir(exist_ok=True)
    (ROOT / "docs" / f"level4_results_{T.name}.md").write_text("\n".join(lines) + "\n")


if __name__ == "__main__":
    main()
