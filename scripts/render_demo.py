#!/usr/bin/env python3
"""Render solver-produced CSV, never a fabricated simulation. Requires matplotlib/numpy."""
import argparse
import csv
import json
import os
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("directory", nargs="?", default="output/demo", type=Path)
args = parser.parse_args()
os.environ.setdefault("MPLCONFIGDIR", str(Path(".cache/matplotlib").resolve()))
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

metadata = json.loads((args.directory / "metadata.json").read_text())
with (args.directory / "field.csv").open() as source:
    rows = list(csv.DictReader(source))
shape = (metadata["height"], metadata["width"])
fig, axes = plt.subplots(1, 4, figsize=(14, 4.4), layout="constrained")
for ax, key, step, time in zip(axes, ["initial", "early", "middle", "final"],
                             metadata["snapshot_steps"], metadata["snapshot_times"]):
    field = np.array([float(row[key]) for row in rows]).reshape(shape)
    image = ax.imshow(field, origin="lower", cmap="inferno", vmin=0, vmax=1,
                      interpolation="nearest", extent=[0, shape[1] - 1, 0, shape[0] - 1])
    ax.set_title(f"Step {step:,} · t = {time:.1f}", fontsize=11)
    ax.set_xlabel("x (grid units)")
    ax.set_ylabel("y (grid units)")
fig.colorbar(image, ax=axes, shrink=0.68, label="Normalized temperature (fixed scale)")
fig.suptitle("HeatFlow Metal | 2D diffusion from a hot spot", fontsize=17, fontweight="bold")
fig.get_layout_engine().set(rect=(0, 0.08, 1, 1))
fig.text(0.5, 0.025,
         f"{metadata['backend'].upper()} · Float32 · dt = {metadata['dt']:.1f} · zero Dirichlet edges · Guy Zomer",
         ha="center", fontsize=10, color="#555555")
fig.savefig(args.directory / "heat-diffusion.png", dpi=160)
plt.close(fig)
print(args.directory / "heat-diffusion.png")
