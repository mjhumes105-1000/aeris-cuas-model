"""
Level 4 terrain: elevation grids, land cover, and line-of-sight.

A `Terrain` is a regular grid of ground elevation (m MSL) on a local
east-north frame in metres, plus an optional land-cover class grid. It can be
built from a public GeoTIFF DEM (Copernicus GLO-30, USGS 3DEP, SRTM) or from
a synthetic beach used for development and for parametric sweeps.

Line of sight uses a polar viewshed: from an observer at (x, y) with antenna
height h_obs AGL, rays are marched out to max_range on n_az azimuths, and a
target at h_tgt AGL is visible at a point if its elevation angle is at least
the running maximum of terrain elevation angles along that ray. Earth
curvature and standard refraction are included with the 4/3-earth model.

Conventions match Levels 1-2: +x is the expected threat axis (inland for the
beach vignette), +y is left of it, metres throughout.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path

import numpy as np
from scipy.ndimage import gaussian_filter, map_coordinates

R_EARTH_EFF = 6_371_000.0 * 4.0 / 3.0

# Land-cover classes used for clutter bookkeeping. Codes are ours; loaders map
# external products (ESA WorldCover, NLCD) onto them.
LC_WATER, LC_BARE, LC_GRASS, LC_SHRUB, LC_TREES, LC_BUILT, LC_WETLAND = range(7)
LC_NAMES = {LC_WATER: "water", LC_BARE: "bare/sand", LC_GRASS: "grass", LC_SHRUB: "shrub",
            LC_TREES: "trees", LC_BUILT: "built-up", LC_WETLAND: "wetland"}
ESA_WORLDCOVER_MAP = {10: LC_TREES, 20: LC_SHRUB, 30: LC_GRASS, 40: LC_GRASS, 50: LC_BUILT,
                      60: LC_BARE, 70: LC_BARE, 80: LC_WATER, 90: LC_WETLAND, 95: LC_WETLAND,
                      100: LC_GRASS}


@dataclass
class Terrain:
    z: np.ndarray                 # (ny, nx) ground elevation, m MSL
    dx: float                     # grid spacing, m
    x0: float = 0.0               # x of column 0
    y0: float = 0.0               # y of row 0
    landcover: np.ndarray | None = None
    name: str = "terrain"
    meta: dict = field(default_factory=dict)

    # ---- geometry -----------------------------------------------------------
    @property
    def nx(self): return self.z.shape[1]
    @property
    def ny(self): return self.z.shape[0]
    @property
    def x(self): return self.x0 + self.dx * np.arange(self.nx)
    @property
    def y(self): return self.y0 + self.dx * np.arange(self.ny)
    @property
    def extent(self):
        return (self.x[0], self.x[-1], self.y[0], self.y[-1])

    def _idx(self, x, y):
        return (np.asarray(y, float) - self.y0) / self.dx, (np.asarray(x, float) - self.x0) / self.dx

    def elevation(self, x, y) -> np.ndarray:
        """Bilinear ground elevation at arbitrary (x, y); edge-clamped."""
        r, c = self._idx(x, y)
        return map_coordinates(self.z, [np.atleast_1d(r), np.atleast_1d(c)], order=1,
                               mode="nearest").reshape(np.shape(x))

    def landcover_at(self, x, y) -> np.ndarray:
        if self.landcover is None:
            return np.full(np.shape(x), -1)
        r, c = self._idx(x, y)
        return map_coordinates(self.landcover, [np.atleast_1d(r), np.atleast_1d(c)], order=0,
                               mode="nearest").reshape(np.shape(x))

    def slope_deg(self) -> np.ndarray:
        gy, gx = np.gradient(self.z, self.dx)
        return np.degrees(np.arctan(np.hypot(gx, gy)))

    # ---- constructors ---------------------------------------------------------
    @classmethod
    def from_geotiff(cls, path: str | Path, center_lon: float, center_lat: float,
                     half_size_m: float = 8000.0, dx: float = 30.0,
                     axis_bearing_deg: float = 90.0, landcover_path: str | Path | None = None,
                     name: str | None = None) -> "Terrain":
        """Crop a geographic DEM around (lon, lat) onto a local metre grid.

        axis_bearing_deg : compass bearing (0 = N, 90 = E) that becomes the
            +x (threat) axis. For a west-facing beach with threats from inland,
            use 90.
        Uses an equirectangular local projection, accurate to well under 1 %
        over 20 km, which is far below DEM error.
        """
        import rasterio
        from rasterio.windows import from_bounds

        deg_lat = 1.0 / 111_320.0
        deg_lon = deg_lat / np.cos(np.deg2rad(center_lat))
        pad = half_size_m * 1.5
        with rasterio.open(path) as src:
            win = from_bounds(center_lon - pad * deg_lon, center_lat - pad * deg_lat,
                              center_lon + pad * deg_lon, center_lat + pad * deg_lat,
                              src.transform)
            arr = src.read(1, window=win).astype(float)
            tr = src.window_transform(win)
            nod = src.nodata
        if nod is not None:
            arr[arr == nod] = np.nan
        arr = np.where(np.isnan(arr), 0.0, arr)

        n = int(round(2 * half_size_m / dx)) + 1
        xs = (np.arange(n) - n // 2) * float(dx)
        X, Y = np.meshgrid(xs, xs)
        # rotate local (x along axis, y left of axis) to east/north
        b = np.deg2rad(axis_bearing_deg)
        east = X * np.sin(b) - Y * np.cos(b)
        north = X * np.cos(b) + Y * np.sin(b)
        lon = center_lon + east * deg_lon
        lat = center_lat + north * deg_lat
        col = (lon - tr.c) / tr.a
        row = (lat - tr.f) / tr.e
        z = map_coordinates(arr, [row, col], order=1, mode="nearest")

        lc = None
        if landcover_path is not None:
            with rasterio.open(landcover_path) as lsrc:
                lwin = from_bounds(center_lon - pad * deg_lon, center_lat - pad * deg_lat,
                                   center_lon + pad * deg_lon, center_lat + pad * deg_lat,
                                   lsrc.transform)
                larr = lsrc.read(1, window=lwin)
                ltr = lsrc.window_transform(lwin)
            lcol = (lon - ltr.c) / ltr.a
            lrow = (lat - ltr.f) / ltr.e
            raw = map_coordinates(larr, [lrow, lcol], order=0, mode="nearest")
            lc = np.vectorize(lambda v: ESA_WORLDCOVER_MAP.get(int(v), LC_GRASS))(raw)
        # Sea-level water mask if no land cover: z <= 0.5 m
        if lc is None:
            lc = np.where(z <= 0.5, LC_WATER, LC_GRASS)
        return cls(z=z, dx=dx, x0=xs[0], y0=xs[0], landcover=lc,
                   name=name or Path(path).stem,
                   meta={"center_lon": center_lon, "center_lat": center_lat,
                         "axis_bearing_deg": axis_bearing_deg, "source": str(path)})

    @classmethod
    def synthetic_beach(cls, half_size_m: float = 8000.0, dx: float = 30.0,
                        seed: int = 3, dune_height: float = 6.0, ridge_height: float = 220.0,
                        ridge_x: float = 6500.0, valley: bool = True) -> "Terrain":
        """A plausible west-facing training beach.

        Sea for x < 0 (defended point is on the beach at the origin), a dune
        line at ~300 m, a coastal plain rising ~1 %, a river valley cutting
        the plain at y ≈ +1.5 km, a foothill ridge at ridge_x with a saddle,
        and random knolls. Threats come from +x (inland).
        """
        rng = np.random.default_rng(seed)
        n = int(round(2 * half_size_m / dx)) + 1
        xs = (np.arange(n) - n // 2) * float(dx)
        X, Y = np.meshgrid(xs, xs)

        z = np.zeros_like(X, dtype=float)
        land = X > 0
        # beach slope 2 % for first 150 m, then dune
        z += np.where(land, np.clip(X, 0, 150) * 0.02, 0.0)
        z += dune_height * np.exp(-((X - 320.0) / 90.0) ** 2) * land
        # coastal plain ~1 % grade with gentle undulation
        z += np.where(land, np.clip(X - 400.0, 0, None) * 0.010, 0.0)
        z += 4.0 * np.sin(Y / 900.0) * np.sin(X / 1300.0) * land
        # foothill ridge with saddle at y ~ -1.2 km
        ridge = ridge_height * np.exp(-((X - ridge_x) / 900.0) ** 2)
        ridge *= 1.0 - 0.55 * np.exp(-((Y + 1200.0) / 700.0) ** 2)
        ridge *= 1.0 + 0.35 * np.sin(Y / 1500.0)
        z += ridge * land
        # everything behind the ridge is higher ground
        z += np.where(X > ridge_x, np.clip(X - ridge_x, 0, None) * 0.02, 0.0)
        # river valley
        if valley:
            vy = 1500.0 + 300.0 * np.sin(X / 2500.0)
            cut = 0.6 * np.exp(-((Y - vy) / 220.0) ** 2) * np.clip(z - 3.0, 0, None)
            z -= cut * land
        # knolls
        for _ in range(12):
            kx = rng.uniform(1200, half_size_m - 800)
            ky = rng.uniform(-half_size_m + 800, half_size_m - 800)
            z += rng.uniform(8, 30) * np.exp(-(((X - kx) ** 2 + (Y - ky) ** 2) / rng.uniform(250, 500) ** 2)) * land
        z = gaussian_filter(z, sigma=1.0)
        z[~land] = 0.0

        # land cover by simple rules
        lc = np.full_like(z, LC_GRASS, dtype=int)
        lc[~land] = LC_WATER
        lc[land & (X < 380)] = LC_BARE
        slope = np.degrees(np.arctan(np.hypot(*np.gradient(z, dx)[::-1])))
        lc[land & (X > 380) & (slope > 8)] = LC_SHRUB
        lc[land & (X > 380) & (z > 60) & (slope > 12)] = LC_TREES
        if valley:
            lc[land & (np.abs(Y - vy) < 260) & (X > 600)] = LC_TREES   # riparian corridor
        # a small built-up compound on the plain
        lc[land & (np.abs(X - 3200) < 250) & (np.abs(Y + 2600) < 200)] = LC_BUILT
        return cls(z=z, dx=dx, x0=xs[0], y0=xs[0], landcover=lc, name="synthetic-beach",
                   meta={"seed": seed, "dune_height": dune_height, "ridge_height": ridge_height,
                         "ridge_x": ridge_x})


# --------------------------------------------------------------------------- #
# Viewshed
# --------------------------------------------------------------------------- #


@dataclass
class Viewshed:
    """Polar visibility table from one observer."""
    obs_xy: tuple[float, float]
    h_obs: float                 # antenna height AGL, m
    h_tgt: float                 # target height AGL, m
    max_range: float
    az: np.ndarray               # (n_az,) degrees, bearing from +x CCW
    s: np.ndarray                # (n_s,) range samples, m
    visible: np.ndarray          # (n_az, n_s) bool

    def __call__(self, x, y) -> np.ndarray:
        """Visibility at arbitrary points (nearest polar cell). Beyond
        max_range -> False."""
        x = np.asarray(x, float); y = np.asarray(y, float)
        dx = x - self.obs_xy[0]; dy = y - self.obs_xy[1]
        r = np.hypot(dx, dy)
        a = np.degrees(np.arctan2(dy, dx)) % 360.0
        ia = np.rint(a / (360.0 / len(self.az))).astype(int) % len(self.az)
        ds = self.s[1] - self.s[0]
        i_s = np.rint(r / ds).astype(int)
        ok = i_s < len(self.s)
        out = np.zeros(np.shape(x), dtype=bool)
        out[ok] = self.visible[ia[ok], np.clip(i_s[ok], 0, len(self.s) - 1)]
        return out

    def fraction_visible(self, r_max: float | None = None, sector_width: float = 360.0,
                         boresight: float = 0.0) -> float:
        """Area-weighted fraction of the (range, sector) footprint with LOS."""
        r_max = self.max_range if r_max is None else r_max
        m_s = self.s <= r_max
        off = np.abs((self.az - boresight + 180.0) % 360.0 - 180.0)
        m_a = off <= sector_width / 2.0
        w = self.s[m_s]  # annulus area weight ∝ r
        v = self.visible[np.ix_(m_a, m_s)]
        return float((v * w).sum() / (w.sum() * m_a.sum())) if m_a.any() and m_s.any() else 0.0


def viewshed(terrain: Terrain, obs_xy: tuple[float, float], h_obs: float = 2.0,
             h_tgt: float = 30.0, max_range: float = 6000.0, n_az: int = 720,
             ds: float | None = None, k_earth: float = 4.0 / 3.0) -> Viewshed:
    """Polar viewshed with 4/3-earth curvature (radar horizon included).

    A target flying at h_tgt AGL is visible at (az, s) if
        (z_ground(s) + h_tgt - s²/(2 R_eff) - z_obs - h_obs) / s
    is >= the running max over the ray of
        (z_ground(s') - s'²/(2 R_eff) - z_obs - h_obs) / s'.
    """
    ds = terrain.dx / 2.0 if ds is None else ds
    s = np.arange(ds, max_range + ds / 2, ds)
    az = np.arange(n_az) * (360.0 / n_az)
    ca, sa = np.cos(np.deg2rad(az)), np.sin(np.deg2rad(az))
    X = obs_xy[0] + s[None, :] * ca[:, None]
    Y = obs_xy[1] + s[None, :] * sa[:, None]
    zg = terrain.elevation(X, Y)
    z_obs = float(terrain.elevation(obs_xy[0], obs_xy[1])) + h_obs
    r_eff = 6_371_000.0 * k_earth
    drop = s ** 2 / (2.0 * r_eff)
    ang_ground = (zg - drop[None, :] - z_obs) / s[None, :]
    # blocking angle: max of ground angles strictly before s
    block = np.maximum.accumulate(ang_ground, axis=1)
    block_prev = np.concatenate([np.full((n_az, 1), -np.inf), block[:, :-1]], axis=1)
    ang_tgt = (zg + h_tgt - drop[None, :] - z_obs) / s[None, :]
    vis = ang_tgt >= block_prev
    return Viewshed(obs_xy=tuple(map(float, obs_xy)), h_obs=h_obs, h_tgt=h_tgt,
                    max_range=max_range, az=az, s=s, visible=vis)


def coverage_by_landcover(terrain: Terrain, vs: Viewshed, r_max: float,
                          sector_width: float = 360.0, boresight: float = 0.0) -> dict:
    """Fraction of the visible footprint over each land-cover class — the
    clutter environment the node will actually be looking at."""
    m_s = vs.s <= r_max
    off = np.abs((vs.az - boresight + 180.0) % 360.0 - 180.0)
    m_a = off <= sector_width / 2.0
    S, A = np.meshgrid(vs.s[m_s], vs.az[m_a])
    X = vs.obs_xy[0] + S * np.cos(np.deg2rad(A))
    Y = vs.obs_xy[1] + S * np.sin(np.deg2rad(A))
    lc = terrain.landcover_at(X, Y)
    v = vs.visible[np.ix_(m_a, m_s)]
    w = S * v
    tot = w.sum()
    return {LC_NAMES[c]: float(w[lc == c].sum() / tot) if tot > 0 else 0.0
            for c in LC_NAMES}
