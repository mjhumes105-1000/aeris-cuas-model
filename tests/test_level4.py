"""Level 4 checks: horizon, masking, flat-earth reduction to Level 2, DEM loader."""

import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from cuas_l1 import Node, radar_horizon  # noqa: E402
from cuas_l2 import Level2Config, simulate  # noqa: E402
from cuas_l4 import Terrain, viewshed, coverage_by_landcover  # noqa: E402


def flat(half=20000, dx=100):
    n = int(2 * half / dx) + 1
    return Terrain(z=np.zeros((n, n)), dx=dx, x0=-half, y0=-half)


def test_flat_earth_radar_horizon():
    vs = viewshed(flat(), (0, 0), h_obs=2.0, h_tgt=30.0, max_range=40_000, n_az=8, ds=25.0)
    first_hidden = vs.s[np.argmin(vs.visible[0])]
    assert abs(first_hidden - radar_horizon(2.0, 30.0)) < 150.0


def test_flat_earth_fully_visible_inside_horizon():
    vs = viewshed(flat(), (0, 0), 2.0, 30.0, 6000, n_az=36)
    assert vs.visible.all()


def test_wall_masks_everything_behind_it():
    t = flat(half=5000, dx=25)
    t.z[:, t.x > 1000] = 200.0          # 200 m cliff at x = 1 km
    vs = viewshed(t, (0, 0), 2.0, 30.0, 4000, n_az=4)
    i0 = 0                               # azimuth 0 = +x
    s = vs.s
    assert vs.visible[i0][s < 1000].all()
    # target at 30 m AGL on top of the cliff (230 m) is visible; but a point
    # just past the cliff edge on the plateau is visible too (it is the crest)
    assert vs.visible[i0][(s > 1000) & (s < 1050)].all()
    # looking the other way (-x) nothing blocks
    assert vs.visible[2].all()


def test_valley_behind_ridge_is_masked():
    t = flat(half=5000, dx=25)
    t.z[:, (t.x > 1000) & (t.x < 1100)] = 200.0   # thin ridge
    vs = viewshed(t, (0, 0), 2.0, 30.0, 4000, n_az=4)
    s = vs.s
    behind = (s > 1200) & (s < 2500)
    assert not vs.visible[0][behind].any()
    # a high-flying target reappears while its elevation angle beats the crest:
    # crest angle ~ (200-2)/1000 = 0.198 -> a 400 m target is seen out to ~2.0 km
    vs2 = viewshed(t, (0, 0), 2.0, 400.0, 4000, n_az=4)
    assert vs2.visible[0][(s > 1200) & (s < 1900)].all()
    assert not vs2.visible[0][(s > 2200) & (s < 2500)].any()


def test_flat_terrain_reduces_to_level2():
    node = Node(x=6000, r_detect=3000, sector_width=90)
    cfg = Level2Config()
    vs = viewshed(flat(), (6000, 0), 2.0, 30.0, 4800)
    a = simulate([node], cfg, 3000, seed=1)
    b = simulate([node], cfg, 3000, seed=1, visibility=[vs])
    assert np.array_equal(a.t_warning, b.t_warning)


def test_masked_node_never_tracks():
    t = flat(half=8000, dx=25)
    t.z[:, t.x > 6300] = 300.0        # wall right in front of the node
    node = Node(x=6000, r_detect=3000, sector_width=90)
    vs = viewshed(t, (6000, 0), 2.0, 30.0, 4800)
    r = simulate([node], Level2Config(), 500, visibility=[vs])
    # threat is only visible for the last 300 m before the wall -> far too late
    assert r.p_meet == 0.0


def test_synthetic_beach_shape_and_landcover():
    t = Terrain.synthetic_beach(half_size_m=9000, dx=50)
    assert t.z[:, t.x < 0].max() == 0.0                # sea
    assert (t.landcover[:, t.x < 0] == 0).all()        # water class
    assert t.z.max() > 100.0                           # a ridge exists
    vs = viewshed(t, (2000, 0), 2.0, 30.0, 3000)
    shares = coverage_by_landcover(t, vs, 3000, 90, 0)
    assert abs(sum(shares.values()) - 1.0) < 1e-6


def test_geotiff_loader_roundtrip(tmp_path):
    rasterio = __import__("rasterio")
    from rasterio.transform import from_origin
    # 0.02° tile at 1 arc-sec-ish spacing with a known east-west ramp
    n = 200
    lon0, lat0, res = -117.5, 33.3, 0.0001
    lon = lon0 + res * np.arange(n)
    Z = np.tile(((lon - lon0) * 111_320 * np.cos(np.deg2rad(33.29))) * 0.05, (n, 1)).astype("float32")
    p = tmp_path / "t.tif"
    with rasterio.open(p, "w", driver="GTiff", height=n, width=n, count=1, dtype="float32",
                       crs="EPSG:4326", transform=from_origin(lon0, lat0, res, res)) as dst:
        dst.write(Z, 1)
    t = Terrain.from_geotiff(p, lon0 + res * n / 2, lat0 - res * n / 2, half_size_m=600,
                             dx=30, axis_bearing_deg=90)
    # +x is east: elevation must rise with x at ~0.05 m/m
    g = np.gradient(t.z.mean(axis=0), t.dx).mean()
    assert abs(g - 0.05) < 0.005
