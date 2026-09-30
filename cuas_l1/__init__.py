"""Level 1 mission-geometry model for minimum-sensing C-UAS warning."""

from .geometry import (CoverageResult, Node, Threat, WarningRequirement,
                       cost_per_warning_depth, coverage_vs_bearing,
                       first_detection_range, power_aperture_proxy,
                       r_detect_min_headon, radar_horizon, warning_depth_required,
                       warning_time, warning_time_headon)
from .scenarios import (ARCHITECTURE_CASES, BASELINE_REQ, SECTOR_WIDTHS,
                        V_C_BAND, V_C_BASELINE, ArchitectureCase)

__all__ = [n for n in dir() if not n.startswith("_")]
__version__ = "0.1.0"
