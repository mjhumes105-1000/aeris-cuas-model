"""
Level 4 studies: placement on terrain, mast height, target altitude.
"""

from __future__ import annotations

from dataclasses import dataclass, replace

import numpy as np

from cuas_l1 import Node
from cuas_l2 import Level2Config, simulate
from .terrain import Terrain, Viewshed, coverage_by_landcover, viewshed


@dataclass
class Candidate:
    x: float
    y: float
    z_ground: float
    los_fraction: float          # LOS fraction of the range/sector footprint
    p_meet: float
    p_track: float
    p_meet_flat: float | None = None
    landcover: dict | None = None


def evaluate_candidate(terrain: Terrain, cfg: Level2Config, x: float, y: float,
                       r_detect: float = 3000.0, sector: float = 90.0, boresight: float = 0.0,
                       h_obs: float = 2.0, h_tgt: float = 30.0, n_trials: int = 4_000,
                       flat_baseline: bool = False, seed: int = 0) -> Candidate:
    node = Node(x=x, y=y, r_detect=r_detect, sector_width=sector, boresight=boresight)
    vs = viewshed(terrain, (x, y), h_obs=h_obs, h_tgt=h_tgt, max_range=1.6 * r_detect)
    r = simulate([node], cfg, n_trials, seed=seed, visibility=[vs])
    pf = simulate([node], cfg, n_trials, seed=seed).p_meet if flat_baseline else None
    return Candidate(x=x, y=y, z_ground=float(terrain.elevation(x, y)),
                     los_fraction=vs.fraction_visible(r_detect, sector, boresight),
                     p_meet=r.p_meet, p_track=r.p_track, p_meet_flat=pf,
                     landcover=coverage_by_landcover(terrain, vs, r_detect, sector, boresight))


def placement_grid(terrain: Terrain, cfg: Level2Config, d_forward_m, lateral_m,
                   **kw) -> list[Candidate]:
    out = []
    for i, d in enumerate(d_forward_m):
        for j, yl in enumerate(lateral_m):
            out.append(evaluate_candidate(terrain, cfg, float(d), float(yl),
                                          seed=1000 * i + j, **kw))
    return out


def altitude_mast_matrix(terrain: Terrain, cfg: Level2Config, x: float, y: float,
                         h_obs_list=(2.0, 6.0, 12.0), h_tgt_list=(15.0, 30.0, 60.0, 120.0),
                         r_detect: float = 3000.0, sector: float = 90.0, n_trials: int = 6_000):
    P = np.zeros((len(h_obs_list), len(h_tgt_list)))
    L = np.zeros_like(P)
    for i, ho in enumerate(h_obs_list):
        for j, ht in enumerate(h_tgt_list):
            c = evaluate_candidate(terrain, cfg, x, y, r_detect, sector, 0.0, ho, ht, n_trials,
                                   seed=7 * i + j)
            P[i, j] = c.p_meet
            L[i, j] = c.los_fraction
    return np.array(h_obs_list), np.array(h_tgt_list), P, L


def los_along_axis(terrain: Terrain, d_forward_m, r_detect: float = 3000.0, sector: float = 90.0,
                   h_obs: float = 2.0, h_tgt: float = 30.0):
    return np.array([viewshed(terrain, (float(d), 0.0), h_obs, h_tgt, 1.6 * r_detect)
                     .fraction_visible(r_detect, sector, 0.0) for d in d_forward_m])
