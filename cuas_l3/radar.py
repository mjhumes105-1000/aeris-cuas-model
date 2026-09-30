"""
Level 3 radar link budget: physics-based Pd(range) for the sensing node.

This module replaces the Level 2 `DetectionModel`'s empirical logistic curve
with a probability of detection computed from the radar range equation for a
specific array, waveform, target RCS, and clutter environment. It exposes the
SAME interface Level 2 expects — a `.pd(range_m, r_detect=None)` method — so a
`PhysicsDetectionModel` drops straight into `Level2Config.detection` and every
Level 2 / Level 4 experiment reruns unchanged. It also provides
`.reliable_range()`, which solves Pd = target for the range the geometry
layers call `r_detect`; i.e. Level 3 *derives* the number Levels 1-2 assumed.

Physics summary
---------------
Single-pulse SNR from the monostatic radar equation:

    SNR_1 = Pt · G_t · G_r · λ² · σ / ( (4π)³ · R⁴ · k · Ts · B · L )

with array gain G from the aperture, Ts = T0·F the system noise temperature,
B ≈ 1/τ the matched-filter bandwidth, and L lumped two-way losses. A coherent
processing interval (CPI) of Np pulses staring at one sector cell integrates
coherently, SNR_cpi = Np · SNR_1; optional non-coherent integration across
Nc CPIs applies an efficiency-reduced factor. Detection uses the Swerling-1
closed form Pd = Pfa^(1/(1+SNR)), which is exact for a fluctuating target
observed as one integrated complex sample and is the SAME formula Level 2's
`swerling1` model used — Level 3 only supplies a physical SNR instead of an
anchored one.

Surface clutter (see `clutter_sinr`) is added as an interference term whose
land-cover class sets both σ⁰ and the achievable MTI/Doppler cancellation
(internal clutter motion — swaying trees — spreads the clutter Doppler and
caps cancellation). This is the physical bridge from the Level 4 land-cover
map to detection performance.

All quantities SI; ranges in metres. Every AERIS-Nexus number below is a
DOCUMENTED PLACEHOLDER, flagged provisional, to be replaced with the frozen
repository specification before proposal. See `AERIS_NEXUS_PROVISIONAL`.
"""

from __future__ import annotations

from dataclasses import dataclass, field, replace

import numpy as np
from scipy.optimize import brentq

K_BOLTZ = 1.380649e-23
T0 = 290.0
C_LIGHT = 299_792_458.0


def db(x):
    return 10.0 * np.log10(x)


def undb(x_db):
    return 10.0 ** (np.asarray(x_db, float) / 10.0)


# --------------------------------------------------------------------------- #
# Radar parameters
# --------------------------------------------------------------------------- #


