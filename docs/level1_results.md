# Level 1 results  (V_c = 30 m/s, T_req = 300 s, latency = 0 s, buffer = 0 m)

Required total warning depth along the approach axis: **9.0 km**

## Architecture cases (head-on, ideal)

| Case | R_detect (km) | D_forward (km) | T_warning (s) | Meets? | PA proxy | PA per km depth |
|---|---|---|---|---|---|---|
| Long-range at defended point | 9 | 0 | 300 | yes | 81.00 | 9.000 |
| Distributed node | 3 | 6 | 300 | yes | 1.00 | 0.111 |
| Lower-cost picket | 2 | 7 | 300 | yes | 0.20 | 0.022 |
| Short-range beside force | 2 | 0 | 67 | no | 0.20 | 0.099 |

## Sector coverage, one 3 km node 6 km forward

Warning time (s) by approach bearing relative to boresight. A forward node meets the 300 s requirement only on-axis: off-axis threats pass through the coverage disc closer to the defended point, so warning depth shrinks even before the sector edge is reached. The last column is the bearing at which the node stops seeing the threat at all.

| Sector width | 0° | 10° | 20° | 30° | 45° | 60° | Loses track beyond |
|---|---|---|---|---|---|---|---|
| 30° | 300 | — | — | — | — | — | ±4.5° |
| 60° | 300 | — | — | — | — | — | ±9.5° |
| 90° | 300 | 291 | — | — | — | — | ±14.5° |
| 360° | 300 | 291 | 261 | — | — | — | ±29.5° |

Note the 360° row: with the node this far forward, going omnidirectional buys nothing beyond ±~27°, because past that bearing the threat's path misses the 3 km disc entirely. Sector width and placement are coupled.

## Two 3 km nodes vs one, 6 km forward, 90° sectors

Bearing half-angle over which warning stays at or above a given fraction of the requirement.

| Layout | ≥300 s | ≥270 s | ≥240 s | ≥180 s | any detection |
|---|---|---|---|---|---|
| one node on axis | ±0° | ±14° | ±14° | ±14° | ±14° |
| two nodes at ±20° | ±20° | ±34° | ±34° | ±34° | ±34° |

Figures written to `figures/`
