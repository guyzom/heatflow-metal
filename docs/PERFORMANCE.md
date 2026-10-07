# Measured performance

Captured on 2026-10-03T22:09:18Z using an Apple M1 Pro MacBook Pro, 8 CPU cores (6 performance + 2 efficiency), 14 GPU cores, 16 GiB unified memory, macOS 27.0.1, and Apple Swift 6.4. The Mac was connected to AC power when checked after the run. No power settings were changed. Background processes and thermals were not controlled.

The committed samples preserve that dated run. They are historical measurements, not timings for every later revision; rerun the release benchmark to measure the current checkout.

**These are actual synchronized Metal results, compared with the single-threaded Swift CPU reference.** They are not CUDA results or a comparison against an optimized multicore CPU solver.

Each case advances 200 timesteps from the same normalized hot spot, with `dx = dy = α = 1`, `dt = 0.2`, Float32, fixed zero boundary nodes, and Metal batches of 64. Each backend receives one complete warmup per grid and five measured solves. Execution order alternates between CPU-first and Metal-first.

| Grid | CPU median (ms) | Metal wall median (ms) | CPU / Metal wall | Metal wall range (ms) | Max absolute difference |
|---|---:|---:|---:|---:|---:|
| 64² | 0.942 | 2.218 | 0.425× | 2.044–2.305 | 2.98e-08 |
| 256² | 16.563 | 2.938 | 5.637× | 2.661–3.545 | 1.79e-07 |
| 1024² | 263.089 | 15.308 | 17.186× | 9.225–16.902 | 1.79e-07 |

At 64² the CPU is faster: dispatch and synchronization overhead dominate this small workload. The measured Metal wall-time advantage grows at larger grids. At 1024² it is 17.19× relative to this reference, but the GPU samples vary materially. Five samples on one machine cannot establish a portable speedup or characterize sustained thermal performance.

## What is timed

- Wall time uses `DispatchTime` (a monotonic clock) around `solve`, including field validation, per-solve allocation, input copying, encoding, GPU execution, waits, and final array readback. The CPU scope includes validation and its array allocations/updates.
- Shader/pipeline compilation, device/queue creation, initial hot-spot generation, JSON writing and plotting are excluded. GPU setup was 35.86 ms in this run and is retained in the raw report. This is a warmed execution comparison, not cold process startup.
- Separate `metal_command_gpu_seconds` samples sum `gpuEndTime−gpuStartTime` over completed command buffers. These are command-buffer GPU intervals, not pure kernel-only timings. They omit host overhead and are never used in the speedup ratio.
- The ratio is median CPU wall time divided by median Metal wall time. A ratio below 1 means the GPU is slower. These are medians of each backend, not the median of paired ratios.
- Interior updates per second count `(width−2)(height−2)steps` divided by Metal wall time. GPU boundary copying is still included in the elapsed time.

## Reproduce

```sh
HEATFLOW_REQUIRE_METAL=1 ./scripts/swift.sh test -c release
./scripts/benchmark.sh --output output/benchmark.json
# A single workload or a different batch size:
./scripts/benchmark.sh --size 512 --steps 1000 --repeats 7 --batch-size 32 --output output/custom.json
```

Default GPU execution requires a host process with Metal device access. Some process sandboxes hide the GPU; `heatflow info` reports this and Metal commands fail explicitly. Run from a normal local terminal if appropriate. Do not treat a skipped GPU test as GPU validation.

Every measured CPU/Metal pair is checked for finite GPU output and maximum absolute error ≤ `2e-5`. Mismatches abort the benchmark before a success report is written. Use release mode: debug mode is reported in JSON, and should not be compared with these results.

## Evidence

- [Raw JSON samples](../benchmarks/m1-pro.json): all wall and GPU intervals, medians, ratios, errors, date, precision, hardware and timing scope.
- [Console output](../benchmarks/m1-pro-console.txt).
- [Toolchain and OS](../benchmarks/toolchain.txt), with no machine serial numbers.
- [Release tests](../benchmarks/tests-release.txt), with Metal required rather than skipped.
- [Demo fields and rendering](../examples/demo).

## Limits and next work

The reference intentionally uses one CPU thread and a straightforward stencil. Threaded CPU and explicit SIMD baselines would make a stronger hardware comparison. A shared-memory/tiled GPU kernel, reusable workspaces, fewer encoders, or asynchronous independent simulations may reduce overhead; each requires new correctness and timing verification. The current implementation favors clear data dependencies and bounded command batches. Large-scale problems may benefit more from an implicit method or a different numerical algorithm than from accelerating this explicit stencil. CUDA support is a future NVIDIA-only backend, not an existing capability.
