"""
Run the whole simulation stack in order and report what was produced.

    python scripts/run_all.py              # everything (~2-3 min)
    python scripts/run_all.py --quick      # coarse grids (~1 min)
    python scripts/run_all.py --skip-dem   # skip the real-terrain run
    python scripts/run_all.py --only 3     # just Level 3

Levels run in dependency order: 1 (geometry) -> 2 (Monte Carlo) -> 4 (terrain)
-> 3 (radar physics). Level 3 is last because it consumes Levels 1-2 through
the detection hook and reports the feedback into placement.
"""

from __future__ import annotations

import argparse
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PY = sys.executable

# Real-terrain run: Camp Pendleton coastline (Red Beach stretch), inland axis.
DEM = ROOT / "data" / "Copernicus_DSM_COG_10_N33_00_W118_00_DEM.tif"
LANDCOVER = ROOT / "data" / "ESA_WorldCover_10m_2021_v200_N33W120_Map.tif"
SITE = ["--lon", "-117.463", "--lat", "33.29", "--axis", "52"]


def run(label: str, args: list[str]) -> bool:
    print(f"\n{'='*70}\n  {label}\n{'='*70}", flush=True)
    t0 = time.time()
    r = subprocess.run([PY, *args], cwd=ROOT)
    ok = r.returncode == 0
    print(f"  -> {'ok' if ok else 'FAILED'} in {time.time()-t0:.0f} s", flush=True)
    return ok


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--quick", action="store_true", help="coarse grids, fewer trials")
    ap.add_argument("--skip-dem", action="store_true", help="skip the real-terrain Level 4 run")
    ap.add_argument("--skip-tests", action="store_true")
    ap.add_argument("--only", type=str, default=None, help="run only level 1|2|3|4")
    args = ap.parse_args()
    q = ["--quick"] if args.quick else []
    only = args.only

    results = {}

    if not args.skip_tests and only is None:
        results["tests"] = run("TESTS", ["-m", "pytest", "-q"])

    if only in (None, "1"):
        results["level 1 (geometry)"] = run(
            "LEVEL 1 - mission geometry", ["scripts/run_level1.py"])

    if only in (None, "2"):
        results["level 2 (monte carlo)"] = run(
            "LEVEL 2 - imperfect warning chain", ["scripts/run_level2.py", *q])

    if only in (None, "4"):
        results["level 4 (synthetic beach)"] = run(
            "LEVEL 4 - terrain, synthetic beach", ["scripts/run_level4.py", *q])
        if not args.skip_dem:
            if DEM.exists():
                cmd = ["scripts/run_level4.py", "--dem", str(DEM), *SITE, *q]
                if LANDCOVER.exists():
                    cmd += ["--landcover", str(LANDCOVER)]
                results["level 4 (real DEM)"] = run("LEVEL 4 - terrain, Camp Pendleton DEM", cmd)
            else:
                print(f"\n[skip] real-terrain run: {DEM.name} not found in data/.")
                print("       See HANDOFF.md 'Data files' for the download URL.")

    if only in (None, "3"):
        results["level 3 (radar physics)"] = run(
            "LEVEL 3 - radar link budget", ["scripts/run_level3.py"])

    print(f"\n{'='*70}\n  SUMMARY\n{'='*70}")
    for k, v in results.items():
        print(f"  {'PASS' if v else 'FAIL'}  {k}")
    print(f"\n  figures -> {ROOT/'figures'}")
    print(f"  results -> {ROOT/'docs'}")
    print("\n  MATLAB (run locally, not from here):")
    print("    >> cd matlab; aeris_scope_sim            % animated radar scope + MP4")
    print("    >> aeris_nexus_linkbudget                % Level 3 cross-check")
    return 0 if all(results.values()) else 1


if __name__ == "__main__":
    sys.exit(main())
