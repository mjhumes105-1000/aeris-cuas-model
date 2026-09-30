"""
Level 2 component models: imperfect detection, revisit, track confirmation,
latency chain, false alerts, and availability.

Every model is a small dataclass with documented defaults taken from the
project concept brief where it gives a number, and from ordinary radar practice
where it does not. Every default is provisional and is meant to be swept.

Design rule: Level 2 has exactly ONE physics hook — `DetectionModel`, which
maps range to single-look probability of detection. Level 3 replaces the
default Swerling-I curve with SNR(range) computed from a real waveform,
array, RCS and clutter model; nothing else in Level 2 changes.
"""

from __future__ import annotations

from dataclasses import dataclass, field

import numpy as np

# --------------------------------------------------------------------------- #
# Detection: Pd(range)
# --------------------------------------------------------------------------- #


@dataclass(frozen=True)
class DetectionModel:
    """Single-look probability of detection versus range.

    kind = "logistic" (default, conservative)
        Pd(R) = pd_max / (1 + exp((R - r50) / w)), with w = rolloff * r_detect
        and r50 solved so that Pd(r_detect) = pd_at_r_detect. A steep,
        bounded roll-off: Pd is essentially zero a few widths beyond
        r_detect. This encodes the handoff's notion of a *reliable* range
        beyond which the node should not be counted on (horizon, clutter,
        integration limits), without pretending to know the physics yet.

    kind = "swerling1" (physics-shaped, optimistic)
        Swerling-I closed form, Pd = Pfa^(1 / (1 + SNR)), with SNR falling as
        the fourth power of range: SNR(R) = SNR_ref * (r_detect / R)^4, and
        SNR_ref solved so Pd(r_detect) = pd_at_r_detect. This curve has a
        long low-Pd tail; with fast revisit, cumulative detection confirms
        tracks well beyond r_detect. Level 3 replaces SNR(R) with a computed
        value including clutter and horizon, which is what tames the tail.

    kind = "hard"
        Pd = pd_at_r_detect inside r_detect, 0 outside. With pd = 1 this is
        the Level 1 model and is used for regression tests.

    Parameters
    ----------
    pd_at_r_detect : Pd at the node's nominal r_detect. The handoff calls
        r_detect the *reliable* range, so 0.9 is the default anchor.
    pd_max : asymptotic close-range Pd for the logistic model (blind zones,
        eclipsing and processing losses keep it below 1).
    rolloff : logistic width as a fraction of r_detect (0.1 -> Pd falls from
        0.9 to 0.1 over ~0.44 r_detect).
    pfa : per-look false-alarm probability for the Swerling curve; sets its
        steepness. 1e-6 is a conventional CFAR design point.
    """

    kind: str = "logistic"
    pd_at_r_detect: float = 0.9
    pd_max: float = 0.98
    rolloff: float = 0.1
    pfa: float = 1e-6

    def r50(self, r_detect: float) -> float:
        """Range at which the logistic Pd equals pd_max/2."""
        w = self.rolloff * r_detect
        # pd_at = pd_max / (1 + exp((r_detect - r50)/w))
        #   ->  r50 = r_detect - w * ln(pd_max/pd_at - 1)
        return r_detect - w * np.log(self.pd_max / self.pd_at_r_detect - 1.0)

    def snr_ref(self) -> float:
        """SNR (linear) at r_detect that yields pd_at_r_detect."""
        # Pd = Pfa^(1/(1+SNR))  ->  1 + SNR = ln(Pfa) / ln(Pd)
        return np.log(self.pfa) / np.log(self.pd_at_r_detect) - 1.0

    def pd(self, rng_m: np.ndarray, r_detect: float) -> np.ndarray:
        rng_m = np.asarray(rng_m, dtype=float)
        if self.kind == "hard":
            return np.where(rng_m <= r_detect, self.pd_at_r_detect, 0.0)
        if self.kind == "logistic":
            w = self.rolloff * r_detect
            z = np.clip((rng_m - self.r50(r_detect)) / w, -60, 60)
            return self.pd_max / (1.0 + np.exp(z))
        if self.kind == "swerling1":
            with np.errstate(divide="ignore", invalid="ignore"):
                snr = self.snr_ref() * (r_detect / np.maximum(rng_m, 1.0)) ** 4
                return self.pfa ** (1.0 / (1.0 + snr))
        raise ValueError(f"unknown detection model kind {self.kind!r}")


# --------------------------------------------------------------------------- #
# Tracker: revisit and M-of-N confirmation
# --------------------------------------------------------------------------- #


