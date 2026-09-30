"""Level 4 figures (12+)."""

from __future__ import annotations

from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.colors import LightSource, ListedColormap
import numpy as np

from cuas_l1.plots import INK, INK2, SERIES, _save
from .terrain import LC_NAMES, Terrain, Viewshed

LC_COLORS = {0: "#9ecae1", 1: "#e8d9b5", 2: "#c7e3a8", 3: "#a2c48a", 4: "#4f8a4b",
             5: "#8c8c8c", 6: "#7fb8b0"}


def _hillshade(ax, t: Terrain, alpha=1.0):
    ls = LightSource(azdeg=315, altdeg=45)
    shade = ls.hillshade(t.z, vert_exag=2.0, dx=t.dx, dy=t.dx)
    ax.imshow(shade, cmap="gray", extent=(*t.extent,), origin="lower", alpha=alpha, vmin=0, vmax=1)


def fig_terrain(t: Terrain, defended=(0.0, 0.0), candidates=None, out: Path | None = None):
    fig, ax = plt.subplots(figsize=(8, 7.2))
    _hillshade(ax, t)
    if t.landcover is not None:
        cmap = ListedColormap([LC_COLORS[k] for k in sorted(LC_COLORS)])
        ax.imshow(t.landcover, cmap=cmap, vmin=-0.5, vmax=6.5, extent=(*t.extent,),
                  origin="lower", alpha=0.45, interpolation="nearest")
    cs = ax.contour(t.x / 1, t.y / 1, t.z, levels=np.arange(0, t.z.max() + 1, 25),
                    colors=[INK2], linewidths=0.4, alpha=0.6)
    ax.plot(*defended, "*", ms=14, color=SERIES[7], mec="white", mew=1)
    ax.annotate("defended point", defended, xytext=(8, -14), textcoords="offset points",
                fontsize=9, color=INK)
    ax.annotate("", xy=(4500, 0), xytext=(800, 0),
                arrowprops=dict(arrowstyle="-|>", color=INK, lw=1.5))
    ax.text(2600, 180, "expected threat axis", fontsize=8.5, color=INK, ha="center")
    if candidates:
        xs = [c.x for c in candidates]; ys = [c.y for c in candidates]
        p = [c.p_meet for c in candidates]
        sc = ax.scatter(xs, ys, c=p, cmap="Blues", vmin=0, vmax=1, s=70, edgecolors=INK,
                        linewidths=0.8, zorder=5)
        cb = fig.colorbar(sc, ax=ax, pad=0.02, shrink=0.7)
        cb.set_label("P(T_warning ≥ 300 s), corridor ±30°", color=INK)
        best = max(candidates, key=lambda c: c.p_meet)
        ax.annotate(f"best {best.p_meet:.2f}", (best.x, best.y), xytext=(-10, 12),
                    textcoords="offset points", fontsize=8.5, color=INK, ha="right",
                    bbox=dict(fc="white", ec="none", alpha=0.8))
    from matplotlib.patches import Patch
    ax.legend(handles=[Patch(fc=LC_COLORS[k], label=LC_NAMES[k]) for k in sorted(LC_COLORS)],
              loc="lower left", fontsize=8, framealpha=0.9)
    # crop: a little sea, all the land
    ax.set_xlim(max(t.x[0], -1500.0), t.x[-1]); ax.set_ylim(t.y[0], t.y[-1])
    ax.set_aspect("equal")
    ax.set_xlabel("x — along expected threat axis (m)"); ax.set_ylabel("y (m)")
    ax.set_title(f"{t.name}: terrain, land cover, and placement candidates", fontsize=10.5, loc="left")
    ax.grid(False)
    return _save(fig, out, "fig12_terrain_placement")


