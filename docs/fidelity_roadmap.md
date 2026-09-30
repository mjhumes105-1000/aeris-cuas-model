# AERIS-Nexus high-fidelity model — architecture and fidelity roadmap

## High-fidelity model vs. digital twin

A model becomes a *twin* when (1) it spans every subsystem from one shared
definition, (2) its fidelity is high enough to substitute for measurement in
the questions you ask of it, and (3) it can be **validated against the physical
article** and, eventually, fed by its telemetry. We already have (1) and a good
start on (2), so this is a **high-fidelity model, not yet a twin** - (3) needs
the physical hardware. This doc is the map from here toward a validated twin.

## The model today — one definition, every subsystem

Everything derives from a single parameter struct (`aeris_params`). Change one
number and the whole system moves consistently, which is the defining property
of a system model:

```matlab
aeris.system_report(aeris_params(), 4)   % the model at a glance, 4-node net
```

| domain | model | fidelity now |
|---|---|---|
| **Sensing** | link budget, Swerling-1 Pd, CFAR, constant-γ clutter, ITU weather | mid — radar-equation SNR, aperture-formula gain |
| **Beam / schedule** | URA pattern, dwell tiling, revisit | mid — analytic array factor |
| **Multi-node** | placement layouts, OR-fusion, per-node geometry | good |
| **Comms** | link budget + mesh reachability + latency | mid — Friis + path-loss exponent |
| **Tracking** | constant-velocity Kalman, gating, multi-node fusion | good |
| **Warning output** | georeferenced (WGS-84) CoT-ready message | good |
| **Power** | pulsed-average DC budget, battery runtime | mid — parametric |
| **SWaP-C** | weight + cost BOM, per node and network | mid — priced parts |
| **Scenario engine** | randomized raids, Monte Carlo sweep, COP/scope | good |

That is a genuine system model: sensing range, revisit, comms reach, power draw,
weight and cost all move together off the same spec, and a scenario run and the
system card can never disagree.

## The gap to HIGH fidelity — the rungs

Each rung swaps an analytic approximation for a physics- or measurement-grade
model, and each is independently useful. The toolboxes being installed
(Antenna, RF, RF Blockset) unlock the first three.

1. **[DONE] Real antenna patterns (Antenna Toolbox).** `aeris.antenna_model`
   tiles a modeled microstrip patch into a `phased.URA`; `aeris.derive` and
   `aeris.beam_pattern` use it behind `p.useModeledAntenna`. Validated by
   `aeris_antenna_check`: modeled vs analytic agree to **0.3 dB gain / 0.13 deg
   beamwidth**, three-way with Python at ~1.7 km reliable range. Modeled far
   sidelobes drop ~5-10 dB faster than the aperture formula (real element
   taper). Comms omni modeled too (`aeris.comms_antenna_gain`).

2. **[DONE] RF chain (Friis cascade).** `aeris.rf_chain` builds the receive
   chain - ADL8107 LNA (1.3 dB NF, 24 dB gain) -> ADAR1000 -> mixer -> Pluto -
   and `aeris.derive` takes the system NF from it behind `p.useRfChain`. Result
   (`aeris_rfchain_check`): **system NF 1.43 dB, 97% set by the LNA**, vs the
   4 dB placeholder -> **+2.6 dB / +16% range**. The LNA-per-element architecture
   is what makes the node's NF ~= the LNA's own.

3. **[DONE] IQ signal-level front end.** `aeris.look_iq` builds a real
   fast-time x slow-time datacube (LFM chirp -> matched-filter pulse
   compression -> windowed Doppler FFT -> |.|^2), replacing the synthesized
   range-Doppler map. `aeris_iq_check` compares Pd vs SNR against the fast map:
   the curves track with the IQ shifted **+2.5 dB** - the **processing loss**
   (Doppler-window + straddle) the fast map omits. Too heavy for the 15k sweep
   (a full CPI datacube per dwell - the GPU/cluster rung); its job is to
   validate the fast map, which it does.

   **Key result - the refinements cancel.** The RF-chain NF gain (+2.6 dB) and
   the IQ processing loss (-2.5 dB) very nearly cancel, so the net reliable
   range returns to ~1.7 km - the conservative baseline. Two independent
   fidelity upgrades pulling opposite ways converge back on the original
   number: the baseline was robust, not lucky. Fold the loss in with
   `p.procLossDB` (~2.5).

4. **Terrain & propagation.** Hook the Level 4 viewsheds for masking; add
   multipath/diffraction over terrain for low-altitude targets.

5. **Validation against the CN0566 hardware — the twin ↔ physical link.** This
   is what turns the model into a twin. Bench the real Phaser: measured array
   pattern vs modeled, measured SNR(range) vs predicted, measured track error
   vs the Kalman covariance. Each comparison either confirms a subsystem or
   calibrates it. `matlab/aeris_nexus_linkbudget.m` already exports CSVs for
   exactly this overlay - extend the pattern to measurement.

6. **Live telemetry (the operational twin).** Ingest CoT/track streams from a
   fielded node so the twin runs alongside the real system, predicting warning
   and flagging when reality diverges from the model. This is the endpoint.

7. **Visualization.** The COP (map + tracks + comms), the 3-D scope, the beam
   plot - already the model's viewports.

## Where the core study stops, and where the model keeps going

Per `CLAUDE.md`, Levels 1-2 are the minimum viable study and results must
not depend on RF hardware. The model as it stands (rungs 0-3 modeled, 5 set up
for when hardware is available) **already exceeds** that bar. Rungs 5-6 are what
make it a *twin* rather than a model, but they need the physical CN0566 and are
a stretch goal. Build the fidelity rungs because they strengthen
the argument and stand alone - not because the study blocks on them.

## Two modeling artifacts caught and fixed (graceful, not cliffs)

While climbing the rungs, two hard-threshold artifacts surfaced - both a
geometric switch standing in for a smooth physical rolloff - and both were made
graceful:

- **Comms backhaul** (`aeris.comms`): a binary in/out-of-range switch became a
  packet-delivery waterfall + ARQ latency inflation. Warning now degrades
  smoothly to a hard floor where no path exists, not off a cliff. Sharpness
  tunable via `p.commsWaterfall`.
- **Azimuth sector edge** (`aeris.az_gain`): a full-gain-inside / zero-outside
  wall became scan loss (cos^q) + a soft shoulder past the edge, matching the
  elevation treatment (`aeris.elev_gain`). Cost the grass baseline ~2.7 points
  (65.4 -> 62.7%) - the honest, less-optimistic coverage. Sharpness via
  `p.scanLossExp`.

Documenting these - a model that degrades gracefully at its boundaries, with the
rolloff sharpness shown not to change the conclusion - is a maturity signal, not
an embarrassment.

## Status and next step

Rungs 0-3 are modeled and cross-validated; rungs 1-3 each have a check harness
(`aeris_antenna_check`, `aeris_rfchain_check`, `aeris_iq_check`). The sensing
front end is now faithful from the radar equation up to signal-level IQ, and the
headline (grass ~63% met, speed-bound failures, rain-only weather) survived
every upgrade.

Remaining, all needing hardware or being separate studies:
- **Rung 4 - terrain & propagation** (hook the Level 4 viewsheds).
- **Rung 5 - CN0566 hardware validation** (the twin <-> physical link).
- **EW jammer model** - raise the noise floor at a location, watch the comms
  waterfall and reliable range both erode; quantifies the backhaul vulnerability
  the comms study exposed.
