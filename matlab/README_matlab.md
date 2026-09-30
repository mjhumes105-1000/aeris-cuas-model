# MATLAB radar scope simulation + Level 3 cross-check

## Files

```
aeris_params.m            every variable, one place
aeris_scope_sim.m         single-target animated scope (2x2, reference)
aeris_scope_sim3d.m       multi-target scope + 3-D volume + randomised raids
aeris_analyze_runs.m      turn the accumulated run log into study curves
aeris_nexus_linkbudget.m  independent Level 3 cross-check against Python
+aeris/                   SHARED PHYSICS — see below
matlab_out/               CSV outputs (link budget, run log)
```

## Shared physics — `+aeris/`

The radar equation used to live in three copies. It now lives once. Both scope
sims call the same package, so they cannot disagree:

| function | what it owns |
|---|---|
| `aeris.derive(p)` | wavelength, aperture, gain, Ts, losses, beamwidths, `dR`, `vUnamb` |
| `aeris.snr(p,g,R,gain)` | **the link budget** — matched-filter radar equation |
| `aeris.pd_swerling1(snr,Pfa)` | Swerling-1 detection probability |
| `aeris.reliable_range(p,g)` | range where Pd drops below `pdReliable` |
| `aeris.beam_pattern(az,p,g)` | URA azimuth pattern (toolbox, with fallback) |
| `aeris.gauss_beam(off,bw)` | Gaussian elevation cut (opt-in) |
| `aeris.clutter_ridge(...)` | constant-γ surface clutter after MTI |
| `aeris.cfar_init` / `aeris.cfar` | CA-CFAR, with the constant terms precomputed |
| `aeris.add_target` | target return + point spread on the RD map |
| `aeris.spawn_threats(p)` | randomised raid generation |
| `aeris.log_run(...)` | append an engagement to the results CSV |
| `aeris.boxfilt`, `aeris.wrap180` | small shared utilities |

**If you change `aeris.snr`, change `cuas_l3/radar.py` to match.** That is now
the only place in MATLAB where the link budget is written.

`aeris_nexus_linkbudget.m` deliberately does **not** use the package — its
value is that it is an independent reimplementation. It does now check its
hardcoded parameters against `aeris_params.m` and warn on drift, so
"independent physics" cannot quietly become "different radar."

---

## Beams & dwells — `aeris_beam3d.m`

```matlab
cd matlab
aeris_beam3d                                      % four-panel figure
aeris_beam3d(aeris_params(),'animate',true)       % step through every dwell
aeris_beam3d(aeris_params(),'elevCover',[0 45])   % what wider coverage costs
```

Four panels: the **3-D radiation pattern** of one beam (mainlobe and sidelobes,
radius scaled by gain in dB), the **3-D dwell tiling** (every beam position as
its 3-dB footprint on a range shell, so gaps and overlap are visible), the
**vertical coverage** wedge with drone-class altitudes overlaid, and the
**dwell budget**.

### What the geometry says

The beam is a **fan, wider than it is tall** — 8 elements in azimuth but 16 in
elevation:

| | |
|---|---|
| wavelength | 3.16 cm |
| 3-dB beamwidth | **12.69° az × 6.35° el** |
| dwell time | 25.6 ms (`cpi/prf`) |

Tiling a 90° sector at 0.9× beamwidth spacing needs 8 azimuth positions, and
the elevation coverage sets the rest:

| elevation covered | dwells | revisit | 4 looks |
|---|---|---|---|
| 0–10° | 16 | 0.41 s | 1.6 s |
| **0–20°** | **32** | **0.82 s** | **3.3 s** |
| 0–30° | 48 | 1.23 s | 4.9 s |
| 0–45° | 64 | 1.64 s | 6.6 s |

**This validates an assumption the scope sims were making silently.** They treat
one displayed frame as one full sector scan that puts a beam on the target.
Revisit is 0.4–1.6 s against `frameDt = 2.0 s`, so that holds — and
`aeris_beam3d` prints an explicit warning if you change `cpi`, sector width or
elevation coverage enough to break it.

