"""
Level 2 Monte Carlo: imperfect detection and the warning chain.

For each trial a threat is drawn from the prior, node availability is drawn,
and the threat is stepped toward the defended point at the tracker's revisit
interval. At every look each available node whose sector contains the threat
rolls a detection with Pd(range). Detections are fused centrally and a track
is confirmed by an M-of-N rule. Warning time is the time-to-go at
confirmation minus a sampled latency chain. Trials are vectorised in batches
(trials x looks arrays), so 10^4–10^5 trials run in seconds on a laptop.

Level 1 is recovered exactly with DetectionModel(kind="hard", pd=1),
m_of_n=(1,1), zero latency and full availability (see tests).
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Sequence

import numpy as np

from cuas_l1.geometry import Node, _wrap_deg
from .models import Level2Config


@dataclass
class Level2Result:
    n_trials: int
    speed: np.ndarray            # m/s per trial
    bearing: np.ndarray          # deg per trial
    range_first_detect: np.ndarray   # m from defended point; nan if never
    range_track: np.ndarray          # m at track confirmation; nan if never
    latency: np.ndarray              # sampled chain latency (s)
    t_warning: np.ndarray            # s; -inf if never confirmed
    n_nodes_available: np.ndarray    # per trial
    t_required: float
    false_alerts_per_hour: float
    ppv: float

    # ---- summary metrics --------------------------------------------------
    @property
    def p_meet(self) -> float:
        return float(np.mean(self.t_warning >= self.t_required - 1e-9))

    @property
    def p_track(self) -> float:
        return float(np.mean(np.isfinite(self.range_track)))

    @property
    def p_miss(self) -> float:
        return 1.0 - self.p_track

    def percentile_warning(self, q) -> np.ndarray:
        """Percentiles of warning time with never-confirmed counted as 0."""
        tw = np.where(np.isfinite(self.t_warning), self.t_warning, 0.0)
        return np.percentile(np.clip(tw, 0, None), q)

    def summary(self) -> dict:
        p10, p50, p90 = self.percentile_warning([10, 50, 90])
        return {
            "P(T_warning >= T_req)": self.p_meet,
            "P(track confirmed)": self.p_track,
            "P(miss)": self.p_miss,
            "T_warning p10/p50/p90 (s)": (float(p10), float(p50), float(p90)),
            "mean range at first detection (km)": float(np.nanmean(self.range_first_detect)) / 1000,
            "mean range at track (km)": float(np.nanmean(self.range_track)) / 1000,
            "median latency (s)": float(np.median(self.latency)),
            "mean nodes available": float(np.mean(self.n_nodes_available)),
            "false alerts / h": self.false_alerts_per_hour,
            "PPV": self.ppv,
        }


def _sector_mask(node: Node, dx: np.ndarray, dy: np.ndarray) -> np.ndarray:
    if node.sector_width >= 360.0:
        return np.ones_like(dx, dtype=bool)
    bearing = np.rad2deg(np.arctan2(dy, dx))
    return np.abs(_wrap_deg(bearing - node.boresight)) <= node.sector_width / 2.0


def simulate(nodes: Sequence[Node], cfg: Level2Config, n_trials: int = 20_000,
             seed: int | None = 0, batch: int = 2_000,
             visibility: Sequence | None = None) -> Level2Result:
    """
    visibility : optional list (one per node) of callables f(x, y) -> bool
        array, e.g. Level 4 `Viewshed` objects. A node can only detect the
        threat at positions where its callable is True. None = flat earth,
        unobstructed (Levels 1-2 behaviour).
    """
    rng = np.random.default_rng(seed)
    if visibility is not None and len(visibility) != len(nodes):
        raise ValueError("visibility must have one entry per node")
    nodes = list(nodes)
    n_nodes = len(nodes)
    dt = cfg.tracker.revisit_s
    M, N = cfg.tracker.m_of_n

    # Spawn range: far enough that Pd is negligible for every node.
    reach = max(np.hypot(n.x, n.y) + 2.0 * n.r_detect for n in nodes)
    start = 1.05 * reach

    v_all, b_all = cfg.threat.sample(n_trials, rng)
    avail_all = cfg.availability.sample(n_trials, n_nodes, rng)
    lat_all = cfg.latency.sample(n_trials, rng)

    r_first = np.full(n_trials, np.nan)
    r_track = np.full(n_trials, np.nan)

    for i0 in range(0, n_trials, batch):
        i1 = min(i0 + batch, n_trials)
        v = v_all[i0:i1]
        b = np.deg2rad(b_all[i0:i1])
        avail = avail_all[i0:i1]
        nb = i1 - i0

        n_steps = int(np.ceil(start / (v.min() * dt))) + 1
        t = np.arange(n_steps) * dt                        # (steps,)
        rho = start - v[:, None] * t[None, :]              # (nb, steps) range from origin
        alive = rho > 0.0
        px = rho * np.cos(b)[:, None]
        py = rho * np.sin(b)[:, None]

        det_any = np.zeros((nb, n_steps), dtype=bool)
        for j, node in enumerate(nodes):
            dx = px - node.x
            dy = py - node.y
            dist = np.hypot(dx, dy)
            pd = cfg.detection.pd(dist, node.r_detect)
            pd = pd * _sector_mask(node, dx, dy) * alive * avail[:, j][:, None]
            if visibility is not None and visibility[j] is not None:
                pd = pd * visibility[j](px, py)
            det_any |= rng.random((nb, n_steps)) < pd

        # first detection
        has_det = det_any.any(axis=1)
        k_first = np.argmax(det_any, axis=1)
        r_first[i0:i1] = np.where(has_det, rho[np.arange(nb), k_first], np.nan)

        # M-of-N over a sliding window of N looks (inclusive of current look)
        cs = np.cumsum(det_any, axis=1)
        window = cs - np.concatenate([np.zeros((nb, N)), cs[:, :-N]], axis=1) if N < n_steps \
            else cs
        confirmed = (window >= M) & alive
        has_trk = confirmed.any(axis=1)
        k_trk = np.argmax(confirmed, axis=1)
        r_track[i0:i1] = np.where(has_trk, rho[np.arange(nb), k_trk], np.nan)

    with np.errstate(invalid="ignore"):
        t_warn = (r_track - cfg.r_action) / v_all - lat_all
    t_warn = np.where(np.isfinite(r_track), t_warn, -np.inf)

    n_avail = avail_all.sum(axis=1)
    p_track = float(np.mean(np.isfinite(r_track)))
    fa_rate = cfg.false_alerts.system_rate(float(n_avail.mean()))
    ppv = cfg.false_alerts.ppv(float(n_avail.mean()), p_track)

    return Level2Result(
        n_trials=n_trials, speed=v_all, bearing=b_all,
        range_first_detect=r_first, range_track=r_track, latency=lat_all,
        t_warning=t_warn, n_nodes_available=n_avail, t_required=cfg.t_required,
        false_alerts_per_hour=fa_rate, ppv=ppv,
    )
