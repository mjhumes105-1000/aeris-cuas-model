"""
Level 3 study: radar link budget, clutter, and physics-fed placement.

    python scripts/run_level3.py
"""

from __future__ import annotations

import sys
import time
from dataclasses import replace
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from cuas_l1 import Node  # noqa: E402
from cuas_l2 import Level2Config, ThreatPrior, simulate  # noqa: E402
from cuas_l3 import RadarParams, ClutterModel, PhysicsDetectionModel, db  # noqa: E402
from cuas_l3 import plots  # noqa: E402
from cuas_l4.terrain import LC_NAMES  # noqa: E402


def main():
    t0 = time.time()
    out = ROOT / "figures"
    radar = RadarParams()
    lines = []
    say = lambda s="": (print(s), lines.append(s))

    say("# Level 3 results — radar link budget (AERIS-Nexus placeholder params)")
    say()
    say("**All radar numbers are documented placeholders** (see `cuas_l3/radar.py`, "
        "`AERIS_NEXUS_PROVISIONAL`); freeze from the AERIS-10 repository before citing.")
    say()
    say(f"- Frequency {radar.freq_hz/1e9:.1f} GHz (λ = {radar.wavelength*1000:.1f} mm), "
        f"{radar.n_az}×{radar.n_el} array, aperture {radar.aperture_m2*1e4:.0f} cm², "
        f"gain **{radar.gain_db:.1f} dBi**")
    say(f"- Beamwidths {np.rad2deg(radar.beamwidth_az_rad()):.1f}° az × "
        f"{np.rad2deg(radar.beamwidth_el_rad()):.1f}° el; range resolution {radar.range_resolution_m:.0f} m")
    say(f"- Peak power {radar.peak_power_w:.0f} W, pulse {radar.pulse_width_s*1e6:.0f} µs, "
        f"PRF {radar.prf_hz/1e3:.0f} kHz, CPI {radar.cpi_pulses} pulses "
        f"→ integration {db(radar.integration_gain()):.1f} dB")
    say(f"- Noise figure {radar.noise_figure_db:.0f} dB (Ts {radar.noise_temp:.0f} K), "
        f"losses {radar.system_loss_db:.0f} dB, Pfa {radar.pfa:g}")
    say()

    # 1. Reliable range vs RCS (thermal only) --------------------------------
    say("## 1. Reliable range vs target RCS (thermal noise only)")
    say()
    say("| Target | RCS (m²) | Reliable range (Pd 0.9) | Pd @ 2 km | Pd @ 3 km |")
    say("|---|---|---|---|---|")
    for rcs, lab in ((0.1, "Group 2 / small fixed-wing"), (0.05, "large quad"),
                     (0.03, "nominal small UAS"), (0.01, "micro quad")):
        say(f"| {lab} | {rcs:g} | {radar.reliable_range(rcs)/1000:.2f} km | "
            f"{float(radar.pd(2000, rcs)):.2f} | {float(radar.pd(3000, rcs)):.2f} |")
    say()
    say(f"**Key finding.** With these placeholder parameters the node's reliable range on a "
        f"nominal 0.03 m² small UAS is **{radar.reliable_range(0.03)/1000:.1f} km**, not the 3 km "
        f"design claim; the 3 km figure is only approached for a ~0.1 m² (Group 2 / fixed-wing) "
        f"target. This is the study's skepticism about advertised ranges made quantitative, and "
        f"it propagates: the 'reliable range' Levels 1-2 treated as 3 km is really RCS-dependent "
        f"and mostly below it.")
    say()
    plots.fig_snr_pd(radar, out=out)
    plots.fig_reliable_vs_rcs(radar, out=out)

    # 2. Clutter by land cover ----------------------------------------------
    say("## 2. Clutter by land cover (RCS 0.03 m²)")
    say()
    say("Reliable range with surface clutter, by land-cover class and grazing angle. "
        "Clutter enters as single-pulse C/N divided by the Doppler processor's improvement "
        "factor (the dominant provisional unknown). γ = σ⁰ level, I = MTI improvement.")
    say()
    cl1 = ClutterModel(grazing_deg=1.0)
    say("| Land cover | thermal-only | grazing 1° | grazing 2° | grazing 5° |")
    say("|---|---|---|---|---|")
    base = radar.reliable_range(0.03) / 1000
    for lc in (1, 2, 3, 6, 0, 5, 4):
        rr = [radar.reliable_range(0.03, ClutterModel(grazing_deg=g), lc) / 1000 for g in (1, 2, 5)]
        say(f"| {LC_NAMES[lc]} | {base:.2f} km | {rr[0]:.2f} | {rr[1]:.2f} | {rr[2]:.2f} |")
    say()
    say("Bare, grass and built-up cancel to near the thermal-only range; **trees and shrub at "
        "higher grazing angles are the hard case**, because high σ⁰ combines with the limited "
        "MTI improvement that swaying vegetation allows. This is the physical link to the Level 4 "
        "land-cover map: a candidate whose footprint looks over trees is a materially harder "
        "detection problem, and the improvement factor is the single parameter most worth "
        "pinning down (bench/field measurement, or a STAP study).")
    say()
    plots.fig_clutter_by_landcover(radar, out=out)

    # 3. Physics -> placement feedback --------------------------------------
    say("## 3. Feeding physics back into placement")
    say()
    rr03 = radar.reliable_range(0.03)
    say(f"At 30 m/s the requirement needs 9 km of warning depth. A physics-limited "
        f"{rr03/1000:.1f} km node (0.03 m²) must therefore sit **{(9000-rr03)/1000:.1f} km forward**, "
        f"not the 6 km the Level 2 baseline assumed — and that is before terrain (Level 4) and the "
        f"latency/confirmation budget. The distributed-node concept still works, but the node has "
        f"to be pushed further forward or the corridor covered with more nodes.")
    say()
    plots.fig_physics_vs_placement(radar, out=out)

    # 4. Physics Pd inside the Level 2 Monte Carlo --------------------------
    say("## 4. Physics Pd inside the Level 2 warning chain")
    say()
    say("Replacing the empirical logistic Pd with the physics model and setting each node's "
        "reliable range from the link budget, then running the full Level 2 chain (revisit, "
        "3-of-4 confirmation, ~19 s latency, 0.855 availability, 30 m/s head-on):")
    say()
    say("| Config | node R_detect | D_forward | P(meet) |")
    say("|---|---|---|---|")
    for rcs in (0.1, 0.03):
        det = PhysicsDetectionModel(radar, rcs_m2=rcs)
        rr = det.reliable_range()
        cfg = replace(Level2Config(), detection=det)
        for dfwd in (6000.0, (9000 - rr)):
            node = Node(x=dfwd, r_detect=rr, sector_width=90)
            r = simulate([node], cfg, 12000)
            say(f"| RCS {rcs:g}, D={dfwd/1000:.1f} km | {rr/1000:.2f} km | {dfwd/1000:.1f} km | "
                f"**{r.p_meet:.2f}** |")
    say()
    say("The physics Pd and the empirical logistic give consistent chain behaviour once the "
        "reliable range is matched — the point of Level 3 is that it *derives* that range and its "
        "RCS/clutter dependence instead of assuming it.")
    say()

    say("## MATLAB cross-check")
    say()
    say("- The MATLAB Phased Array Toolbox scripts in `matlab/` reproduce the array gain/pattern "
        "and the SNR(range) curve independently; run them locally and compare against "
        "`figures/fig16_snr_pd`. Agreement in the overlap region validates the Python link budget.")
    say("- Dominant provisional unknowns, in order: target RCS, MTI/clutter improvement factor "
        "over vegetation, transmit power, and integration (CPI) length. All are single-line edits "
        "in `RadarParams` / the clutter tables.")
    say()
    say(f"_Run time {time.time()-t0:.0f} s._")
    (ROOT / "docs").mkdir(exist_ok=True)
    (ROOT / "docs" / "level3_results.md").write_text("\n".join(lines) + "\n")


if __name__ == "__main__":
    main()
