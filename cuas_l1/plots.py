"""
Level 1 figures. Each function returns a matplotlib Figure and (optionally)
saves it. Styling is deliberately plain: single y-axis, fixed series colours,
direct labels, recessive grid — report figures, not dashboards.
"""

from __future__ import annotations

from pathlib import Path
from typing import Sequence

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

from .geometry import (Node, WarningRequirement, coverage_vs_bearing,
                       power_aperture_proxy, warning_time_headon)
from .scenarios import (ARCHITECTURE_CASES, BASELINE_REQ, D_FORWARD_GRID,
                        R_DETECT_GRID, SECTOR_WIDTHS, V_C_BASELINE)

# Fixed categorical order (never cycled).
SERIES = ["#2a78d6", "#eb6834", "#1baf7a", "#eda100", "#e87ba4", "#008300", "#4a3aa7", "#e34948"]
INK = "#0b0b0b"
INK2 = "#52514e"
GRID = "#e6e5e1"
SURFACE = "#fcfcfb"

plt.rcParams.update({
    "figure.facecolor": SURFACE,
    "axes.facecolor": SURFACE,
    "axes.edgecolor": INK2,
    "axes.labelcolor": INK,
    "axes.titlecolor": INK,
    "xtick.color": INK2,
    "ytick.color": INK2,
    "axes.grid": True,
    "grid.color": GRID,
    "grid.linewidth": 0.8,
    "axes.spines.top": False,
    "axes.spines.right": False,
    "font.size": 10,
    "legend.frameon": False,
})


def _save(fig, out: Path | None, name: str):
    if out is not None:
        out.mkdir(parents=True, exist_ok=True)
        fig.savefig(out / f"{name}.png", dpi=180, bbox_inches="tight")
        fig.savefig(out / f"{name}.svg", bbox_inches="tight")
    return fig


# --------------------------------------------------------------------------- #
# Figure 1: range vs placement, T_warning field with 300 s isoline
# --------------------------------------------------------------------------- #

def fig_range_vs_placement(v_c: float = V_C_BASELINE,
                           req: WarningRequirement = BASELINE_REQ,
                           out: Path | None = None):
    r = np.linspace(*R_DETECT_GRID)
    d = np.linspace(*D_FORWARD_GRID)
    D, R = np.meshgrid(d, r)
    T = warning_time_headon(D, R, v_c, req.t_latency, req.r_action)

    fig, ax = plt.subplots(figsize=(7.5, 5))
    levels = np.arange(0, 601, 60)
    cf = ax.contourf(D / 1000, R / 1000, np.clip(T, 0, 600), levels=levels,
                     cmap="Blues", alpha=0.9)
    cb = fig.colorbar(cf, ax=ax, pad=0.02)
    cb.set_label("Ideal warning time (s)", color=INK)
    cb.ax.tick_params(colors=INK2)
    cs = ax.contour(D / 1000, R / 1000, T, levels=[req.t_required],
                    colors=[SERIES[1]], linewidths=2)
    ax.clabel(cs, fmt={req.t_required: f"{req.t_required:.0f} s"},
              inline=True, fontsize=9, colors=[SERIES[1]])

    for i, case in enumerate(ARCHITECTURE_CASES):
        if case.r_detect > r.max() or case.d_forward > d.max():
            continue
        ax.plot(case.d_forward / 1000, case.r_detect / 1000, "o", ms=8,
                color=INK, mfc="white", mew=1.6)
        ax.annotate(case.name, (case.d_forward / 1000, case.r_detect / 1000),
                    xytext=(6, 6), textcoords="offset points", fontsize=8.5,
                    color=INK)

    ax.set_xlabel("Forward placement D_forward (km)")
    ax.set_ylabel("Reliable detection range R_detect (km)")
    ax.set_title(f"Warning time vs range and placement  (V_c = {v_c:.0f} m/s, "
                 f"latency {req.t_latency:.0f} s, buffer {req.r_action/1000:.1f} km)",
                 fontsize=10.5, loc="left")
    ax.grid(False)
    return _save(fig, out, "fig1_range_vs_placement")


# --------------------------------------------------------------------------- #
# Figure 2: 300 s isolines for several closure speeds
# --------------------------------------------------------------------------- #

def fig_isolines_by_speed(speeds: Sequence[float] = (10, 20, 30, 40, 50),
                          req: WarningRequirement = BASELINE_REQ,
                          out: Path | None = None):
    d = np.linspace(*D_FORWARD_GRID)
    fig, ax = plt.subplots(figsize=(7.5, 5))
    for i, v in enumerate(speeds):
        r_min = req.r_action + v * (req.t_required + req.t_latency) - d
        ax.plot(d / 1000, r_min / 1000, color=SERIES[i % len(SERIES)], lw=2)
        # direct label where the line enters the plot (top or left edge)
        j = int(np.argmax(r_min / 1000 <= 9.6)) if (r_min / 1000 <= 9.6).any() else 0
        ax.annotate(f"{v:.0f} m/s", (d[j] / 1000, r_min[j] / 1000),
                    xytext=(6, -4), textcoords="offset points", fontsize=9,
                    va="top", color=SERIES[i % len(SERIES)])
    ax.axhspan(2, 3, color=SERIES[2], alpha=0.12, lw=0)
    ax.text(9.9, 2.5, "candidate node 2-3 km", ha="right", va="center",
            fontsize=8.5, color=INK2)
    ax.set_xlim(0, 10)
    ax.set_ylim(0, 10.5)
    ax.set_xlabel("Forward placement D_forward (km)")
    ax.set_ylabel("Minimum R_detect for the requirement (km)")
    ax.set_title(f"Range needed to deliver {req.t_required:.0f} s of warning, "
                 "by closure speed", fontsize=10.5, loc="left")
    return _save(fig, out, "fig2_isolines_by_speed")


