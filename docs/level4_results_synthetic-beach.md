# Level 4 results — synthetic-beach

Grid 801×801 at 30 m, elevation 0–365 m. Threat: 30 m/s, bearing uniform ±30° from the axis, 30 m AGL terrain-following. Node: 3 km, 90° sector on-axis, mast 2 m. Level 2 chain defaults otherwise.

## 1. LOS fraction of the 90° × 3 km footprint along the axis

| D_forward (km) | 2.00 | 2.50 | 3.00 | 3.50 | 4.00 | 4.50 | 5.00 | 5.50 | 6.00 | 6.50 | 7.00 | 7.50 | 8.00 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| mast 2 m, threat 30 m AGL | 1.00 | 1.00 | 1.00 | 0.99 | 0.88 | 0.63 | 0.31 | 0.12 | 0.03 | 0.17 | 0.98 | 0.94 | 0.91 |
| mast 6 m, threat 30 m AGL | 1.00 | 1.00 | 1.00 | 0.99 | 0.88 | 0.63 | 0.32 | 0.12 | 0.04 | 0.39 | 0.99 | 0.94 | 0.92 |
| mast 2 m, threat 100 m AGL | 1.00 | 1.00 | 1.00 | 1.00 | 0.99 | 0.78 | 0.49 | 0.21 | 0.09 | 0.51 | 1.00 | 1.00 | 1.00 |

## 2. Placement candidates (corridor prior ±30°)

| rank | x (km) | y (km) | ground (m) | LOS frac | P(track) | P(meet) | dominant cover |
|---|---|---|---|---|---|---|---|
| 1 | 7.0 | -1.5 | 144 | 1.00 | 0.42 | **0.41** | grass |
| 2 | 7.0 | 0.0 | 236 | 0.98 | 0.41 | **0.40** | grass |
| 3 | 8.0 | 0.0 | 122 | 0.91 | 0.40 | **0.39** | grass |
| 4 | 7.0 | -3.0 | 188 | 1.00 | 0.40 | **0.39** | grass |
| 5 | 7.0 | 3.0 | 292 | 1.00 | 0.39 | **0.38** | grass |
| 6 | 8.0 | -1.5 | 115 | 1.00 | 0.38 | **0.38** | grass |
| 7 | 8.0 | -3.0 | 118 | 1.00 | 0.37 | **0.37** | grass |
| 8 | 8.0 | 3.0 | 127 | 0.95 | 0.35 | **0.34** | grass |
| 9 | 7.0 | 1.5 | 149 | 0.62 | 0.29 | **0.29** | grass |
| 10 | 8.0 | 1.5 | 54 | 0.46 | 0.16 | **0.14** | trees |

Flat-earth Level 2 at the nominal (6.0, 0.0) km position: P(meet) = 0.21. On this terrain the same position gives 0.00 (LOS 3%); the best candidate on the grid is (7.0, -1.5) km at 144 m ground with P(meet) = 0.41 (LOS 100%).

## 3. Mast height vs threat altitude

**nominal (6.0, 0.0) km** — cells are P(meet) (LOS fraction); rows mast height, columns threat AGL.

| mast \ AGL | 15 m | 30 m | 60 m | 120 m |
|---|---|---|---|---|
| 2 m | 0.00 (0.02) | 0.00 (0.03) | 0.00 (0.06) | 0.00 (0.10) |
| 6 m | 0.00 (0.03) | 0.00 (0.04) | 0.00 (0.07) | 0.00 (0.12) |
| 12 m | 0.00 (0.04) | 0.00 (0.05) | 0.00 (0.08) | 0.00 (0.14) |

**best (7.0, -1.5) km** — cells are P(meet) (LOS fraction); rows mast height, columns threat AGL.

| mast \ AGL | 15 m | 30 m | 60 m | 120 m |
|---|---|---|---|---|
| 2 m | 0.42 (1.00) | 0.41 (1.00) | 0.42 (1.00) | 0.39 (1.00) |
| 6 m | 0.40 (1.00) | 0.42 (1.00) | 0.43 (1.00) | 0.44 (1.00) |
| 12 m | 0.40 (1.00) | 0.41 (1.00) | 0.41 (1.00) | 0.43 (1.00) |

## Interpretation

- Terrain masking is first-order. At the nominal (6.0, 0.0) km position flat-earth Level 2 gives P(meet) = 0.21; on this terrain it gives 0.00 with 3% of the footprint in line of sight. Moving to the best grid site, (7.0, -1.5) km at 144 m, recovers 0.41 with 100% LOS.
- The Level 2 placement rule ('Level 1 position plus a chain budget') must be applied on the ground: the useful forward distance is the nearest crest, saddle or shoulder that looks into the corridor, not a number on a map. Placement is a terrain problem before it is a range problem.
- At the nominal site, raising the mast from 2 to 12 m adds +0.02 to the LOS fraction (30 m AGL threat), while a threat at 120 m instead of 15 m AGL adds +0.08 (2 m mast); P(meet) there is at most 0.00 in any cell. Neither a practical mast nor a higher-flying threat rescues a masked site — only moving does. Threat altitude still outweighs mast height and belongs next to threat speed on the list of open assumptions.
- Land-cover shares of each candidate's visible footprint are recorded for Level 3 clutter modelling (a site looking over shrub and trees is a different radar problem from one looking over grass or water).

_Run time 14 s._
