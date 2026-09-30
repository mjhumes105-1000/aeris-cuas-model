"""
Level 1 mission-geometry model for C-UAS warning.

Deterministic, 2-D (plan view), no detection statistics. This level answers one
question: for a given threat closure speed, how much reliable sensing range and
forward placement are needed to deliver a required warning time?

Conventions
-----------
* The defended point is the origin (0, 0).
* The expected threat axis is +x. "Forward" means +x, toward the threat.
* Bearings are measured in degrees from the +x axis (counter-clockwise
  positive). A threat "approach bearing" of 0 deg means the threat comes
  straight down the expected axis; +30 deg means it comes in 30 deg off-axis.
* Every threat flies a straight line at constant speed directly toward the
  defended point, starting far outside any sensor's reach.
* All distances in metres, speeds in m/s, times in seconds, angles in degrees.

Core equations (from the project concept brief)
----------------------------------------
    T_warning     = (D_forward + R_detect - R_action) / V_c - T_latency
    R_detect,min  = R_action + V_c * (T_required + T_latency) - D_forward

The first is the head-on, on-axis special case of what this module computes in
general: warning depth is the distance from the defended point to the first
point on the threat path that lies inside some node's reliable coverage.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Iterable, Sequence

import numpy as np

# --------------------------------------------------------------------------- #
# Data classes
# --------------------------------------------------------------------------- #


@dataclass(frozen=True)
class Node:
    """A fixed-sector sensing node.

    Parameters
    ----------
    x, y : float
        Position relative to the defended point (m). +x is forward.
    r_detect : float
        Reliable detection/track range (m). Level 1 treats this as a hard
        edge: inside is detected, outside is not.
    sector_width : float
        Field-of-regard width in degrees (30, 60, 90, or 360 for a
        rotating/omni comparison). Centred on `boresight`.
    boresight : float
        Sector centre bearing in degrees (0 = looking along +x, toward the
        expected threat axis).
    """

    x: float = 0.0
    y: float = 0.0
    r_detect: float = 3000.0
    sector_width: float = 90.0
    boresight: float = 0.0

    @property
    def position(self) -> np.ndarray:
        return np.array([self.x, self.y], dtype=float)


@dataclass(frozen=True)
class Threat:
    """A straight-line threat closing on the defended point.

    Parameters
    ----------
    speed : float
        Closure speed V_c (m/s). Group 1-2 UAS: roughly 10-50 m/s.
    bearing : float
        Approach bearing in degrees. The threat starts at
        `start_range` along this bearing and flies to the origin.
    start_range : float
        Where the threat is spawned (m). Must exceed any node's reach;
        200 km is a safe default and costs nothing in a closed-form model.
    """

    speed: float = 30.0
    bearing: float = 0.0
    start_range: float = 200_000.0

    @property
    def direction_in(self) -> np.ndarray:
        """Unit vector pointing from the threat toward the origin."""
        b = np.deg2rad(self.bearing)
        return -np.array([np.cos(b), np.sin(b)])

    @property
    def start_position(self) -> np.ndarray:
        b = np.deg2rad(self.bearing)
        return self.start_range * np.array([np.cos(b), np.sin(b)])


@dataclass(frozen=True)
class WarningRequirement:
    """Mission-derived timing requirement.

    t_required : float
        Required useful warning time (s). Provisional study value: 300 s.
    t_latency : float
        End-to-end latency budget (s): sensing, track confirmation,
        processing, transport, CoT/ATAK rendering, operator orientation and
        decision. Level 1 treats this as a single lumped constant.
    r_action : float
        Action buffer (m): the range from the defended point at which the
        warning clock stops (e.g. the range at which the operator must have
        already acted). 0 means the clock runs to the defended point.
    """

    t_required: float = 300.0
    t_latency: float = 0.0
    r_action: float = 0.0


# --------------------------------------------------------------------------- #
# Closed-form head-on equations (the handoff's first-order case)
# --------------------------------------------------------------------------- #


def warning_time_headon(
    d_forward: float | np.ndarray,
    r_detect: float | np.ndarray,
    v_c: float,
    t_latency: float = 0.0,
    r_action: float = 0.0,
) -> np.ndarray:
    """T_warning = (D_forward + R_detect - R_action) / V_c - T_latency.

    Vectorised over d_forward / r_detect (broadcasting). Negative results are
    kept (they mean the requirement cannot be met even in the ideal case);
    clip at the call site if you want a floor of zero.
    """
    d_forward = np.asarray(d_forward, dtype=float)
    r_detect = np.asarray(r_detect, dtype=float)
    return (d_forward + r_detect - r_action) / v_c - t_latency


def r_detect_min_headon(
    d_forward: float | np.ndarray,
    v_c: float,
    t_required: float,
    t_latency: float = 0.0,
    r_action: float = 0.0,
) -> np.ndarray:
    """R_detect,min = R_action + V_c (T_required + T_latency) - D_forward."""
    d_forward = np.asarray(d_forward, dtype=float)
    return r_action + v_c * (t_required + t_latency) - d_forward


def warning_depth_required(v_c: float, t_required: float, t_latency: float = 0.0,
                           r_action: float = 0.0) -> float:
    """Total warning depth (m) needed along the approach axis.

    At 30 m/s and 300 s with zero latency and zero buffer this is 9 000 m,
    the handoff's headline number.
    """
    return r_action + v_c * (t_required + t_latency)


# --------------------------------------------------------------------------- #
# General 2-D geometry: first detection along a straight path
# --------------------------------------------------------------------------- #


def _wrap_deg(a: np.ndarray) -> np.ndarray:
    """Wrap angles to (-180, 180]."""
    return (a + 180.0) % 360.0 - 180.0


def _in_sector(node: Node, points: np.ndarray) -> np.ndarray:
    """Boolean mask: which points (N,2) fall inside the node's angular sector."""
    if node.sector_width >= 360.0:
        return np.ones(len(points), dtype=bool)
    rel = points - node.position
    bearing = np.rad2deg(np.arctan2(rel[:, 1], rel[:, 0]))
    off = np.abs(_wrap_deg(bearing - node.boresight))
    return off <= node.sector_width / 2.0