It also says **dwell scheduling is not the binding constraint**: a full scan is
under 0.6% of the 300 s requirement. Sensitivity and placement are what limit
the node, which is the right conclusion for the study to reach on evidence
rather than assertion.

`aeris.dwell_plan(p)` returns the numbers without plotting, and
`p.elevCoverDeg` / `p.beamSpacing` control them.

---

## Multi-node distributed sensing — `aeris_engage.m`  (NEW, validate first)

The study's placement variable, made real: a **network** of nodes instead of
one. Each node is the same radar at its own position and boresight; a target is
confirmed when **any** node holds a track (OR fusion - the warning-layer model).

```matlab
cd matlab
rehash; clear functions
aeris_check_net            % parity (N=1) + what 1/2/3/4 nodes buy
```

Pieces:

| file | role |
|---|---|
| `aeris.node_layout(p)` | node positions & boresights: `single`, `line` (picket), `depth` (defense in depth), `ring` (point defense) |
| `aeris.look(...)` | one radar look - the RD-map+CFAR detection, now SHARED so single- and multi-node cannot drift |
| `aeris_engage(p)` | headless N-node engagement; per-target results plus which node confirmed and the network uplift |
| `aeris_check_net` | **run this first** - proves N=1 matches `aeris_scope_sim3d`, then shows the multi-node uplift |

Set the network with `p.nNodes`, `p.nodeLayout`, `p.nodeSpacing`. `nNodes = 1`
reduces exactly to the single-node sim.

**Status:** engine + validation only. The multi-node *sweep* and its analysis
come next, once `aeris_check_net` confirms parity - same pilot-before-15k
discipline. Don't generate multi-node data for the study until Part 1 of the
check prints PARITY OK.

---

## Monte Carlo sweep — `aeris_sweep.m`

The data-generation path. No graphics, no GUI, weighted sampling across drone
classes and environments:

```matlab
cd matlab
aeris_sweep(15000)                     % ~30-90 min single-threaded
aeris_sweep(15000,'parallel',true)     % ~5-15 min on 8 cores
aeris_analyze_sweep
```

Start with a pilot to check the numbers look sane before committing an hour:

```matlab
aeris_sweep(300,'file','matlab_out/pilot.csv')
aeris_analyze_sweep('matlab_out/pilot.csv')
```

Force a flat head-to-head instead of weighted sampling:

```matlab
aeris_sweep(4000,'envs',{'best','grass','rain_heavy','worst'})
```

### Altitude mode — `p.altMode`

Altitude sampling has three modes, and the choice matters for what you can
claim:

| mode | altitude from | use when |
|---|---|---|
| `'class'` *(default)* | the drone class band | realistic per airframe — but altitude is **correlated with RCS** (fixedwing is big *and* high), so altitude effects are confounded |
| `'independent'` | `p.randAlt`, ignoring class | you want to **attribute** an altitude effect; breaks the correlation |
| `'fixed'` | `p.targetAlt` exactly | controlled single-altitude runs |

```matlab
aeris_sweep(15000,'altMode','independent','alts',[30 500])
```

Run both and compare: `'class'` tells you how the node performs against a
realistic threat population; `'independent'` tells you whether altitude
*itself* is a driver. They answer different questions and the second is the one
a committee will press on.

### Output — CSV and `.mat`

Every sweep writes both:

```
matlab_out/aeris_sweep.csv    one row per drone
matlab_out/aeris_sweep.mat    same data, plus provenance
```

The `.mat` (saved `-v7.3`) contains:

| variable | what |
|---|---|
| `data` | table, one row per drone |
| `raids` | table, one row per engagement, with `n_drones` |
| `meta` | timestamp, altMode, MATLAB version, elevation/weather model names, and an explicit list of what is still **provisional** |
| `params` | the exact base parameter struct used |
| `envTable`, `droneTable` | the sampling definitions in force |

```matlab
load('matlab_out/aeris_sweep.mat')
head(raids)
meta.provisional          % what not to cite without a caveat
groupsummary(data,'env','mean','confirmed')
```

Disable with `'mat',false`.

### Weather physics — `aeris.atmos_atten`

Attenuation was **not in the model before**; rain, fog and humidity could not
do anything until it existed. Now the link budget applies two-way path loss:

