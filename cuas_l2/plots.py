"""Level 2 figures (numbered 6+ to follow Level 1)."""

from __future__ import annotations

from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

from cuas_l1.plots import INK, INK2, SERIES, _save  # shared style
from cuas_l1 import ARCHITECTURE_CASES


def fig_pmeet_grid(P, r_km, d_km, cfg, out: Path | None = None):
    fig, ax = plt.subplots(figsize=(7.5, 5))
    D, R = np.meshgrid(d_km, r_km)
    cf = ax.contourf(D, R, P, levels=np.linspace(0, 1, 11), cmap="Blues", alpha=0.9)
    cb = fig.colorbar(cf, ax=ax, pad=0.02)
    cb.set_label("P(T_warning ≥ 300 s)", color=INK)
    cb.ax.tick_params(colors=INK2)
    from matplotlib.lines import Line2D
    handles = []
    for lvl, col, lw in ((0.5, SERIES[3], 1.4), (0.8, SERIES[1], 2.0)):
        ax.contour(D, R, P, levels=[lvl], colors=[col], linewidths=lw)
        handles.append(Line2D([], [], color=col, lw=lw, label=f"P(meet) = {lvl:.1f}"))
    # Level 1 ideal 300 s line for reference
    ax.plot(d_km, 9.0 - np.asarray(d_km), color=INK2, lw=1, ls="--")
    handles.append(Line2D([], [], color=INK2, lw=1, ls="--", label="Level 1 ideal 300 s"))
    ax.legend(handles=handles, loc="upper right", fontsize=8.5)
    for case in ARCHITECTURE_CASES[1:3]:
        ax.plot(case.d_forward / 1000, case.r_detect / 1000, "o", ms=8, color=INK,
                mfc="white", mew=1.6)
        ax.annotate(case.name, (case.d_forward / 1000, case.r_detect / 1000),
                    xytext=(6, 6), textcoords="offset points", fontsize=8.5, color=INK)
    ax.set_xlim(d_km[0], d_km[-1]); ax.set_ylim(r_km[0], r_km[-1])
    ax.set_xlabel("Forward placement D_forward (km)")
    ax.set_ylabel("Reliable detection range R_detect (km)")
    ax.set_title("Level 2: probability of 300 s warning vs range and placement\n"
                 f"(one 90° node, Pd={cfg.detection.pd_at_r_detect} at R_detect, "
                 f"{cfg.tracker.m_of_n[0]}-of-{cfg.tracker.m_of_n[1]} @ {cfg.tracker.revisit_s:.0f} s, "
                 f"latency ~{cfg.latency.median():.0f} s, availability "
                 f"{cfg.availability.p_node_up*cfg.availability.p_comms_up:.2f})",
                 fontsize=9.5, loc="left")
    ax.grid(False)
    return _save(fig, out, "fig6_pmeet_range_vs_placement")


def fig_sensitivity(sens: dict, baseline_p: float, out: Path | None = None):
    keys = ["latency_median_s", "pd_at_r_detect", "rolloff_frac", "revisit_s", "m_of_n", "p_node_up"]
    titles = {"latency_median_s": "Latency median (s)", "pd_at_r_detect": "Pd at R_detect",
              "rolloff_frac": "Roll-off width (× R_detect)", "revisit_s": "Revisit (s)",
              "m_of_n": "Confirmation M/N", "p_node_up": "P(node up)"}
    fig, axes = plt.subplots(2, 3, figsize=(10.5, 6))
    for ax, k in zip(axes.flat, keys):
        x, p = sens[k]
        if isinstance(x[0], str):
            ax.plot(range(len(x)), p, "-o", color=SERIES[0], lw=2, ms=6)
            ax.set_xticks(range(len(x))); ax.set_xticklabels(x)
        else:
            ax.plot(x, p, "-o", color=SERIES[0], lw=2, ms=6)
        ax.axhline(baseline_p, color=INK2, lw=1, ls="--")
        ax.set_ylim(0, 1.02)
        ax.set_title(titles[k], fontsize=9.5, loc="left")
        ax.set_ylabel("P(meet)", fontsize=9)
    fig.suptitle("Level 2 one-at-a-time sensitivity — 3 km node, 6 km forward, 90° sector "
                 "(dashed = baseline)", fontsize=10, x=0.02, ha="left")
    fig.tight_layout()
    return _save(fig, out, "fig7_sensitivity")