@dataclass(frozen=True)
class RadarParams:
    """Array, waveform, and receiver parameters.

    DEFAULTS are the AERIS-Nexus *placeholder* set (see module docstring):
    an 8×16 (az×el) half-wavelength X-band array, modest solid-state power,
    concentrated dwell. Replace with frozen repo values before citing.
    """

    # RF / array
    freq_hz: float = 9.5e9            # X-band
    n_az: int = 8                     # elements across azimuth
    n_el: int = 16                    # elements in elevation
    element_spacing_wl: float = 0.5   # λ
    aperture_efficiency: float = 0.6  # illumination + spillover
    # Transmit
    peak_power_w: float = 20.0        # total radiated peak power (all elements)
    pulse_width_s: float = 10e-6      # τ; with pulse compression, matched-filter
                                      # SNR uses pulse ENERGY Pt·τ (bandwidth-free)
    chirp_bandwidth_hz: float = 5e6   # LFM sweep -> range resolution c/(2B) ≈ 30 m
    prf_hz: float = 10_000.0
    # Processing
    cpi_pulses: int = 256             # coherent pulses per dwell (CPI)
    noncoherent_cpi: int = 1          # CPIs integrated non-coherently per look
    noncoherent_efficiency: float = 0.8
    # Receiver / losses
    noise_figure_db: float = 4.0
    system_loss_db: float = 6.0       # two-way: radome, scan, beamshape, CFAR, etc.
    pfa: float = 1e-6
    # Detection target
    pd_reliable: float = 0.9          # Pd that defines "reliable range"

    # ---- derived ----------------------------------------------------------
    @property
    def wavelength(self) -> float:
        return C_LIGHT / self.freq_hz

    @property
    def n_elements(self) -> int:
        return self.n_az * self.n_el

    @property
    def aperture_m2(self) -> float:
        d = self.element_spacing_wl * self.wavelength
        return (self.n_az * d) * (self.n_el * d)

    @property
    def gain(self) -> float:
        """Boresight array gain (linear), aperture formula with efficiency."""
        return 4.0 * np.pi * self.aperture_m2 * self.aperture_efficiency / self.wavelength**2

    @property
    def gain_db(self) -> float:
        return db(self.gain)

    @property
    def range_resolution_m(self) -> float:
        """Compressed range resolution, c / (2·B_chirp). Sizes the clutter cell."""
        return C_LIGHT / (2.0 * self.chirp_bandwidth_hz)

    def beamwidth_az_rad(self) -> float:
        # ~0.886 λ / D for a uniformly illuminated aperture
        return 0.886 * self.wavelength / (self.n_az * self.element_spacing_wl * self.wavelength)

    def beamwidth_el_rad(self) -> float:
        return 0.886 * self.wavelength / (self.n_el * self.element_spacing_wl * self.wavelength)

    @property
    def noise_temp(self) -> float:
        return T0 * undb(self.noise_figure_db)

    # ---- link budget ------------------------------------------------------
    def snr_single(self, rng_m, rcs_m2: float) -> np.ndarray:
        """Single-pulse matched-filter SNR (linear) vs range for a given RCS.

        Energy form: SNR = Pt·τ·G²·λ²·σ / ((4π)³ R⁴ k Ts L). Using pulse
        energy Pt·τ makes this independent of receiver bandwidth (the matched
        filter integrates the whole pulse), so pulse compression improves
        range resolution without changing SNR."""
        rng_m = np.asarray(rng_m, float)
        num = (self.peak_power_w * self.pulse_width_s * self.gain**2
               * self.wavelength**2 * rcs_m2)
        den = ((4 * np.pi) ** 3 * np.maximum(rng_m, 1.0) ** 4
               * K_BOLTZ * self.noise_temp * undb(self.system_loss_db))
        return num / den

    def integration_gain(self) -> float:
        """Combined coherent × non-coherent integration gain (linear)."""
        coh = self.cpi_pulses
        nc = self.noncoherent_cpi
        # non-coherent integration gain ≈ Nc^eff (efficiency 0.7-0.9 typical)
        return coh * nc ** self.noncoherent_efficiency

    def snr(self, rng_m, rcs_m2: float) -> np.ndarray:
        """Integrated SNR (linear) vs range."""
        return self.snr_single(rng_m, rcs_m2) * self.integration_gain()

    # ---- detection --------------------------------------------------------
    def pd_from_snr(self, snr_lin) -> np.ndarray:
        """Swerling-1 detection probability for integrated SNR."""
        snr_lin = np.asarray(snr_lin, float)
        return self.pfa ** (1.0 / (1.0 + np.maximum(snr_lin, 0.0)))

    def pd(self, rng_m, rcs_m2: float = 0.03, clutter=None, terrain_landcover=None) -> np.ndarray:
        """Pd vs range. If a ClutterModel is given, detection uses SINR."""
        if clutter is None:
            return self.pd_from_snr(self.snr(rng_m, rcs_m2))
        sinr = clutter.sinr(self, rng_m, rcs_m2, terrain_landcover)
        return self.pd_from_snr(sinr)

    def reliable_range(self, rcs_m2: float = 0.03, clutter=None, landcover=None,
                       hi: float = 30_000.0) -> float:
        """Range at which Pd = pd_reliable (0 if never reached)."""
        f = lambda R: self.pd(R, rcs_m2, clutter, landcover) - self.pd_reliable
        if f(1.0) < 0:
            return 0.0
        if f(hi) > 0:
            return hi
        return float(brentq(f, 1.0, hi, xtol=1.0))


# Provisional AERIS-Nexus placeholder (identical to defaults; named for clarity
# and so the freeze step is a one-line diff).
AERIS_NEXUS_PROVISIONAL = RadarParams()


# --------------------------------------------------------------------------- #
# Surface clutter
# --------------------------------------------------------------------------- #

