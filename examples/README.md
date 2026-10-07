# Reproduce the demo

The checked-in `demo/field.csv` and `demo/metadata.json` were produced by the actual Metal solver on an Apple M1 Pro. The PNG uses those exact fields, with one fixed 0–1 color scale across four snapshots. All four snapshots are independently advanced from the same initial condition; the metadata stores the step counts and physical times.

From the repository root:

```sh
./scripts/swift.sh build -c release
.build/release/heatflow demo --backend metal --size 96 --steps 1500 --output output/demo
python3 scripts/render_demo.py output/demo
```

Optional plotting dependencies are pinned in `requirements-demo.txt`. Use `--backend cpu` on machines without Metal. The initial profile is `exp(−80[(x/Lx−0.5)²+(y/Ly−0.5)²])` for interior nodes; the outer nodes are set to zero. Spacings and diffusivity equal 1 and timestep equals 0.2 in consistent arbitrary units. This depicts diffusion and loss through cold fixed edges, not heat conservation.
