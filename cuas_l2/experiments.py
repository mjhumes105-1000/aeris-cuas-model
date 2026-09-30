"""
Level 2 experiments. Each returns plain arrays/dicts so the run script can
tabulate and plot without re-simulating.
"""

from __future__ import annotations

from dataclasses import replace

import numpy as np

from cuas_l1 import ARCHITECTURE_CASES, Node
from .models import (DetectionModel, LatencyModel, Level2Config, ThreatPrior,
                     TrackerModel, AvailabilityModel)
from .montecarlo import simulate


def architecture_cases(cfg: Level2Config, n_trials: int = 20_000, sector: float = 90.0):
    rows = []
    for c in ARCHITECTURE_CASES:
        r = simulate([c.node(sector)], cfg, n_trials)
        rows.append((c, r))
    return rows


def pmeet_grid(cfg: Level2Config, r_detect_km, d_forward_km, n_trials: int = 3_000,
               sector: float = 90.0):
    """P(T_warning >= T_req) over a range x placement grid, one node on-axis."""
    P = np.zeros((len(r_detect_km), len(d_forward_km)))
    for i, rk in enumerate(r_detect_km):
        for j, dk in enumerate(d_forward_km):
            node = Node(x=dk * 1000, r_detect=rk * 1000, sector_width=sector)
            P[i, j] = simulate([node], cfg, n_trials, seed=i * 1000 + j).p_meet
    return P


def scaled_latency(base: LatencyModel, scale: float) -> LatencyModel:
    return LatencyModel(stages=tuple((m * scale, s) for m, s in base.stages))


def sensitivity(cfg: Level2Config, node: Node, n_trials: int = 10_000):
    """One-at-a-time sweeps around the baseline for a single node."""
    out = {}
    lat_scales = [0.0, 0.5, 1.0, 1.5, 2.0, 3.0]
    out["latency_median_s"] = ([cfg.latency.median() * s for s in lat_scales],
                               [simulate([node], replace(cfg, latency=scaled_latency(cfg.latency, s)),
                                         n_trials).p_meet for s in lat_scales])
    pds = [0.5, 0.7, 0.8, 0.9, 0.95]
    out["pd_at_r_detect"] = (pds, [simulate([node], replace(cfg, detection=replace(cfg.detection, pd_at_r_detect=p)),
                                            n_trials).p_meet for p in pds])
    rolls = [0.02, 0.05, 0.1, 0.2, 0.3]
    out["rolloff_frac"] = (rolls, [simulate([node], replace(cfg, detection=replace(cfg.detection, rolloff=w)),
                                            n_trials).p_meet for w in rolls])
    revs = [0.5, 1.0, 2.0, 4.0, 8.0]
    out["revisit_s"] = (revs, [simulate([node], replace(cfg, tracker=replace(cfg.tracker, revisit_s=t)),
                                        n_trials).p_meet for t in revs])
    mofn = [(1, 1), (2, 2), (2, 3), (3, 4), (4, 5), (5, 6)]
    out["m_of_n"] = ([f"{m}/{n}" for m, n in mofn],
                     [simulate([node], replace(cfg, tracker=replace(cfg.tracker, m_of_n=mn)),
                               n_trials).p_meet for mn in mofn])
    avail = [0.7, 0.8, 0.9, 0.95, 1.0]
    out["p_node_up"] = (avail, [simulate([node], replace(cfg, availability=replace(cfg.availability, p_node_up=a)),
                                         n_trials).p_meet for a in avail])
    return out


def forward_distance_to_meet(cfg: Level2Config, r_detect: float, target: float = 0.9,
                             d_grid_km=np.arange(4.0, 12.01, 0.25), n_trials: int = 6_000,
                             sector: float = 90.0):
    """Smallest forward placement at which one node reaches P(meet) >= target,
    with availability set to 1 so the answer isolates geometry+chain from
    attrition. Returns (d_grid, pmeet, d_star or nan)."""
    cfg1 = replace(cfg, availability=AvailabilityModel(1.0, 1.0))
    p = np.array([simulate([Node(x=d * 1000, r_detect=r_detect, sector_width=sector)],
                           cfg1, n_trials, seed=int(d * 100)).p_meet for d in d_grid_km])
    ok = np.where(p >= target)[0]
    return d_grid_km, p, (float(d_grid_km[ok[0]]) if len(ok) else np.nan)


def node_layouts(cfg: Level2Config, r_detect: float = 3000.0, d_forward: float = 6000.0,
                 sector: float = 90.0, n_trials: int = 20_000, corridor_deg: float = 30.0):
    """Compare layouts under a corridor prior (bearing uniform in ±corridor)."""
    cfgc = replace(cfg, threat=replace(cfg.threat, bearing=(-corridor_deg, corridor_deg)))

    def ring(n, half_angle):
        angs = np.linspace(-half_angle, half_angle, n) if n > 1 else np.array([0.0])
        return [Node(x=d_forward * np.cos(np.deg2rad(a)), y=d_forward * np.sin(np.deg2rad(a)),
                     r_detect=r_detect, sector_width=sector, boresight=a) for a in angs]

    layouts = {
        "1 node on axis": ring(1, 0),
        "2 co-located (redundant)": [Node(x=d_forward, r_detect=r_detect, sector_width=sector)] * 2,
        "2 nodes at ±20°": ring(2, 20),
        "3 nodes at 0, ±25°": ring(3, 25),
        "1 node, 360° sector": [Node(x=d_forward, r_detect=r_detect, sector_width=360)],
        "3 nodes 360° at 0, ±25°": [replace(n, sector_width=360.0) for n in ring(3, 25)],
    }
    return {k: simulate(v, cfgc, n_trials) for k, v in layouts.items()}


def speed_band(cfg: Level2Config, node: Node, n_trials: int = 20_000):
    cfgs = replace(cfg, threat=replace(cfg.threat, speed=(10.0, 50.0)))
    r = simulate([node], cfgs, n_trials)
    # bin P(meet) by speed
    edges = np.arange(10, 51, 5)
    idx = np.digitize(r.speed, edges) - 1
    p = [float(np.mean(r.t_warning[idx == k] >= r.t_required)) if np.any(idx == k) else np.nan
         for k in range(len(edges) - 1)]
    return edges, p, r