# Constant-γ surface backscatter: σ0 = γ · sin(grazing).  γ in dB by land-cover
# class (order matches cuas_l4.terrain LC codes). Provisional X-band values
# drawn from standard clutter tables (Nathanson / Barton ranges).
GAMMA_DB_BY_LC = {
    0: -30.0,   # water (low, but sea state raises it; provisional calm)
    1: -27.0,   # bare / sand
    2: -22.0,   # grass
    3: -18.0,   # shrub
    4: -12.0,   # trees (high backscatter)
    5: -8.0,    # built-up (very high, spiky)
    6: -20.0,   # wetland
}
# Total clutter cancellation of the Doppler processor (improvement factor, dB):
# how far the residual clutter in the target's Doppler bin sits below the raw
# clutter return. Capped by internal clutter motion — rigid surfaces cancel
# deeply, swaying vegetation spreads the clutter Doppler and caps it. This is
# the DOMINANT provisional unknown at Level 3 and is meant to be swept; it
# already includes the coherent-processing gain, so clutter enters as a
# single-pulse C/N (no integration applied) divided by this factor.
MTI_IMPROVEMENT_DB_BY_LC = {
    0: 35.0,    # water: waves decorrelate -> moderate
    1: 55.0,    # bare: rigid -> excellent
    2: 48.0,    # grass
    3: 40.0,    # shrub
    4: 30.0,    # trees: large internal motion -> limited
    5: 45.0,    # built-up: rigid but spiky returns
    6: 38.0,    # wetland
}


@dataclass(frozen=True)
class ClutterModel:
    """Surface-clutter interference at the target cell.

    grazing_deg : grazing angle at the clutter patch (small for a low mast
        looking at a low-altitude target). Provisional single value; a full
        model would compute it per range from terrain.
    default_lc : land-cover class used when none is supplied.
    az_beamwidth_scale, range_gate_m : set the clutter patch size.
    """

    grazing_deg: float = 1.0
    default_lc: int = 2               # grass
    range_gate_m: float = None        # defaults to c·τ/2 from the radar
    internal_motion_floor_db: float = 0.0

    def sigma0(self, lc: int, grazing_rad: float) -> float:
        gamma = undb(GAMMA_DB_BY_LC.get(int(lc), GAMMA_DB_BY_LC[2]))
        return gamma * np.sin(grazing_rad)

    def clutter_patch_area(self, radar: RadarParams, rng_m, grazing_rad: float) -> np.ndarray:
        rng_m = np.asarray(rng_m, float)
        az = radar.beamwidth_az_rad()
        gate = self.range_gate_m or radar.range_resolution_m   # compressed cell
        # beam-limited in azimuth, pulse-limited in range; /cos(grazing) for slant
        return rng_m * az * gate / max(np.cos(grazing_rad), 1e-3)

    def sinr(self, radar: RadarParams, rng_m, rcs_m2: float, lc=None) -> np.ndarray:
        """Signal-to-interference-plus-noise ratio (linear), integrated."""
        rng_m = np.asarray(rng_m, float)
        lc = self.default_lc if lc is None else lc
        grazing = np.deg2rad(self.grazing_deg)
        # Signal gets full coherent+non-coherent integration.
        s = radar.snr(rng_m, rcs_m2)                       # integrated signal / noise
        # Clutter enters as SINGLE-PULSE C/N (no integration) divided by the
        # processor's total improvement factor, which already embeds the
        # coherent-processing clutter rejection — avoids double-counting the
        # Doppler CPI as both signal gain and clutter cancellation.
        sigma_c = self.sigma0(lc, grazing) * self.clutter_patch_area(radar, rng_m, grazing)
        c_over_n_single = radar.snr_single(rng_m, sigma_c)
        imp = undb(MTI_IMPROVEMENT_DB_BY_LC.get(int(lc), 45.0))
        c_residual = c_over_n_single / imp                 # residual clutter / noise
        return s / (1.0 + c_residual)                      # S / (N + C_residual)


# --------------------------------------------------------------------------- #
# Adapter to the Level 2 DetectionModel interface
# --------------------------------------------------------------------------- #


@dataclass
class PhysicsDetectionModel:
    """Wraps RadarParams (+ optional clutter) as a Level 2 detection model.

    Usage:
        radar = RadarParams()
        det = PhysicsDetectionModel(radar, rcs_m2=0.03)
        cfg = replace(Level2Config(), detection=det)
        node = Node(x=..., r_detect=det.reliable_range(), sector_width=90)

    The `.pd(rng_m, r_detect=None)` signature matches Level 2; `r_detect` is
    accepted and ignored (physics sets the scale, not the anchor).
    """

    radar: RadarParams
    rcs_m2: float = 0.03
    clutter: ClutterModel | None = None
    landcover: int | None = None
    kind: str = "physics"

    def pd(self, rng_m, r_detect=None) -> np.ndarray:
        return self.radar.pd(rng_m, self.rcs_m2, self.clutter, self.landcover)

    def reliable_range(self) -> float:
        return self.radar.reliable_range(self.rcs_m2, self.clutter, self.landcover)

    # convenience passthroughs used by some Level 2 report strings
    @property
    def pd_at_r_detect(self) -> float:
        return self.radar.pd_reliable
