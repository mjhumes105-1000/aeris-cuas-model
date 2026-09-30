"""Hand-checkable tests for the Level 1 geometry. Run: python -m pytest -q"""

import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from cuas_l1 import (ARCHITECTURE_CASES, BASELINE_REQ, Node, Threat,  # noqa: E402
                     WarningRequirement, coverage_vs_bearing, first_detection_range,
                     power_aperture_proxy, r_detect_min_headon, radar_horizon,
                     warning_depth_required, warning_time, warning_time_headon)


def test_handoff_table_reproduced():
    expected = [300.0, 300.0, 300.0, 200.0 / 3.0]  # 2 km / 30 m/s = 66.7 s
    for case, exp in zip(ARCHITECTURE_CASES, expected):
        t = float(warning_time_headon(case.d_forward, case.r_detect, 30.0))
        assert abs(t - exp) < 1e-9, case.name


def test_required_depth_9km():
    assert warning_depth_required(30.0, 300.0) == 9000.0


def test_r_detect_min_inverts_warning_time():
    for d in (0.0, 2500.0, 6000.0):
        r = float(r_detect_min_headon(d, 30.0, 300.0, t_latency=20.0, r_action=500.0))
        t = float(warning_time_headon(d, r, 30.0, t_latency=20.0, r_action=500.0))
        assert abs(t - 300.0) < 1e-9


def test_latency_and_buffer_reduce_warning():
    base = float(warning_time_headon(6000.0, 3000.0, 30.0))
    lat = float(warning_time_headon(6000.0, 3000.0, 30.0, t_latency=30.0))
    buf = float(warning_time_headon(6000.0, 3000.0, 30.0, r_action=900.0))
    assert abs(base - lat - 30.0) < 1e-9
    assert abs(base - buf - 30.0) < 1e-9  # 900 m at 30 m/s = 30 s


def test_general_geometry_matches_closed_form_headon():
    node = Node(x=6000.0, r_detect=3000.0, sector_width=90.0)
    d = first_detection_range(Threat(speed=30.0, bearing=0.0), [node])
    assert abs(d - 9000.0) < 1e-3
    t = warning_time(Threat(speed=30.0, bearing=0.0), [node], BASELINE_REQ)
    assert abs(t - 300.0) < 1e-6


def test_offaxis_entry_range_matches_analytic_chord():
    """Entry range from the origin, for a node at (D,0) and a threat on a ray at
    bearing theta: rho = D cos(theta) + sqrt(R^2 - D^2 sin^2(theta))."""
    D, R, th = 6000.0, 3000.0, 20.0
    node = Node(x=D, r_detect=R, sector_width=360.0)
    d = first_detection_range(Threat(speed=30.0, bearing=th), [node])
    s, c = np.sin(np.deg2rad(th)), np.cos(np.deg2rad(th))
    rho = D * c + np.sqrt(R**2 - (D * s) ** 2)
    assert abs(d - rho) < 1e-3


def test_threat_missing_the_disc_is_never_detected():
    # sin(theta) > R/D = 0.5  ->  theta > 30 deg misses a 3 km disc 6 km out
    node = Node(x=6000.0, r_detect=3000.0, sector_width=360.0)
    assert first_detection_range(Threat(speed=30.0, bearing=35.0), [node]) == 0.0
    assert warning_time(Threat(speed=30.0, bearing=35.0), [node], BASELINE_REQ) == -np.inf


def test_sector_restricts_coverage_relative_to_omni():
    bearings = np.arange(-60, 60.5, 0.5)
    omni = coverage_vs_bearing([Node(x=6000, r_detect=3000, sector_width=360)],
                               30.0, BASELINE_REQ, bearings)
    sec = coverage_vs_bearing([Node(x=6000, r_detect=3000, sector_width=90)],
                              30.0, BASELINE_REQ, bearings)
    seen_omni = np.isfinite(omni.t_warning).sum()
    seen_sec = np.isfinite(sec.t_warning).sum()
    assert 0 < seen_sec < seen_omni
    # where both see the threat, the warning time is identical (same disc)
    both = np.isfinite(omni.t_warning) & np.isfinite(sec.t_warning)
    assert np.allclose(omni.t_warning[both], sec.t_warning[both])


def test_node_at_origin_omni_sees_all_bearings_equally():
    node = Node(x=0.0, r_detect=2000.0, sector_width=360.0)
    res = coverage_vs_bearing([node], 30.0, BASELINE_REQ, np.arange(-180, 180, 15.0))
    assert np.allclose(res.depth, 2000.0)


def test_multiple_nodes_take_the_max_depth():
    near = Node(x=0.0, r_detect=2000.0, sector_width=360.0)
    far = Node(x=6000.0, r_detect=3000.0, sector_width=90.0)
    d = first_detection_range(Threat(speed=30.0, bearing=0.0), [near, far])
    assert abs(d - 9000.0) < 1e-3


def test_power_aperture_fourth_power():
    assert abs(float(power_aperture_proxy(9000.0)) - 81.0) < 1e-9
    assert abs(float(power_aperture_proxy(3000.0)) - 1.0) < 1e-9


def test_radar_horizon_sanity():
    # 2 m mast, 30 m AGL target: roughly 5.8 + 22.6 = ~28 km with 4/3 earth
    h = radar_horizon(2.0, 30.0)
    assert 26_000 < h < 30_000


def test_requirement_dataclass_defaults():
    req = WarningRequirement()
    assert req.t_required == 300.0 and req.t_latency == 0.0 and req.r_action == 0.0