def fig_layouts(results: dict, out: Path | None = None):
    names = list(results)
    p = [results[k].p_meet for k in names]
    ptrk = [results[k].p_track for k in names]
    fig, ax = plt.subplots(figsize=(8, 4.2))
    y = np.arange(len(names))
    ax.barh(y + 0.18, ptrk, height=0.34, color=SERIES[2], label="P(track confirmed)")
    ax.barh(y - 0.18, p, height=0.34, color=SERIES[0], label="P(T_warning ≥ 300 s)")
    for yi, (a, b) in enumerate(zip(p, ptrk)):
        ax.text(a + 0.01, yi - 0.18, f"{a:.2f}", va="center", fontsize=8.5, color=INK)
        ax.text(b + 0.01, yi + 0.18, f"{b:.2f}", va="center", fontsize=8.5, color=INK)
    ax.set_yticks(y); ax.set_yticklabels(names, fontsize=9)
    ax.invert_yaxis()
    ax.set_xlim(0, 1.12)
    ax.set_xlabel("Probability")
    ax.set_title("Node layouts, 3 km nodes 6 km forward, threat bearing uniform ±30°",
                 fontsize=10, loc="left")
    ax.legend(loc="lower right", fontsize=8.5)
    ax.grid(axis="y", visible=False)
    return _save(fig, out, "fig8_node_layouts")


def fig_warning_distributions(rows, out: Path | None = None):
    fig, ax = plt.subplots(figsize=(8, 4.2))
    bins = np.arange(0, 481, 10)
    for i, (case, r) in enumerate(rows):
        tw = np.where(np.isfinite(r.t_warning), r.t_warning, 0.0)
        ax.hist(np.clip(tw, 0, 480), bins=bins, histtype="step", lw=2,
                color=SERIES[i], label=f"{case.name}  (P={r.p_meet:.2f})", density=True)
    ax.axvline(300, color=INK2, lw=1, ls="--")
    ax.text(302, ax.get_ylim()[1] * 0.95, "300 s", fontsize=8.5, color=INK2)
    ax.set_xlabel("Warning time (s); never-confirmed shown at 0")
    ax.set_ylabel("density")
    ax.set_title("Warning-time distributions under identical imperfections (30 m/s, head-on)",
                 fontsize=10, loc="left")
    ax.legend(fontsize=8.5)
    return _save(fig, out, "fig9_warning_distributions")


def fig_forward_distance(curves: dict, out: Path | None = None):
    """curves: {label: (d_km, pmeet, d_star)}"""
    fig, ax = plt.subplots(figsize=(7.5, 4.2))
    for i, (label, (d, p, ds)) in enumerate(curves.items()):
        ax.plot(d, p, color=SERIES[i], lw=2, label=label)
        if np.isfinite(ds):
            ax.plot(ds, 0.9, "o", color=SERIES[i], ms=6)
            ax.annotate(f"{ds:.2f} km", (ds, 0.9), xytext=(4, -12), textcoords="offset points",
                        fontsize=8.5, color=SERIES[i])
    ax.axhline(0.9, color=INK2, lw=1, ls="--")
    ax.set_ylim(0, 1.02)
    ax.set_xlabel("Forward placement D_forward (km)")
    ax.set_ylabel("P(T_warning ≥ 300 s)  [availability = 1]")
    ax.set_title("How far forward must a node sit to reach P = 0.9 once the chain is imperfect?",
                 fontsize=10, loc="left")
    ax.legend(fontsize=8.5, loc="lower right")
    return _save(fig, out, "fig10_forward_distance_to_meet")


def fig_speed_band(edges, p, out: Path | None = None):
    fig, ax = plt.subplots(figsize=(6.5, 3.8))
    centers = (edges[:-1] + edges[1:]) / 2
    ax.bar(centers, p, width=4.2, color=SERIES[0])
    for c, v in zip(centers, p):
        ax.text(c, v + 0.02, f"{v:.2f}", ha="center", fontsize=8.5, color=INK)
    ax.set_ylim(0, 1.1)
    ax.set_xlabel("Closure speed bin (m/s)")
    ax.set_ylabel("P(T_warning ≥ 300 s)")
    ax.set_title("Speed dominates: 3 km node 6 km forward across the Group 1-2 band",
                 fontsize=10, loc="left")
    ax.grid(axis="x", visible=False)
    return _save(fig, out, "fig11_speed_band")