def first_detection_range(threat: Threat, nodes: Sequence[Node]) -> float:
    """Distance from the defended point at which the threat is first inside
    any node's reliable coverage (range AND sector). Returns 0.0 if the
    threat is never detected before reaching the origin.

    Method: the threat path is the segment from `start_position` to the
    origin. For each node, intersect that line with the node's range circle
    (closed form), then walk the in-range interval and keep only the part
    inside the sector. Sector membership along a straight path can switch on
    and off, so the in-range interval is sampled finely (1 m) and the
    first sector-valid sample is taken. Because the line-circle
    intersection is exact, the sampling only affects the sector boundary,
    and 1 m is far below any Level 1 decision resolution.
    """
    p0 = threat.start_position
    u = threat.direction_in  # unit vector toward origin
    path_len = threat.start_range
    best = 0.0

    for node in nodes:
        # Solve |p0 + s*u - c|^2 = R^2 for s (distance travelled from spawn).
        d = p0 - node.position
        b = 2.0 * float(d @ u)
        c = float(d @ d) - node.r_detect**2
        disc = b * b - 4.0 * c
        if disc < 0.0:
            continue  # path never enters this node's range circle
        sq = np.sqrt(disc)
        s_in = (-b - sq) / 2.0
        s_out = (-b + sq) / 2.0
        # Clip to the actual flown segment [0, path_len]
        s_in = max(s_in, 0.0)
        s_out = min(s_out, path_len)
        if s_out <= s_in:
            continue
        if node.sector_width >= 360.0:
            depth = path_len - s_in
        else:
            n = max(int(np.ceil((s_out - s_in) / 1.0)) + 1, 2)
            s = np.linspace(s_in, s_out, n)
            pts = p0[None, :] + s[:, None] * u[None, :]
            ok = _in_sector(node, pts)
            if not ok.any():
                continue
            depth = path_len - s[np.argmax(ok)]
        best = max(best, depth)
    return float(best)


