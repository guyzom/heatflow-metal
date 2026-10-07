#!/usr/bin/env python3
"""Check checked-in benchmark calculations and demo field invariants independently."""
import csv
import json
import math
import statistics
from pathlib import Path

root = Path(__file__).resolve().parents[1]
report = json.loads((root / "benchmarks/m1-pro.json").read_text())
assert report["build_mode"] == "release"
assert report["metal_device"] == "Apple M1 Pro"
for case in report["cases"]:
    for key in ["cpu_wall_seconds", "metal_wall_seconds", "metal_command_gpu_seconds"]:
        assert len(case[key]) == case["repeats"]
        assert all(math.isfinite(x) and x > 0 for x in case[key])
    cpu = statistics.median(case["cpu_wall_seconds"])
    gpu = statistics.median(case["metal_wall_seconds"])
    assert math.isclose(case["cpu_median_seconds"], cpu)
    assert math.isclose(case["metal_median_seconds"], gpu)
    assert math.isclose(case["cpu_over_metal_wall_ratio"], cpu / gpu)
    assert 0 <= case["max_absolute_error"] <= 2e-5
    assert all(a <= b for a, b in zip(case["metal_command_gpu_seconds"], case["metal_wall_seconds"]))
metadata = json.loads((root / "examples/demo/metadata.json").read_text())
with (root / "examples/demo/field.csv").open() as source:
    rows = list(csv.DictReader(source))
assert metadata["backend"] == "metal"
assert len(rows) == metadata["width"] * metadata["height"]
for i, row in enumerate(rows):
    x, y = int(row["x"]), int(row["y"])
    assert (x, y) == (i % metadata["width"], i // metadata["width"])
    for key in ["initial", "early", "middle", "final"]:
        value = float(row[key])
        assert math.isfinite(value) and 0 <= value <= 1
        if x in [0, metadata["width"] - 1] or y in [0, metadata["height"] - 1]:
            assert value == 0
for key, maximum in zip(["initial", "early", "middle", "final"], metadata["maxima"]):
    assert math.isclose(max(float(row[key]) for row in rows), maximum, abs_tol=1e-7)
assert all(a > b for a, b in zip(metadata["maxima"], metadata["maxima"][1:]))
assert (root / "examples/demo/heat-diffusion.png").read_bytes().startswith(b"\x89PNG\r\n\x1a\n")
print("Benchmark calculations and 9,216 demo nodes verified")
