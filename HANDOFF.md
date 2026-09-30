# HANDOFF — C-UAS simulation stack

**For:** the next working session (Claude Code, or you six weeks from now).
**Date:** 3 September 2026.
**Location:** repository root

Read `CLAUDE.md` first for the research question, the frozen/provisional
decisions, and the architecture rules. This file is the operating manual: how
to set it up, how to run each piece, what each one produces, and what to do
next.

---

## 1. One-time setup

Open PowerShell in the repository root.

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
```

If PowerShell blocks the activate script:
`Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass` and retry.

**OneDrive note.** A `.venv` is thousands of small files and OneDrive will
try to sync all of them. Either exclude `.venv` in OneDrive settings, or put
the venv outside the synced folder (`python -m venv C:\venvs\cuas`) and
activate that instead. `.gitignore` already ignores it for git.

Verify:

```powershell
python -m pytest -q          # expect: 40 passed
```

### Data files (needed only for the real-terrain run)

Two public tiles live in `data/` (already downloaded, ~130 MB total, excluded
from the zips):

- `Copernicus_DSM_COG_10_N33_00_W118_00_DEM.tif` — ESA Copernicus GLO-30 DEM,
  33-34°N 117-118°W (covers the Camp Pendleton coastline).
- `ESA_WorldCover_10m_2021_v200_N33W120_Map.tif` — ESA WorldCover 10 m land
  cover.

If they are ever missing, re-download from
`https://copernicus-dem-30m.s3.amazonaws.com/Copernicus_DSM_COG_10_N33_00_W118_00_DEM/Copernicus_DSM_COG_10_N33_00_W118_00_DEM.tif`
and
`https://esa-worldcover.s3.eu-central-1.amazonaws.com/v200/2021/map/ESA_WorldCover_10m_2021_v200_N33W120_Map.tif`.
Both are public and unclassified; cite ESA.

---

## 2. Run everything

```powershell
python scripts\run_all.py --quick     # coarse pass, ~1 min — use this first
python scripts\run_all.py             # full resolution, ~3 min
```

Useful flags: `--skip-dem` (no real-terrain run), `--skip-tests`,
`--only 3` (single level).

It runs tests, then Levels 1 → 2 → 4 → 3 in dependency order, prints a
PASS/FAIL summary, and tells you where the outputs went. Everything below is
what that script calls, in case you want to run pieces individually.

---

## 3. Run each file

### Level 1 — mission geometry (`scripts/run_level1.py`)

Deterministic. No detection statistics. Answers: how much range and forward
placement deliver a required warning time, and what sector width does off-axis.

```powershell
python scripts\run_level1.py
python scripts\run_level1.py --vc 45 --latency 30 --buffer 500 --treq 300
```

Flags: `--vc` closure speed m/s, `--latency` s, `--buffer` action buffer m,
`--treq` required warning s, `--out` figure directory.

Produces `docs/level1_results.md` and figures 1-5. Runs in seconds.

### Level 2 — Monte Carlo warning chain (`scripts/run_level2.py`)

Adds Pd(range), revisit, M-of-N confirmation, latency, false alerts, node and
comms availability, and speed/bearing priors. Produces
P(T_warning ≥ 300 s), not an average.

```powershell
python scripts\run_level2.py --quick    # ~20 s
python scripts\run_level2.py            # ~1 min
```

Produces `docs/level2_results.md`, `docs/level2_pmeet_grid.csv`, figures 6-11.

**To change assumptions**, edit `cuas_l2/models.py` — every default sits in a
dataclass with a docstring explaining where it came from. The sensitivity
figure (7) shows which ones matter.

### Level 4 — terrain and environment (`scripts/run_level4.py`)

Loads a DEM, builds 4/3-earth viewsheds for a mast height and a
terrain-following threat altitude, and scores placement candidates on real
ground by feeding visibility into the Level 2 Monte Carlo.

```powershell
# synthetic beach (no data files needed), ~15-30 s
python scripts\run_level4.py --quick

# real terrain — Camp Pendleton coastline, inland threat axis
python scripts\run_level4.py `
    --dem "data\Copernicus_DSM_COG_10_N33_00_W118_00_DEM.tif" `
    --landcover "data\ESA_WorldCover_10m_2021_v200_N33W120_Map.tif" `
    --lon -117.463 --lat 33.29 --axis 52