# --------------------------------------------------------------------------- #
# Figure 3: latency sensitivity for the architecture cases
# --------------------------------------------------------------------------- #

def fig_latency_sensitivity(v_c: float = V_C_BASELINE,
                            latencies=np.linspace(0, 90, 91),
                            out: Path | None = None):
    """Warning time vs latency for several total warning depths. The three
    handoff architectures that meet 300 s all have 9 km of depth and are one
    line here; the point of the figure is how much *extra* depth latency
    forces you to buy."""
    fig, ax = plt.subplots(figsize=(7.5, 4.5))
    depths_km = (6, 9, 12, 15)
    labels = {9: "9 km  (all three handoff architectures)",
              6: "6 km", 12: "12 km", 15: "15 km"}
    for i, dk in enumerate(depths_km):
        t = warning_time_headon(dk * 1000.0, 0.0, v_c, latencies)
        ax.plot(latencies, t, color=SERIES[i], lw=2)
        ax.annotate(labels[dk], (latencies[-1], t[-1]), xytext=(4, 0),
                    textcoords="offset points", fontsize=8.5, va="center",
                    color=SERIES[i])
    ax.axhline(300, color=INK2, lw=1, ls="--")
    ax.text(0.5, 306, "300 s requirement", fontsize=8.5, color=INK2)
    # where each depth crosses the requirement
    for i, dk in enumerate(depths_km):
        lat_max = dk * 1000.0 / v_c - 300.0
        if 0 < lat_max < latencies[-1]:
            ax.plot(lat_max, 300, "o", color=SERIES[i], ms=6)
            ax.annotate(f"{lat_max:.0f} s budget", (lat_max, 300), xytext=(0, 8),
                        textcoords="offset points", fontsize=8, ha="center",
                        color=SERIES[i])
    ax.set_xlim(0, latencies[-1])
    ax.set_ylim(0, 520)
    ax.set_xlabel("End-to-end latency T_latency (s)")
    ax.set_ylabel("Warning time (s)")
    ax.set_title(f"Latency eats warning one-for-one  (V_c = {v_c:.0f} m/s, head-on, "
                 "by total warning depth)", fontsize=10.5, loc="left")
    fig.subplots_adjust(right=0.70)
    return _save(fig, out, "fig3_latency_sensitivity")


# --------------------------------------------------------------------------- #
# Figure 4: sector coverage vs approach bearing
# --------------------------------------------------------------------------- #

def fig_sector_coverage(r_detect: float = 3000.0, d_forward: float = 6000.0,
                        v_c: float = V_C_BASELINE,
                        req: WarningRequirement = BASELINE_REQ,
                        widths: Sequence[float] = SECTOR_WIDTHS,
                        out: Path | None = None):
    fig, ax = plt.subplots(figsize=(7.5, 4.5))
    bearings = np.arange(-90, 90.5, 0.5)
    results = {}
    for i, w in enumerate(widths):
        node = Node(x=d_forward, r_detect=r_detect, sector_width=w)
        res = coverage_vs_bearing([node], v_c, req, bearings)
        results[w] = res
        t = np.where(np.isfinite(res.t_warning), res.t_warning, 0)
        ax.plot(bearings, t, color=SERIES[i], lw=2, label=f"{w:.0f}° sector")
    node360 = Node(x=d_forward, r_detect=r_detect, sector_width=360)
    res360 = coverage_vs_bearing([node360], v_c, req, bearings)
    ax.plot(bearings, np.where(np.isfinite(res360.t_warning), res360.t_warning, 0),
            color=INK2, lw=1.2, ls=":", label="360° (reference)")
    ax.axhline(req.t_required, color=INK2, lw=1, ls="--")
    ax.text(-89, req.t_required + 6, f"{req.t_required:.0f} s requirement",
            fontsize=8.5, color=INK2)
    ax.set_xlim(-90, 90)
    ax.set_ylim(0, 340)
    ax.set_xlabel("Threat approach bearing relative to sector boresight (deg)")
    ax.set_ylabel("Warning time (s)")
    ax.set_title(f"One {r_detect/1000:.0f} km node, {d_forward/1000:.0f} km forward: "
                 "warning vs approach bearing", fontsize=10.5, loc="left")
    ax.legend(loc="upper right", fontsize=8.5)
    return _save(fig, out, "fig4_sector_coverage"), results


# --------------------------------------------------------------------------- #
# Figure 5: power-aperture proxy
# --------------------------------------------------------------------------- #

def fig_power_aperture(out: Path | None = None):
    r = np.linspace(1000, 10000, 200)
    fig, ax = plt.subplots(figsize=(6.5, 4.2))
    ax.plot(r / 1000, power_aperture_proxy(r), color=SERIES[0], lw=2)
    for case in ARCHITECTURE_CASES[:3]:
        y = float(power_aperture_proxy(case.r_detect))
        ax.plot(case.r_detect / 1000, y, "o", color=INK, mfc="white", mew=1.6, ms=7)
        ax.annotate(f"{case.r_detect/1000:.0f} km: {y:.0f}x",
                    (case.r_detect / 1000, y), xytext=(6, -2),
                    textcoords="offset points", fontsize=8.5, color=INK)
    ax.set_yscale("log")
    ax.set_xlabel("Reliable detection range R_detect (km)")
    ax.set_ylabel("Relative power-aperture (3 km node = 1)")
    ax.set_title("Range is bought with the fourth power of power-aperture",
                 fontsize=10.5, loc="left")
    return _save(fig, out, "fig5_power_aperture_proxy")