| mechanism | model | 5 km two-way at 9.5 GHz |
|---|---|---|
| oxygen | ITU-R P.676 dry air | ~0.07 dB |
| water vapour | ITU-R P.676 wet term | ~0.1–0.25 dB |
| fog (dense, 0.5 g/m³) | ITU-R P.840 Rayleigh | ~0.5 dB |
| rain 25 mm/hr | ITU-R P.838, `γ = kR^α` | **~6 dB** |
| rain 50 mm/hr | | **~15 dB** |

**Rain dominates; fog is nearly irrelevant at X-band.** That asymmetry is a
result worth stating — it means the node degrades in weather that is *visible
on radar*, not weather that merely looks bad to a human.

Rain also **backscatters** (Marshall-Palmer Z–R in `aeris.clutter_ridge`),
which against a 0.01 m² drone can matter more than the attenuation. Rain moves,
so MTI suppresses it far less than ground clutter — `p.rainMtiDB = 12` vs
`p.mtiImpDB = 48`. **That 12 dB is a guess, not a measurement.**

### Environments — `aeris.environments`

`best`, `clear`, `grass`, `humid`, `haze`, `fog`, `trees`, `rain_light`,
`rain_mod`, `rain_heavy`, `rain_extreme`, `worst` — each fixing rain, fog,
humidity, γ, MTI improvement and grazing angle. `best` and `worst` are the
optimistic and pessimistic **bounds**, not forecasts; `worst` stacks heavy rain
*and* fog *and* vegetation *and* degraded MTI simultaneously.

Sampling is **weighted** so ordinary conditions dominate — an unweighted sweep
would badly overstate how often the node operates in a downpour.

Also usable as presets: `aeris_params('rain_heavy')`.

### Drone classes — `aeris.drone_catalog`

`micro`, `small_quad`, `heavy_quad`, `fixedwing`, `fpv_attack` — each with RCS
(log-uniform), speed and altitude bands. Replaces the flat RCS draw with
airframe-realistic sampling, so results split by class. RCS bands are
**order-of-magnitude estimates from open literature, not measurements.**

---

## Control panel — `aeris_gui.m`

```matlab
cd matlab
aeris_gui
```

A small always-open window: pick **Mode** (random raid / swarm / deterministic),
**Drones** (Auto or an exact 1–8), **Formation**, **Environment**, seed,
altitude, and the elevation-beam / logging / video toggles, then hit **Run**.
No command line needed, and the panel stays open so you can tweak and re-run.

| button | does |
|---|---|
| **Run** | one animated engagement |
| **Run × N** | N engagements **headless** — no graphics, far faster, for data |
| **Stop** | interrupt at the next frame |
| **Analyze** | plot the accumulated log |

The scope figure also carries **Controls** and **Stop** buttons in its top-left
corner, and reuses one window across runs instead of piling up figures.

Leave **Seed** blank for a fresh raid each run; type the integer printed by a
past run to replay it exactly.

### Headless batch

`p.headless = true` skips all graphics — same physics, same logging, no
drawing. This is how you build a data set:

```matlab
p = aeris_params('random'); p.headless = true; p.quiet = true;
for i = 1:500, aeris_scope_sim3d(p); end
aeris_analyze_runs
```

---

## Animated scope — `aeris_scope_sim3d.m`

Five live panels: PPI, range-Doppler, **3-D volume** (right column), A-scope,
and a per-drone status table. Handles any number of simultaneous targets.

```matlab
cd matlab
aeris_scope_sim3d                            % ONE deterministic target
aeris_scope_sim3d(aeris_params('random'))    % fresh random raid, logged
aeris_scope_sim3d(aeris_params('swarm'))     % small, low, fast, many

p = aeris_params('random'); p.nDrones = 5;   % exactly 5, formation still random
aeris_scope_sim3d(p)
```

**Plain `aeris_scope_sim3d` gives one drone by design** — it is the parity case
against `aeris_scope_sim` and the Python model. Pass the `random` preset (or set
`p.randomThreats = true`) for raids. The run prints its raid composition before
the figure builds, so an unexpected count is visible immediately.