```

Flags: `--lon/--lat` site centre, `--axis` compass bearing that becomes the
+x (threat) axis, `--half` half-width of the grid in metres (default 12000),
`--quick`.

Produces `docs/level4_results_<terrain name>.md` and figures 12-15. The
synthetic and real runs write separate results files, so both are kept.

**To study a different beach**, change `--lon/--lat/--axis`. Nothing else.

### Level 3 — radar physics (`scripts/run_level3.py`)

Radar-equation SNR → Swerling-1 Pd for the 8×16 X-band array, plus
constant-γ clutter with a per-land-cover MTI improvement factor. Derives the
reliable range that Levels 1-2 assume, and reports the feedback into placement.

```powershell
python scripts\run_level3.py            # <10 s, no flags
```

Produces `docs/level3_results.md` and figures 16-19.

**To change the radar**, edit `RadarParams` in `cuas_l3/radar.py`. That is the
one place. `AERIS_NEXUS_PROVISIONAL` is the named placeholder set — freezing
the real AERIS spec should be a one-line diff there, mirrored into
`matlab/aeris_params.m`.

### Tests

```powershell
python -m pytest -q                      # all 40
python -m pytest -q tests\test_level3.py # one file
python -m pytest -q -k "clutter"         # by name
```

Each test asserts against an analytic value or a limiting case: Level 1 against
closed-form geometry, Level 2's ideal limit against Level 1, Level 4's flat
earth against the analytic radar horizon and against Level 2, Level 3 against
the R⁻⁴ law and the Swerling anchor. If you change a model and a test fails,
the test is probably right.

### MATLAB — animated radar scope (`matlab/aeris_scope_sim.m`)

Run in MATLAB, not from Python. Needs Phased Array System Toolbox.

```matlab
>> cd matlab                                % from the repository root
>> aeris_scope_sim                          % baseline, plays live + writes MP4
>> aeris_scope_sim(aeris_params('micro'))   % 0.01 m² micro-quad
>> aeris_scope_sim(aeris_params('trees'))   % worst-case vegetation clutter
>> p = aeris_params(); p.Dforward = 7300; aeris_scope_sim(p)   % fixes the shortfall
```

Four live panels — PPI with sweeping beam and warning clock, range-Doppler
map, A-scope with CFAR threshold, status — and it writes `aeris_scope.mp4`.

**All knobs are in `matlab/aeris_params.m`.** Presets: `default`, `micro`,
`fixedwing`, `fast`, `trees`. Set `p.saveVideo = false` to skip the MP4,
`p.useToolboxCFAR = true` to detect with `phased.CFARDetector2D` instead of
the built-in CA-CFAR.

**Not yet run on real MATLAB** — it was written and its algorithm validated by
mirroring it in Python, but never executed. Expect a possible small syntax fix
on first run. See §6.

### MATLAB — link-budget cross-check (`matlab/aeris_nexus_linkbudget.m`)

```matlab
>> aeris_nexus_linkbudget
```

Independently reproduces the Level 3 SNR(range) and Pd(range) using the
toolbox, writes `matlab/matlab_out/*.csv`. Overlay against Python
`figures/fig16_snr_pd.png`. They should agree closely; divergence means a
parameter drifted between `RadarParams` and the `.m` header block.

---

## 4. What the model currently says

Numbers are provisional. Full tables in `docs/level*_results.md`.

1. **Level 1.** The handoff's architecture table reproduces exactly (9 km at
   the defended point, 3 km at 6 km forward, 2 km at 7 km forward all give
   300 s at 30 m/s). By the R⁴ power-aperture proxy the 9 km radar costs ~81×
   the 3 km node for the same on-axis warning.
2. **Level 1, non-obvious.** Placement and sector width are coupled. A 3 km
   node 6 km forward can only ever see threats within ±30° of its axis, and a
   90° sector pointed forward sees only ±14.5°, because off-axis threats cross
   its flanks. Forward pickets must be oriented and offset for crossing
   geometry.
3. **Level 2.** The Level 1 equivalence breaks under a realistic chain: the
   9 km radar holds P(meet) = 0.85, the 3 km node at 6 km falls to 0.58, the
   2 km picket at 7 km to 0.20. The chain costs ~660 m of depth at 30 m/s.
   Fix is placement, and it is cheap: +0.5 km for the 3 km node.
4. **Level 2, dominant sensitivities.** Latency and Pd-at-range dominate;
   revisit and M-of-N next; availability is a linear scale factor. Adding
   nodes raises coverage but scales false alerts and drops PPV from 0.13 to
   0.08 — the many-cheap-nodes trade is decided by per-node false-track rate.
   Threat speed is decisive: 0.85 below 25 m/s, ~0 above 35 m/s.
5. **Level 4.** Terrain masking is first-order. On the Camp Pendleton
   coastline the nominal 6 km on-axis position sees 3 % of its footprint
   against a 30 m AGL threat and scores 0.00; the best gridded site sees 68 %
   and scores 0.28. A masked site cannot be rescued by a taller mast.
   **One 3 km node cannot deliver 5 minutes on that terrain from anywhere.**
6. **Level 3.** The placeholder radar reaches **1.7 km** reliable on a 0.03 m²
   target (2.3 km at 0.1 m², 1.3 km at 0.01 m²) — well under the 3 km design
   claim, which is only approached for Group-2-sized targets. That pushes the
   required forward placement from 6 km to ~7.3 km before terrain and latency.
7. **Level 3, clutter.** Second-order over bare/grass/built-up; trees and
   shrub at higher grazing angles are the hard case (1.7 → 1.2 km over trees
   at 5°). The MTI improvement factor is the most sensitive unknown and the
   physical bridge to the Level 4 land-cover map.

**The through-line:** buying warning through placement and
quantity rather than range still holds, but the physics and the terrain both
push harder than the concept assumed. A single small node is not sufficient on
real ground; the design question is how many, where, and pointed how.

---

## 5. What to do next (suggested order)

1. **Write-up.** Highest value. Everything needed exists: research
   question, equations, four levels of results, figures, and a defensible
   negative result.
2. **Freeze AERIS.** Record repository URL, exact commit/tag/date, variant,
   licence, and the waveform/array/power/processing spec. Write it into
   `AERIS_NEXUS_PROVISIONAL` and `matlab/aeris_params.m`. Until then no
   Level 3 number should be cited.
3. **Validate the 300 s requirement.** It is load-bearing and unsourced.
   Establish the operational basis, the action buffer, and what event stops
   the warning clock.
4. **Multi-node placement optimiser on real terrain.** Level 4 showed a single
   node cannot solve the problem, so the natural next model answers "how many
   nodes, where, boresighted how, to reach P ≥ 0.8 across the corridor."
   This is the biggest remaining modelling gap.
5. **Run the MATLAB scope** and fix anything that errors (§6).
6. Optional: swap the Level 3 detection front end for IQ +
   `phased.RangeDopplerResponse` for signal-level fidelity.

---

## 6. Known gaps and honest caveats

- **The MATLAB scope has never been executed.** Its algorithm was validated by
  a Python mirror (reliable range, CFAR false-alarm rate, and the track/warning
  outcome all matched), but the MATLAB itself is unrun. First run may need a
  small fix.
- **Every Level 2 and Level 3 parameter is a documented placeholder.** Pd 0.9
  at range, 19 s latency, 2 false tracks/node/hour, 0.855 availability, 20 W,
  24 dBi, 4 dB NF, 256-pulse CPI, all the clutter γ and MTI values. The
  sensitivity results are steep around several of them.
- **Level 4's candidate grid is coarse** (500 m × 1 km). It will miss the best
  crest sites. A ridge-following candidate search is the obvious refinement.
- **The site and threat axis are my choice**, not doctrine: 33.29°N,
  117.463°W, axis 052°. Change if the vignette calls for a specific landing
  beach and inland objective.
- **Level 3 detection is modelled at the range-Doppler level**, not from IQ.
- **Level 5-7 of the roadmap are not built**: multi-sensor fusion and
  resilience, operator/HSI, and hardware validation.
- No IRB, export-control, or public-release review has been started. Both are
  flagged in the original concept handoff as schedule risks.

---

## 7. File map

```
CLAUDE.md          project context for Claude Code — read first
HANDOFF.md         this file
README.md          findings summary + equations + layout
requirements.txt   numpy, scipy, matplotlib, rasterio, pytest

cuas_l1/  geometry.py scenarios.py plots.py        Level 1
cuas_l2/  models.py montecarlo.py experiments.py plots.py    Level 2
cuas_l3/  radar.py plots.py                        Level 3 (radar physics)
cuas_l4/  terrain.py study.py plots.py             Level 4 (terrain)

scripts/  run_all.py run_level1.py run_level2.py run_level3.py run_level4.py
tests/    test_geometry.py test_level2.py test_level3.py test_level4.py
matlab/   aeris_params.m aeris_scope_sim.m aeris_nexus_linkbudget.m README_matlab.md
data/     DEM + land-cover GeoTIFFs (not in zips)
figures/  generated PNG + SVG, numbered 1-19 + scope preview
docs/     generated level*_results.md + level2_pmeet_grid.csv
_archive/ dated zips of previous states
```

Source of the whole effort: the original project concept brief (September 2026).
