"""Level 3 checks: radar-equation scaling, detection anchor, clutter, integration."""

import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from cuas_l1 import Node  # noqa: E402
from cuas_l2 import Level2Config, simulate  # noqa: E402
from cuas_l3 import RadarParams, ClutterModel, PhysicsDetectionModel  # noqa: E402
from dataclasses import replace  # noqa: E402


def test_snr_follows_inverse_fourth_power():
    r = RadarParams()
    s1 = r.snr(1000.0, 0.03)
    s2 = r.snr(2000.0, 0.03)
    assert abs((s1 / s2) - 16.0) < 1e-6           # doubling range -> 1/16 SNR


def test_snr_linear_in_rcs_and_power():
    r = RadarParams()
    assert abs(r.snr(1500.0, 0.06) / r.snr(1500.0, 0.03) - 2.0) < 1e-9
    r2 = replace(r, peak_power_w=40.0)
    assert abs(r2.snr(1500.0, 0.03) / r.snr(1500.0, 0.03) - 2.0) < 1e-9


def test_gain_matches_aperture_formula():
    r = RadarParams()
    d = r.element_spacing_wl * r.wavelength
    A = (r.n_az * d) * (r.n_el * d)
    g = 4 * np.pi * A * r.aperture_efficiency / r.wavelength**2
    assert abs(r.gain - g) < 1e-6
    assert 20 < r.gain_db < 28                     # sane for a small X-band array


def test_pd_swerling_anchor_and_monotonic():
    r = RadarParams()
    # Pd = Pfa at SNR 0, -> 1 as SNR -> inf
    assert abs(r.pd_from_snr(0.0) - r.pfa) < 1e-12
    assert r.pd_from_snr(1e6) > 0.999
    rng = np.linspace(200, 5000, 60)
    pd = r.pd(rng, 0.03)
    assert np.all(np.diff(pd) <= 1e-9)             # decreasing with range


def test_reliable_range_increases_with_rcs():
    r = RadarParams()
    rr = [r.reliable_range(s) for s in (0.01, 0.03, 0.1)]
    assert rr[0] < rr[1] < rr[2]
    assert all(500 < x < 4000 for x in rr)         # plausible band for placeholders


def test_integration_gain_raises_reliable_range():
    r1 = replace(RadarParams(), cpi_pulses=1)
    r2 = replace(RadarParams(), cpi_pulses=256)
    assert r2.reliable_range(0.03) > r1.reliable_range(0.03)


def test_clutter_never_increases_pd():
    r = RadarParams()
    cl = ClutterModel(grazing_deg=2.0)
    rng = np.linspace(200, 4000, 50)
    for lc in (1, 2, 4, 5):
        assert np.all(r.pd(rng, 0.03, cl, lc) <= r.pd(rng, 0.03) + 1e-9)


def test_trees_worse_than_bare_under_clutter():
    r = RadarParams()
    cl = ClutterModel(grazing_deg=5.0)
    assert r.reliable_range(0.03, cl, 4) < r.reliable_range(0.03, cl, 1)   # trees < bare


def test_physics_model_plugs_into_level2():
    r = RadarParams()
    det = PhysicsDetectionModel(r, rcs_m2=0.1)
    rr = det.reliable_range()
    cfg = replace(Level2Config(), detection=det)
    # node placed so total depth = 9 km at its physics reliable range
    node = Node(x=9000 - rr, r_detect=rr, sector_width=90)
    res = simulate([node], cfg, 4000)
    assert 0.0 <= res.p_meet <= 1.0
    assert res.p_track > 0.0                        # it does detect something


def test_pd_signature_matches_level2_hook():
    # Level 2 calls detection.pd(rng, r_detect); physics model must accept it
    det = PhysicsDetectionModel(RadarParams(), rcs_m2=0.03)
    a = det.pd(np.array([1500.0, 2000.0]), r_detect=3000.0)
    b = det.pd(np.array([1500.0, 2000.0]))
    assert np.allclose(a, b)                         # r_detect ignored by physics