If MATLAB was already open when `+aeris/` was added, run `rehash; clear
functions` once so the package is picked up.

The 3-D panel draws the sector as a translucent wedge, each drone at its true
altitude with a drop-line to its ground shadow, and 3-D trails. Rotate it live
with the mouse.

### Randomised raids

Set `p.randomThreats = true` (the `random` and `swarm` presets do) and every
run draws a new engagement:

| field | draws |
|---|---|
| `nDrones` | **force an exact count** (`p.nDrones = 5`); `[]` = random |
| `randNDrones` | how many drones, `[min max]` (default `[2 6]`) |
| `randRCS` | size, **log-uniform** (micro-quad → Group 2) |
| `randAlt`, `randAltJitter` | lead altitude, per-drone offset |
| `randSpeed`, `randSpeedJitter` | group speed, per-drone (swarm) |
| `randBearingDeg`, `randStartRange` | where the raid comes from |
| `randCourseJitter` | per-drone course error (swarm) |
| `randSpacing` | formation spacing |
| `randFormations` | `single`, `line`, `trail`, `wedge`, `echelon`, `swarm` |

`p.rngSeed = 'shuffle'` gives a different raid each run. The seed actually used
is printed and logged, so **any run can be replayed exactly** by setting
`p.rngSeed` to that integer.

### Data capture

With `p.logData = true`, every run appends **one row per drone** to
`matlab_out/aeris_runs.csv`, carrying run-level context (formation, seed,
placement, environment) alongside the per-drone outcome (RCS, altitude, speed,
reliable range, detection count, confirmation time, warning time).

The file accumulates. That is the point — run it fifty times and you have a
data set.

```matlab
for i = 1:50, aeris_scope_sim3d(aeris_params('random')); end
aeris_analyze_runs
```

`aeris_analyze_runs` prints the headline statistic — the fraction of **raids**
that delivered the required warning — and plots confirmation rate vs RCS,
warning time vs RCS against the `Treq` line, the warning-time distribution, and
confirmation rate vs altitude.

### 3-D and elevation

- `p.targetAlt` — target altitude. **0 reproduces the 2-D baseline exactly**,
  so the Level 3 / Python parity is preserved. At km ranges a few hundred
  metres of altitude changes slant range by ~1 m (<0.01 dB), so the 3-D view is
  essentially free.
- `p.elevBeamOn` — weight SNR by the elevation beam. **Off by default**,
  because the Python model has no elevation term. Turning it on exposes a real
  close-in coverage hole: `nEl = 16` gives a ~6° elevation beamwidth, so a
  drone at 120 m and 500 m range sits at 13° — off the beam. Worth flagging;
  it is a genuine limitation of the fixed-sector architecture.

### Speed

All graphics objects are built once and only their data is updated per frame;
the clutter ridge and CFAR cell counts are computed once per run; box filters
are separable. Set `p.saveVideo = false` while experimenting — `getframe`
dominates everything else once the rest is fixed.

GPU is **not** the lever here. The maps are ~167×128; the cost is graphics, not
arithmetic. MATLAB's only real GPU path is Parallel Computing Toolbox
(`gpuArray`), and on arrays this size it loses to transfer overhead. It becomes
worth it only if you move to an IQ-level front end
(`phased.LinearFMWaveform` → `phased.RangeDopplerResponse`). For Monte Carlo
volume, `parfor` across runs beats GPU.

---

## Single-target reference — `aeris_scope_sim.m`

The original 2×2 scope, kept as the simple known-good reference. One target, no
randomisation, no logging. Same physics (it calls the same package), so it
remains a valid check on the multi-target version:

```matlab
aeris_scope_sim                          % baseline
aeris_scope_sim(aeris_params('micro'))   % 0.01 m^2 micro-quad
aeris_scope_sim(aeris_params('trees'))   % worst-case vegetation clutter
```

Baseline result: a 1.7 km-reliable node 6 km forward confirms a track but
delivers only ~260 s of warning — **short of 300 s**.

---

## Level 3 link-budget cross-check — `aeris_nexus_linkbudget.m`

```matlab
cd matlab
aeris_nexus_linkbudget
```

