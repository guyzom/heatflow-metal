#!/usr/bin/env python3
"""Dependency-free CLI smoke/error-contract checks for the compiled release binary."""
import json
import subprocess
import tempfile
from pathlib import Path

binary = Path(__file__).resolve().parents[1] / ".build/release/heatflow"
for args in [
    ["wat"], ["demo", "--backend", "cuda"], ["demo", "--size", "2"],
    ["demo", "--steps", "-1"], ["benchmark", "--repeats", "0"],
    ["demo", "--size", "nan"], ["demo", "--size"],
    ["info", "--steps", "2"], ["demo", "--unknown", "1"],
    ["demo", "--size", "8", "--size", "9"],
]:
    result = subprocess.run([str(binary), *args], capture_output=True, text=True)
    assert result.returncode != 0 and "error:" in result.stderr, (args, result)
with tempfile.TemporaryDirectory() as directory:
    subprocess.run([str(binary), "demo", "--backend", "cpu", "--size", "8",
                    "--steps", "0", "--output", directory], check=True)
    metadata = json.loads((Path(directory) / "metadata.json").read_text())
    assert metadata["snapshot_steps"] == [0, 0, 0, 0]
    assert len((Path(directory) / "field.csv").read_text().splitlines()) == 65
print("11 CLI checks passed")
