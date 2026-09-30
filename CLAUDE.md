# CLAUDE.md — project context for Claude Code

Personal C-UAS modeling project by **Mark Humes**, built entirely on
open-source tools and publicly available information.

Working title: *Minimum Sensing and Placement Requirements for Tactically
Useful Counter-UAS Warning Using an Open Fixed-Sector Radar Architecture.*

## The research question

What combination of sensor performance and placement is required for a
low-cost, attritable C-UAS sensing node to provide tactically useful warning
to distributed Navy and Marine Corps forces?

The project is **not** about building a radar. It is about defining the minimum
mission-relevant sensing envelope and testing candidate open architectures
(AERIS-10 Nexus) against it. A defensible negative result — "the baseline
cannot meet the requirement, and here is the parameter that drives it" — is a
successful result.

## Frozen decisions (do not relitigate without the owner)

- Focus is minimum sensing capability **and placement**, not maximum radar range.
- The node is a persistent local warning layer inside defense-in-depth. It is
  not a stand-alone defeat system and not a miniature MADIS.
- Architecture philosophy: low-cost, open, fixed-sector, distributed,
  attrition-tolerant, hardware-agnostic output.
- Level 1-2 simulation is the minimum viable study; results must not
  depend on RF hardware.
- AERIS-10 is the primary open architecture to model; ADI CN0566 is the
  lower-risk lab reference.

## Provisional (must be validated before citing)

- **300 s (5 min) warning requirement.** Load-bearing: every result scales off
  it. Operational basis not yet established.
- **~2-3 km node reliable range.** Level 3 now says the placeholder radar
  actually achieves ~1.7 km on a 0.03 m² target — see findings.
- Threat set, RCS, closure speed band, action buffer, sector geometry.
- Every number in `cuas_l3.RadarParams` (`AERIS_NEXUS_PROVISIONAL`).

## Architecture — one hook per level

The levels compose through **narrow, documented interfaces**. Preserve them.

```
Level 1  cuas_l1   deterministic geometry      Node, Threat, WarningRequirement
   |                                            warning_time(), first_detection_range()
Level 2  cuas_l2   Monte Carlo warning chain   simulate(nodes, cfg, visibility=None)
   |     hook: cfg.detection.pd(range, r_detect) -> Pd
Level 4  cuas_l4   terrain & environment       viewshed() -> Viewshed callable
   |     plugs into simulate(..., visibility=[vs]) — one entry per node
Level 3  cuas_l3   radar physics               PhysicsDetectionModel.pd(range, r_detect)
         drop-in replacement for the Level 2 detection hook; also derives
         reliable_range(), the number Levels 1-2 otherwise assume
```

Rules that keep this working:

- `DetectionModel.pd(rng_m, r_detect)` is the **only** physics hook. Anything
  that computes Pd must match that signature (Level 3's ignores `r_detect`).
- `simulate(..., visibility=...)` takes one callable per node, `f(x, y) -> bool`.
  `None` means flat-earth. Flat terrain must reduce exactly to Level 2
  (there is a test for this — keep it passing).
- Units are SI everywhere inside the models: metres, seconds, m/s, degrees.
  Convert only in the plotting layer.
- Defended point at the origin; **+x is forward, toward the expected threat**.
  Bearings in degrees from +x, counter-clockwise positive.
- Warning time `-inf` = never detected. Negative finite = detected too late.

## Conventions

- Every provisional parameter lives in a dataclass with a docstring saying
  where the number came from and that it is provisional. Do not scatter magic
  numbers into experiment code.
- Results scripts (`scripts/run_level*.py`) both print and write a markdown
  file into `docs/`. Narrative sentences must be generated from the computed
  values, not hard-coded, so the prose cannot drift from the numbers.
- Figures are numbered globally and monotonically (1-5 L1, 6-11 L2, 12-15 L4,
  16-19 L3). New figures continue the sequence.
- Tests are hand-checkable: each asserts against an analytic value or a
  limiting case, not against a previous run's output.
- Python and MATLAB implement the same physics. If you change the link budget
  in `cuas_l3/radar.py`, change `matlab/aeris_nexus_linkbudget.m` and
  `matlab/aeris_params.m` to match, and say so.

## Commands

```bash
python scripts/run_all.py --quick     # everything, coarse (~1 min)
python scripts/run_all.py             # everything, full (~3 min)
python -m pytest -q                   # 40 tests, ~5 s
```

Individual levels and the MATLAB scope: see `HANDOFF.md`.

## Current state

All four simulation levels are built, tested (40 passing), and integrated.
No AERIS repository commit has been
frozen. Findings are in each `docs/level*_results.md` and summarised in
`README.md`.
