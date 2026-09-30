"""Level 3 figures (16+)."""

from __future__ import annotations

from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

from cuas_l1.plots import INK, INK2, SERIES, _save
from .radar import RadarParams, ClutterModel, db, GAMMA_DB_BY_LC, MTI_IMPROVEMENT_DB_BY_LC
from cuas_l4.terrain import LC_NAMES


def fig_snr_pd(radar: RadarParams, rcs_list=(0.1, 0.03, 0.01), out: Path | None = None):
    rng = np.linspace(200, 5000, 400)
    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(11, 4.3))
    for i, rcs in enumerate(rcs_list):
        ax1.plot(rng / 1000, db(radar.snr(rng, rcs)), color=SERIES[i], lw=2,
                 label=f"σ = {rcs:g} m²")
        ax2.plot(rng / 1000, radar.pd(rng, rcs), color=SERIES[i], lw=2, label=f"σ = {rcs:g} m²")
        rr = radar.reliable_range(rcs)
        if rr > 0:
            ax2.plot(rr / 1000, radar.pd_reliable, "o", color=SERIES[i], ms=6)
            ax2.annotate(f"{rr/1000:.1f} km", (rr / 1000, radar.pd_reliable), xytext=(4, -12),
                         textcoords="offset points", fontsize=8.5, color=SERIES[i])
    ax1.axhline(db(1.0), color=INK2, lw=1, ls=":")
    ax1.text(0.1, 1, "0 dB", fontsize=8, color=INK2)
    ax1.set_xlabel("Range (km)"); ax1.set_ylabel("Integrated SNR (dB)")
    ax1.set_title("Integrated SNR vs range", fontsize=10, loc="left")
    ax1.legend(fontsize=8.5)
    ax2.axhline(radar.pd_reliable, color=INK2, lw=1, ls="--")
    ax2.text(0.1, radar.pd_reliable + 0.02, f"Pd = {radar.pd_reliable:g}", fontsize=8.5, color=INK2)
    ax2.set_ylim(0, 1.02); ax2.set_xlabel("Range (km)"); ax2.set_ylabel("Pd")
    ax2.set_title("Detection probability vs range (Swerling-1)", fontsize=10, loc="left")
    ax2.legend(fontsize=8.5)
    fig.suptitle(f"Level 3 link budget — {radar.gain_db:.0f} dBi array, "
                 f"{radar.peak_power_w:.0f} W peak, {db(radar.integration_gain()):.0f} dB integration "
                 "(thermal noise only)", fontsize=10, x=0.02, ha="left")
    fig.tight_layout()
    return _save(fig, out, "fig16_snr_pd")


def fig_reliable_vs_rcs(radar: RadarParams, out: Path | None = None):
    rcs = np.logspace(np.log10(0.005), np.log10(0.2), 40)
    rr = np.array([radar.reliable_range(s) for s in rcs]) / 1000
    fig, ax = plt.subplots(figsize=(6.8, 4.2))
    ax.semilogx(rcs, rr, color=SERIES[0], lw=2)
    for s, lab in ((0.01, "small quad"), (0.03, "nominal"), (0.1, "Group 2 / fixed-wing")):
        ax.plot(s, radar.reliable_range(s) / 1000, "o", color=INK, mfc="white", mew=1.6, ms=7)
        ax.annotate(f"{lab}\n{radar.reliable_range(s)/1000:.1f} km", (s, radar.reliable_range(s) / 1000),
                    xytext=(6, -4), textcoords="offset points", fontsize=8, color=INK)
    ax.axhline(3.0, color=SERIES[1], lw=1.4, ls="--")
    ax.text(0.006, 3.05, "3 km design claim", fontsize=8.5, color=SERIES[1])
    ax.set_xlabel("Target RCS (m²)"); ax.set_ylabel("Reliable range, Pd = 0.9 (km)")
    ax.set_title("Reliable range is set by RCS — and falls short of the 3 km claim\n"
                 "for small-UAS RCS", fontsize=10, loc="left")
    return _save(fig, out, "fig17_reliable_vs_rcs")


def fig_clutter_by_landcover(radar: RadarParams, out: Path | None = None):
    lcs = [1, 2, 3, 6, 0, 5, 4]
    grazings = [0.5, 1.0, 2.0, 5.0]
    fig, ax = plt.subplots(figsize=(8, 4.3))
    width = 0.8 / len(grazings)
    xpos = np.arange(len(lcs))
    for gi, g in enumerate(grazings):
        rr = [radar.reliable_range(0.03, ClutterModel(grazing_deg=g), lc) / 1000 for lc in lcs]
        ax.bar(xpos + gi * width, rr, width, color=SERIES[gi], label=f"grazing {g:g}°")
    ax.axhline(radar.reliable_range(0.03) / 1000, color=INK2, lw=1, ls="--")
    ax.text(len(lcs) - 1, radar.reliable_range(0.03) / 1000 + 0.03, "thermal-only", fontsize=8.5,
            color=INK2, ha="right")
    ax.set_xticks(xpos + 0.3)
    ax.set_xticklabels([f"{LC_NAMES[lc]}\nγ{GAMMA_DB_BY_LC[lc]:.0f} I{MTI_IMPROVEMENT_DB_BY_LC[lc]:.0f}"
                        for lc in lcs], fontsize=8)
    ax.set_ylabel("Reliable range, RCS 0.03 m² (km)")
    ax.set_title("Clutter by land cover and grazing angle (γ = σ⁰ level, I = MTI improvement, dB)",
                 fontsize=9.5, loc="left")
    ax.legend(fontsize=8.5, ncol=2)
    ax.grid(axis="x", visible=False)
    return _save(fig, out, "fig18_clutter_by_landcover")


def fig_physics_vs_placement(radar: RadarParams, v_c=30.0, t_req=300.0, out: Path | None = None):
    """Required forward placement given the physics reliable range, by RCS."""
    rcs = np.array([0.1, 0.05, 0.03, 0.02, 0.01])
    rr = np.array([radar.reliable_range(s) for s in rcs])
    depth_needed = v_c * t_req
    d_forward = (depth_needed - rr) / 1000
    fig, ax = plt.subplots(figsize=(7, 4.3))
    ax.plot(rcs, rr / 1000, "-o", color=SERIES[0], lw=2, label="physics reliable range")
    ax.plot(rcs, d_forward, "-o", color=SERIES[1], lw=2, label="forward placement for 300 s")
    for s, d in zip(rcs, d_forward):
        ax.annotate(f"{d:.1f} km", (s, d), xytext=(4, 4), textcoords="offset points",
                    fontsize=8, color=SERIES[1])
    ax.set_xscale("log")
    ax.set_xlabel("Target RCS (m²)"); ax.set_ylabel("km")
    ax.set_title(f"Physics feedback: a {rr[2]/1000:.1f} km node (0.03 m²) must sit "
                 f"{d_forward[2]:.1f} km forward\nfor {t_req:.0f} s at {v_c:.0f} m/s — vs 6 km assumed",
                 fontsize=9.5, loc="left")
    ax.legend(fontsize=8.5)
    return _save(fig, out, "fig19_physics_placement")