def warning_time(threat: Threat, nodes: Sequence[Node],
                 req: WarningRequirement) -> float:
    """General-geometry warning time (s). Returns a value <= 0 when there is
    no useful warning (never detected, or detected inside the action buffer
    / latency window)."""
    depth = first_detection_range(threat, nodes)
    if depth <= 0.0:
        return -np.inf
    return (depth - req.r_action) / threat.speed - req.t_latency


# --------------------------------------------------------------------------- #
# Sector-coverage analysis
# --------------------------------------------------------------------------- #


@dataclass
class CoverageResult:
    bearings: np.ndarray
    t_warning: np.ndarray      # seconds, -inf where never detected
    depth: np.ndarray          # metres
    meets: np.ndarray          # bool, t_warning >= t_required
    p_meet: float = field(init=False)

    def __post_init__(self):
        self.p_meet = float(np.mean(self.meets))


def coverage_vs_bearing(nodes: Sequence[Node], speed: float,
                        req: WarningRequirement,
                        bearings: Iterable[float] | None = None) -> CoverageResult:
    """Sweep threat approach bearing and report warning time for each.

    `p_meet` is the fraction of bearings that achieve the requirement — i.e.
    the sector-coverage probability under a uniform bearing prior over the
    sweep. Pass a narrower `bearings` array to encode a corridor prior.
    """
    if bearings is None:
        bearings = np.arange(-180.0, 180.0, 1.0)
    bearings = np.asarray(list(bearings), dtype=float)
    t = np.empty_like(bearings)
    d = np.empty_like(bearings)
    for i, br in enumerate(bearings):
        thr = Threat(speed=speed, bearing=br)
        d[i] = first_detection_range(thr, nodes)
        t[i] = (d[i] - req.r_action) / speed - req.t_latency if d[i] > 0 else -np.inf
    # 1e-6 s tolerance so an exactly-met requirement is not lost to rounding
    return CoverageResult(bearings=bearings, t_warning=t, depth=d,
                          meets=t >= req.t_required - 1e-6)


# --------------------------------------------------------------------------- #
# Cost / SWaP proxy
# --------------------------------------------------------------------------- #


def power_aperture_proxy(r_detect: float | np.ndarray, r_ref: float = 3000.0) -> np.ndarray:
    """Relative power-aperture product needed for range R, normalised to a
    reference node. From the radar equation, R_max ∝ (P·G·A)^(1/4) with all
    else equal, so P·A ∝ R^4. This is a *proxy*, not a cost model: it says
    that a 9 km node needs ~81x the power-aperture of a 3 km node, which is
    the physical reason the handoff says 'do not buy range you can get by
    placement.' Real cost scales sub-linearly with power-aperture, so treat
    the exponent as a parameter to sweep at Level 3."""
    return (np.asarray(r_detect, dtype=float) / r_ref) ** 4


def cost_per_warning_depth(nodes: Sequence[Node], depth: float,
                           r_ref: float = 3000.0) -> float:
    """Sum of node power-aperture proxies divided by achieved warning depth
    (km). Lower is better. Meaningless when depth is 0."""
    total = float(sum(power_aperture_proxy(n.r_detect, r_ref) for n in nodes))
    return total / (depth / 1000.0) if depth > 0 else np.inf


# --------------------------------------------------------------------------- #
# Radar-horizon helper (optional cap on r_detect)
# --------------------------------------------------------------------------- #


def radar_horizon(h_antenna_m: float, h_target_m: float, k: float = 4.0 / 3.0) -> float:
    """Geometric radar horizon (m) for antenna and target heights, using the
    4/3-earth model. Level 1 can use this to cap r_detect for low-flying
    targets; it is a reminder that a 9 km range against a 30 m AGL target
    from a 2 m mast is not physically available regardless of radar power.
    """
    r_e = 6_371_000.0 * k
    return np.sqrt(2 * r_e * h_antenna_m) + np.sqrt(2 * r_e * h_target_m)
