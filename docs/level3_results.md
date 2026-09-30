# Level 3 results — radar link budget (AERIS-Nexus placeholder params)

**All radar numbers are documented placeholders** (see `cuas_l3/radar.py`, `AERIS_NEXUS_PROVISIONAL`); freeze from the AERIS-10 repository before citing.

- Frequency 9.5 GHz (λ = 31.6 mm), 8×16 array, aperture 319 cm², gain **23.8 dBi**
- Beamwidths 12.7° az × 6.3° el; range resolution 30 m
- Peak power 20 W, pulse 10 µs, PRF 10 kHz, CPI 256 pulses → integration 24.1 dB
- Noise figure 4 dB (Ts 728 K), losses 6 dB, Pfa 1e-06

## 1. Reliable range vs target RCS (thermal noise only)

| Target | RCS (m²) | Reliable range (Pd 0.9) | Pd @ 2 km | Pd @ 3 km |
|---|---|---|---|---|
| Group 2 / small fixed-wing | 0.1 | 2.31 km | 0.94 | 0.75 |
| large quad | 0.05 | 1.95 km | 0.89 | 0.56 |
| nominal small UAS | 0.03 | 1.71 km | 0.82 | 0.39 |
| micro quad | 0.01 | 1.30 km | 0.57 | 0.09 |

**Key finding.** With these placeholder parameters the node's reliable range on a nominal 0.03 m² small UAS is **1.7 km**, not the 3 km design claim; the 3 km figure is only approached for a ~0.1 m² (Group 2 / fixed-wing) target. This is the study's skepticism about advertised ranges made quantitative, and it propagates: the 'reliable range' Levels 1-2 treated as 3 km is really RCS-dependent and mostly below it.

## 2. Clutter by land cover (RCS 0.03 m²)

Reliable range with surface clutter, by land-cover class and grazing angle. Clutter enters as single-pulse C/N divided by the Doppler processor's improvement factor (the dominant provisional unknown). γ = σ⁰ level, I = MTI improvement.

| Land cover | thermal-only | grazing 1° | grazing 2° | grazing 5° |
|---|---|---|---|---|
| bare/sand | 1.71 km | 1.71 | 1.71 | 1.71 |
| grass | 1.71 km | 1.71 | 1.71 | 1.71 |
| shrub | 1.71 km | 1.71 | 1.71 | 1.70 |
| wetland | 1.71 km | 1.71 | 1.71 | 1.70 |
| water | 1.71 km | 1.71 | 1.71 | 1.71 |
| built-up | 1.71 km | 1.71 | 1.70 | 1.68 |
| trees | 1.71 km | 1.62 | 1.52 | 1.21 |

Bare, grass and built-up cancel to near the thermal-only range; **trees and shrub at higher grazing angles are the hard case**, because high σ⁰ combines with the limited MTI improvement that swaying vegetation allows. This is the physical link to the Level 4 land-cover map: a candidate whose footprint looks over trees is a materially harder detection problem, and the improvement factor is the single parameter most worth pinning down (bench/field measurement, or a STAP study).

## 3. Feeding physics back into placement

At 30 m/s the requirement needs 9 km of warning depth. A physics-limited 1.7 km node (0.03 m²) must therefore sit **7.3 km forward**, not the 6 km the Level 2 baseline assumed — and that is before terrain (Level 4) and the latency/confirmation budget. The distributed-node concept still works, but the node has to be pushed further forward or the corridor covered with more nodes.

## 4. Physics Pd inside the Level 2 warning chain

Replacing the empirical logistic Pd with the physics model and setting each node's reliable range from the link budget, then running the full Level 2 chain (revisit, 3-of-4 confirmation, ~19 s latency, 0.855 availability, 30 m/s head-on):

| Config | node R_detect | D_forward | P(meet) |
|---|---|---|---|
| RCS 0.1, D=6.0 km | 2.31 km | 6.0 km | **0.76** |
| RCS 0.1, D=6.7 km | 2.31 km | 6.7 km | **0.85** |
| RCS 0.03, D=6.0 km | 1.71 km | 6.0 km | **0.04** |
| RCS 0.03, D=7.3 km | 1.71 km | 7.3 km | **0.82** |

The physics Pd and the empirical logistic give consistent chain behaviour once the reliable range is matched — the point of Level 3 is that it *derives* that range and its RCS/clutter dependence instead of assuming it.

## MATLAB cross-check

- The MATLAB Phased Array Toolbox scripts in `matlab/` reproduce the array gain/pattern and the SNR(range) curve independently; run them locally and compare against `figures/fig16_snr_pd`. Agreement in the overlap region validates the Python link budget.
- Dominant provisional unknowns, in order: target RCS, MTI/clutter improvement factor over vegetation, transmit power, and integration (CPI) length. All are single-line edits in `RadarParams` / the clutter tables.

_Run time 4 s._
