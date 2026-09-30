"""Level 2 checks: Level 1 limit, monotonic behaviours, and model anchors."""

import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from cuas_l1 import ARCHITECTURE_CASES, Node  # noqa: E402
from cuas_l2 import (AvailabilityModel, DetectionModel, LatencyModel,  # noqa: E402
                     Level2Config, ThreatPrior, TrackerModel, simulate)

IDEAL = Level2Config(detection=DetectionModel(kind="hard", pd_at_r_detect=1.0),
                     tracker=TrackerModel(revisit_s=0.25, m_of_n=(1, 1)),
                     latency=LatencyModel(stages=()),
                     availability=AvailabilityModel(1.0, 1.0))


def test_level1_limit_reproduces_handoff_table():
    expected = [300.0, 300.0, 300.0, 200.0 / 3.0]
    for case, exp in zip(ARCHITECTURE_CASES, expected):
        r = simulate([case.node(90)], IDEAL, n_trials=500)
        # discrete revisit -> confirmation up to one look late (0.25 s * 30 m/s = 7.5 m)
        assert np.all(np.abs(r.t_warning - exp) <= 0.26), case.name


def test_logistic_anchor_and_shape():
    d = DetectionModel(kind="logistic", pd_at_r_detect=0.9, pd_max=0.98, rolloff=0.1)
    assert abs(float(d.pd(np.array([3000.0]), 3000.0)[0]) - 0.9) < 1e-9
    pd = d.pd(np.linspace(500, 6000, 50), 3000.0)
    assert np.all(np.diff(pd) <= 1e-12)          # monotone decreasing
    assert pd[-1] < 1e-3 and pd[0] > 0.97


def test_swerling_anchor():
    d = DetectionModel(kind="swerling1", pd_at_r_detect=0.9, pfa=1e-6)
    assert abs(float(d.pd(np.array([3000.0]), 3000.0)[0]) - 0.9) < 1e-9


def test_latency_subtracts_directly():
    cfg = Level2Config(detection=DetectionModel(kind="hard", pd_at_r_detect=1.0),
                       tracker=TrackerModel(revisit_s=0.25, m_of_n=(1, 1)),
                       latency=LatencyModel(stages=((30.0, 1e-9),)),
                       availability=AvailabilityModel(1.0, 1.0))
    r = simulate([ARCHITECTURE_CASES[1].node(90)], cfg, 300)
    assert np.all(np.abs(r.t_warning - 270.0) <= 0.3)


def test_m_of_n_delays_confirmation():
    base = Level2Config(detection=DetectionModel(kind="hard", pd_at_r_detect=1.0),
                        latency=LatencyModel(stages=()), availability=AvailabilityModel(1.0, 1.0))
    node = ARCHITECTURE_CASES[1].node(90)
    r11 = simulate([node], Level2Config(**{**base.__dict__, "tracker": TrackerModel(1.0, (1, 1))}), 200)
    r34 = simulate([node], Level2Config(**{**base.__dict__, "tracker": TrackerModel(1.0, (3, 4))}), 200)
    # 3-of-4 with Pd=1 confirms exactly 2 looks (2 s) after 1-of-1
    assert np.allclose(r11.t_warning - r34.t_warning, 2.0, atol=1e-6)


def test_availability_caps_track_probability():
    cfg = Level2Config(availability=AvailabilityModel(p_node_up=0.5, p_comms_up=1.0))
    r = simulate([ARCHITECTURE_CASES[0].node(90)], cfg, 20_000)
    assert abs(r.p_track - 0.5) < 0.02


def test_never_detected_when_out_of_sector():
    node = Node(x=6000, r_detect=3000, sector_width=30, boresight=0)
    cfg = Level2Config(threat=ThreatPrior(bearing=(60.0, 60.0)),
                       availability=AvailabilityModel(1.0, 1.0))
    r = simulate([node], cfg, 500)
    assert r.p_track == 0.0 and np.all(r.t_warning == -np.inf)


def test_more_nodes_do_not_reduce_track_probability():
    cfg = Level2Config(threat=ThreatPrior(bearing=(-30.0, 30.0)))
    one = simulate([Node(x=6000, r_detect=3000, sector_width=90)], cfg, 8_000)
    two = simulate([Node(x=6000, r_detect=3000, sector_width=90)] * 2, cfg, 8_000)
    assert two.p_track >= one.p_track - 0.01


def test_seed_reproducible():
    node = ARCHITECTURE_CASES[1].node(90)
    a = simulate([node], Level2Config(), 2_000, seed=7)
    b = simulate([node], Level2Config(), 2_000, seed=7)
    assert np.array_equal(a.t_warning, b.t_warning)
