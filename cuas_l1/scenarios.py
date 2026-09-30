"""
Named scenarios from the project concept brief, so every plot and test refers to the
same numbers. Change a value here and everything downstream follows.
"""

from __future__ import annotations

from dataclasses import dataclass

from .geometry import Node, WarningRequirement

# Provisional mission requirement: 5 minutes, no latency, no action buffer.
# Latency and buffer are deliberately zero at Level 1 so the ideal geometry
# is reproduced exactly; Level 2 replaces them with distributions.
BASELINE_REQ = WarningRequirement(t_required=300.0, t_latency=0.0, r_action=0.0)

# Representative closure speed used throughout the handoff.
V_C_BASELINE = 30.0

# Threat speed band for Group 1-2 UAS (m/s).
V_C_BAND = (10.0, 50.0)


@dataclass(frozen=True)
class ArchitectureCase:
    name: str
    r_detect: float     # m
    d_forward: float    # m
    note: str = ""

    def node(self, sector_width: float = 90.0) -> Node:
        return Node(x=self.d_forward, y=0.0, r_detect=self.r_detect,
                    sector_width=sector_width, boresight=0.0)


# The four rows of the handoff's "Architecture" table.
ARCHITECTURE_CASES = [
    ArchitectureCase("Long-range at defended point", 9000.0, 0.0,
                     "one exquisite radar co-located with the asset"),
    ArchitectureCase("Distributed node", 3000.0, 6000.0,
                     "candidate attritable node pushed 6 km forward"),
    ArchitectureCase("Lower-cost picket", 2000.0, 7000.0,
                     "cheaper node pushed further forward"),
    ArchitectureCase("Short-range beside force", 2000.0, 0.0,
                     "what you get if you do not push forward"),
]

# Sector widths the handoff treats as the candidate set.
SECTOR_WIDTHS = (30.0, 60.0, 90.0)

# Sweep grids for the range-vs-placement study (m).
R_DETECT_GRID = (1000.0, 5000.0, 81)     # start, stop, n
D_FORWARD_GRID = (0.0, 10000.0, 101)