def fig_viewshed(t: Terrain, vs: Viewshed, node, out: Path | None = None, tag: str = ""):
    fig, ax = plt.subplots(figsize=(8, 7.2))
    _hillshade(ax, t)
    # rasterise polar visibility onto the grid for display
    X, Y = np.meshgrid(t.x, t.y)
    vis = vs(X, Y)
    inrange = np.hypot(X - node.x, Y - node.y) <= node.r_detect
    ang = np.degrees(np.arctan2(Y - node.y, X - node.x))
    insec = np.abs((ang - node.boresight + 180) % 360 - 180) <= node.sector_width / 2
    foot = inrange & insec
    overlay = np.full(X.shape + (4,), 0.0)
    overlay[foot & vis] = (*matplotlib.colors.to_rgb(SERIES[2]), 0.55)
    overlay[foot & ~vis] = (*matplotlib.colors.to_rgb(SERIES[7]), 0.45)
    ax.imshow(overlay, extent=(*t.extent,), origin="lower", interpolation="nearest")
    ax.plot(node.x, node.y, "^", ms=11, color=INK, mfc="white", mew=1.6, zorder=5)
    ax.plot(0, 0, "*", ms=13, color=SERIES[7], mec="white", mew=1, zorder=5)
    from matplotlib.patches import Patch
    ax.legend(handles=[Patch(fc=SERIES[2], alpha=0.6, label=f"LOS at {vs.h_tgt:.0f} m AGL"),
                       Patch(fc=SERIES[7], alpha=0.5, label="masked")], loc="lower right",
              fontsize=8.5, framealpha=0.9)
    frac = vs.fraction_visible(node.r_detect, node.sector_width, node.boresight)
    ax.set_title(f"Viewshed {tag}: node at ({node.x/1000:.1f}, {node.y/1000:.1f}) km, mast {vs.h_obs:.0f} m, "
                 f"{node.sector_width:.0f}° × {node.r_detect/1000:.0f} km — {frac:.0%} of footprint visible",
                 fontsize=9.5, loc="left")
    pad = node.r_detect * 1.3
    ax.set_xlim(node.x - pad, node.x + pad); ax.set_ylim(node.y - pad, node.y + pad)
    ax.set_xlabel("x (m)"); ax.set_ylabel("y (m)"); ax.grid(False)
    return _save(fig, out, f"fig13_viewshed{tag.replace(' ', '_')}")


def fig_los_along_axis(d_km, curves: dict, out: Path | None = None):
    fig, ax = plt.subplots(figsize=(7.5, 4.2))
    for i, (label, f) in enumerate(curves.items()):
        ax.plot(d_km, f, "-o", color=SERIES[i], lw=2, ms=4, label=label)
    ax.set_ylim(0, 1.02)
    ax.set_xlabel("Forward placement along axis (km)")
    ax.set_ylabel("LOS fraction of 90° × 3 km footprint")
    ax.set_title("Where terrain lets a node see: LOS coverage vs forward placement", fontsize=10, loc="left")
    ax.legend(fontsize=8.5)
    return _save(fig, out, "fig14_los_along_axis")


def fig_altitude_mast(h_obs, h_tgt, P, L, out: Path | None = None):
    fig, axes = plt.subplots(1, 2, figsize=(10, 4))
    for ax, M, title in ((axes[0], P, "P(T_warning ≥ 300 s)"), (axes[1], L, "LOS fraction of footprint")):
        im = ax.imshow(M, cmap="Blues", vmin=0, vmax=1, origin="lower", aspect="auto")
        ax.set_xticks(range(len(h_tgt))); ax.set_xticklabels([f"{h:.0f}" for h in h_tgt])
        ax.set_yticks(range(len(h_obs))); ax.set_yticklabels([f"{h:.0f}" for h in h_obs])
        for i in range(len(h_obs)):
            for j in range(len(h_tgt)):
                ax.text(j, i, f"{M[i, j]:.2f}", ha="center", va="center", fontsize=9,
                        color="white" if M[i, j] > 0.6 else INK)
        ax.set_xlabel("Threat altitude AGL (m)"); ax.set_ylabel("Mast height (m)")
        ax.set_title(title, fontsize=10, loc="left"); ax.grid(False)
    fig.suptitle("Mast height vs threat altitude, best on-terrain placement", fontsize=10, x=0.02, ha="left")
    fig.tight_layout()
    return _save(fig, out, "fig15_altitude_vs_mast")