Requires Phased Array System Toolbox and Radar Toolbox. Writes
`matlab_out/aeris_linkbudget.csv` (range, SNR(dB), Pd per RCS) and
`matlab_out/aeris_array_pattern.csv`, plus two figures.

Overlay the CSV on the Python `figures/fig16_snr_pd`. The SNR(range) curves
should match to a fraction of a dB — both use the identical matched-filter
energy-form radar equation and Swerling-1 Pd, so divergence points to a
parameter that drifted. The drift guard now catches the common case
automatically.

## What MATLAB adds beyond the Python

- The real URA element pattern and array factor (Python uses the aperture
  formula and a Gaussian-ish beamwidth).
- Elevation geometry and the coverage hole it exposes.
- Multi-target raids and formations — Python Levels 1–2 are single-threat.
- A path to `phased.ConstantGammaClutter` and STAP if you take the
  clutter/MTI improvement factor (the dominant Level 3 unknown) to higher
  fidelity than the constant-γ model.

---

## Operator warning output — `aeris_cop.m` (Thread B)

The "communicate back to the user" layer: turns detections into the message a
distributed unit actually receives.

```matlab
cd matlab
rehash; clear functions
aeris_cop                                   % 3-node line, random raid
p = aeris_params('random'); p.nNodes = 4; p.nodeLayout = 'grid'; aeris_cop(p)
```

Two live panels: a fused **operating picture** (defended point, the sensing
network with sector coverage, confirmed hostile tracks with ETA countdowns and
an estimated threat class, faint uncorrelated contacts) and a **warning feed**
(radio-brevity alerts, triaged soonest-ETA first, coloured green/amber/red by
urgency).

The message itself is `aeris.warning_report`, the **hardware-agnostic output**
the architecture calls for - bearing, range, closure, ETA, estimated class with
confidence, and a recommended action, all measured from the defended point and
carrying nothing about the radar internals:

```matlab
w = aeris.warning_report(tracks, p);   % struct array, soonest-ETA first
disp(aeris.warning_text(w(1)))          % render one as the alert a unit sees
```

Threat class is estimated from a NOISY RCS measurement plus Doppler speed
(size alone can't separate a micro-quad from an FPV attacker; size + speed can),
classified against `aeris.drone_catalog` prototypes with a confidence.

Tracks are shown at their detection position - no smoothing yet. A real tracker
with uncertainty ellipses is a Thread-A fidelity upgrade; the warning OUTPUT is
already the real message.

### Tracker + georeference (rung 4)

`aeris_cop` now runs a real constant-velocity **Kalman tracker**
(`aeris.track_step`) instead of showing ground truth:

| piece | role |
|---|---|
| `aeris.meas_polar` | a node's noisy range/bearing fix -> Cartesian z + covariance (angle error dominates, so the ellipse is cross-range) |
| `aeris.kf_predict` / `aeris.kf_update` | constant-velocity Kalman predict/update |
| `aeris.track_step` | predict -> gate-associate -> update -> spawn -> confirm/delete; multiple nodes updating one track IS the fusion |

The picture shows the **estimate**: a track symbol, a heading from the velocity
state, and a 2-sigma **uncertainty ellipse**. Fusing two nodes from different
bearings visibly tightens it. Warnings are computed from the estimate, so ETA
and class now carry real estimation error. Truth is a faint grey ghost for
validation (`p.showTruth=false` for the pure operator view). Tracker knobs:
`p.trackQ` (maneuver allowance), `p.trackGate`, `p.trackConfirm`, `p.trackMaxMiss`.

**Georeference.** Set a site datum and the warnings report a real posit:

```matlab
p = aeris_params('random');
p.refLat = 33.24; p.refLon = -117.44; p.threatBearing = 270;  % site + facing
aeris_cop(p)
```

`aeris.sim2ll` maps any sim-frame (x,y) to lat/lon (`aeris.enu2ll`, flat-earth).
The defended point and every track then carry coordinates a unit with a map can
use. The operator UI that turns a map click into refLat/refLon/threatBearing -
the "loaded map" - is the next build (likely `geoplot`/`geobasemap`, Mapping
Toolbox).
