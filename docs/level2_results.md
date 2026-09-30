# Level 2 results

Baseline configuration (all provisional, see `cuas_l2/models.py`):
- Detection: logistic, Pd = 0.9 at R_detect, roll-off 0.1 × R_detect, Pd_max 0.98
- Tracker: revisit 1.0 s, 3-of-4 confirmation, central fusion
- Latency: lognormal stages, median total ≈ 19 s
- Availability: P(node up) 0.9 × P(comms) 0.95 = 0.855
- False tracks: 2.0/node/h; threat arrivals 0.5/h (for PPV)
- Threat: 30 m/s head-on unless stated; requirement 300 s

## 1. Architecture cases under identical imperfections (head-on, 30 m/s)

| Case | R (km) | D (km) | P(meet) logistic | P(track) | p50 T_w (s) | mean R_track (km) | P(meet) Swerling-I | FA/h | PPV |
|---|---|---|---|---|---|---|---|---|---|
| Long-range at defended point | 9 | 0 | **0.86** | 0.86 | 370 | 11.9 | 0.86 | 1.7 | 0.20 |
| Distributed node | 3 | 6 | **0.59** | 0.86 | 303 | 9.8 | 0.86 | 1.7 | 0.20 |
| Lower-cost picket | 2 | 7 | **0.21** | 0.86 | 293 | 9.5 | 0.85 | 1.7 | 0.20 |
| Short-range beside force | 2 | 0 | **0.00** | 0.86 | 60 | 2.5 | 0.00 | 1.7 | 0.20 |

With a single node, P(track) is capped by availability (0.855). The Level 1 equivalence of the three 9 km-depth architectures breaks once latency and confirmation are charged: ~19 s of latency plus 3 looks to confirm costs ~660 m of depth at 30 m/s, and the small forward nodes have no geometric margin to pay it. The Swerling-I column shows how much an optimistic long Pd tail hides this; the roll-off shape is a Level 3 deliverable.

## 2. P(meet) over range × placement

See `figures/fig6_pmeet_range_vs_placement.png`; raw grid in `docs/level2_pmeet_grid.csv`. The P = 0.8 contour sits to the right of the Level 1 ideal line by the placement penalty quantified in section 3, and nothing exceeds the availability ceiling of 0.855.

## 3. Forward placement needed to reach P(meet) = 0.9 (availability = 1)

| Node R_detect | Level 1 ideal D | Level 2 D for P ≥ 0.9 | Extra placement |
|---|---|---|---|
| 2 km | 7.0 km | 7.75 km | +0.75 km |
| 3 km | 6.0 km | 6.50 km | +0.50 km |
| 4 km | 5.0 km | 5.00 km | +0.00 km |

The chain costs V_c × (latency + confirmation looks) ≈ 660 m of depth at 30 m/s. Larger nodes pay part of it from their soft roll-off beyond R_detect (the tail is proportional to R_detect), which is why the extra placement shrinks with node range. Design rule: the Level 1 position is a floor; budget the chain on top of it in placement, not in radar range. Note the baseline 3 km node only reaches its score at all because of the tail beyond R_detect — with a hard edge (roll-off → 0, section 4) it fails outright. The tail shape is a Level 3 output.

## 4. One-at-a-time sensitivity, 3 km node 6 km forward

Baseline P(meet) = 0.59.

- **latency_median_s**: 0.0 → 0.85, 9.5 → 0.83, 19.0 → 0.60, 28.5 → 0.28, 38.0 → 0.11, 57.0 → 0.01
- **pd_at_r_detect**: 0.5 → 0.02, 0.7 → 0.12, 0.8 → 0.27, 0.9 → 0.60, 0.95 → 0.79
- **rolloff_frac**: 0.02 → 0.00, 0.05 → 0.06, 0.1 → 0.60, 0.2 → 0.85, 0.3 → 0.85
- **revisit_s**: 0.5 → 0.71, 1.0 → 0.60, 2.0 → 0.39, 4.0 → 0.20, 8.0 → 0.05
- **m_of_n**: 1/1 → 0.84, 2/2 → 0.70, 2/3 → 0.75, 3/4 → 0.60, 4/5 → 0.42, 5/6 → 0.26
- **p_node_up**: 0.7 → 0.46, 0.8 → 0.53, 0.9 → 0.60, 0.95 → 0.63, 1.0 → 0.66

## 5. Node layouts, threat bearing uniform in ±30°

| Layout | P(meet) | P(track) | mean nodes up | FA/h | PPV |
|---|---|---|---|---|---|
| 1 node on axis | 0.21 | 0.50 | 0.86 | 1.7 | 0.13 |
| 2 co-located (redundant) | 0.35 | 0.58 | 1.71 | 3.4 | 0.08 |
| 2 nodes at ±20° | 0.36 | 0.77 | 1.71 | 3.4 | 0.10 |
| 3 nodes at 0, ±25° | 0.53 | 0.90 | 2.57 | 5.1 | 0.08 |
| 1 node, 360° sector | 0.21 | 0.86 | 0.86 | 1.7 | 0.20 |
| 3 nodes 360° at 0, ±25° | 0.54 | 0.99 | 2.57 | 5.1 | 0.09 |

Redundant co-location raises availability but not geometry; lateral offset raises geometry but each node still only covers its own ±~15° for full warning. The false-alert column is the price: every node added adds its own false-track rate, and PPV falls accordingly. This is the Level 2 form of the 'more cheap nodes vs one better radar' trade, and it is where the false-alert rate per node (a Level 3 output) decides the answer.

## 6. Closure-speed band 10-50 m/s, 3 km node 6 km forward

| Speed bin (m/s) | 10-15 | 15-20 | 20-25 | 25-30 | 30-35 | 35-40 | 40-45 | 45-50 |
|---|---|---|---|---|---|---|---|---|
| P(meet) | 0.85 | 0.86 | 0.88 | 0.82 | 0.11 | 0.00 | 0.00 | 0.00 |

Averaged over the band: P(meet) = 0.44. The requirement is met comfortably below ~25 m/s and essentially never above ~35 m/s with this geometry; the threat-speed assumption is therefore as decisive as any radar parameter and must be pinned down against a real CONOPS.

_Run time 25 s. Figures in `figures/`._