@dataclass(frozen=True)
class TrackerModel:
    """Revisit interval and M-of-N track confirmation with central fusion.

    revisit_s : time between successive looks at a given direction. A fixed
        sector with electronic steering can revisit quickly; 1 s is a
        conservative default for a small array scanning a 90° sector.
    m_of_n : (M, N). A track is confirmed at the first look where at least M
        of the last N looks produced a detection. 3-of-4 is a common
        initiation rule. (1, 1) confirms on first detection.
    fusion : "central" (default) — a detection from any available node
        counts toward one fused track. Level 5 will add per-node tracks,
        association and handoff.
    """

    revisit_s: float = 1.0
    m_of_n: tuple[int, int] = (3, 4)
    fusion: str = "central"


# --------------------------------------------------------------------------- #
# Latency chain
# --------------------------------------------------------------------------- #


@dataclass(frozen=True)
class LatencyModel:
    """End-to-end latency after track confirmation, as the sum of independent
    lognormal stages. Each stage is given as (median_s, sigma_ln). Defaults
    are placeholders to be replaced with measured values; they are chosen so
    the total has a median near 20 s, which is a plausible figure for a
    confirmed track reaching an ATAK operator and being acted on.

    Stages: processing, network transport, CoT/ATAK rendering, operator
    orientation + decision, action initiation.
    """

    stages: tuple[tuple[float, float], ...] = (
        (1.0, 0.3),    # processing / track output
        (2.0, 0.6),    # network transport (mesh radio, retries)
        (1.0, 0.3),    # CoT message -> ATAK render
        (12.0, 0.5),   # operator orientation + decision
        (3.0, 0.5),    # action initiation
    )

    def sample(self, n: int, rng: np.random.Generator) -> np.ndarray:
        total = np.zeros(n)
        for med, sig in self.stages:
            if med <= 0.0:
                continue
            total += rng.lognormal(mean=np.log(med), sigma=sig, size=n)
        return total

    def median(self) -> float:
        return float(sum(m for m, _ in self.stages))


# --------------------------------------------------------------------------- #
# False alerts and PPV
# --------------------------------------------------------------------------- #


@dataclass(frozen=True)
class FalseAlertModel:
    """Operator-level false-alert bookkeeping.

    false_tracks_per_node_hour : rate of *confirmed* false tracks per node per
        hour after M-of-N logic, in the assumed environment. This is a Level 3
        output (clutter, CFAR, birds, vehicles); at Level 2 it is an input to
        sweep. 2/h is a placeholder.
    threat_arrivals_per_hour : assumed true-threat rate during the vignette,
        used only to compute positive predictive value (PPV).
    """

    false_tracks_per_node_hour: float = 2.0
    threat_arrivals_per_hour: float = 0.5

    def system_rate(self, n_nodes_available: float) -> float:
        return self.false_tracks_per_node_hour * n_nodes_available

    def ppv(self, n_nodes_available: float, p_detect: float) -> float:
        tp = self.threat_arrivals_per_hour * p_detect
        fp = self.system_rate(n_nodes_available)
        return tp / (tp + fp) if (tp + fp) > 0 else float("nan")


# --------------------------------------------------------------------------- #
# Availability
# --------------------------------------------------------------------------- #


@dataclass(frozen=True)
class AvailabilityModel:
    """Per-node availability at the moment the threat arrives.

    p_node_up : node is powered, positioned and operating (attrition,
        battery, setup failure).
    p_comms_up : node's track output reaches the fusion / C2 point.
    A node contributes only if both hold. Sampled independently per node per
    trial.
    """

    p_node_up: float = 0.9
    p_comms_up: float = 0.95

    def sample(self, n_trials: int, n_nodes: int,
               rng: np.random.Generator) -> np.ndarray:
        up = rng.random((n_trials, n_nodes)) < self.p_node_up
        comms = rng.random((n_trials, n_nodes)) < self.p_comms_up
        return up & comms


# --------------------------------------------------------------------------- #
# Threat prior
# --------------------------------------------------------------------------- #


@dataclass(frozen=True)
class ThreatPrior:
    """Distribution over closure speed and approach bearing.

    speed : (low, high) uniform in m/s. Handoff band is 10–50 m/s; the
        baseline point case is 30 m/s.
    bearing : (low, high) uniform in degrees, relative to the expected axis.
        (0, 0) is the head-on point case; (-30, 30) is a corridor prior.
    """

    speed: tuple[float, float] = (30.0, 30.0)
    bearing: tuple[float, float] = (0.0, 0.0)

    def sample(self, n: int, rng: np.random.Generator):
        v = rng.uniform(self.speed[0], self.speed[1], n)
        b = rng.uniform(self.bearing[0], self.bearing[1], n)
        return v, b


@dataclass
class Level2Config:
    detection: DetectionModel = field(default_factory=DetectionModel)
    tracker: TrackerModel = field(default_factory=TrackerModel)
    latency: LatencyModel = field(default_factory=LatencyModel)
    false_alerts: FalseAlertModel = field(default_factory=FalseAlertModel)
    availability: AvailabilityModel = field(default_factory=AvailabilityModel)
    threat: ThreatPrior = field(default_factory=ThreatPrior)
    t_required: float = 300.0
    r_action: float = 0.0
