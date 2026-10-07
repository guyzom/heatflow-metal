# Development and verification

With full Xcode, run the following from the repository root:

```sh
swift test --disable-xctest
swift test --disable-xctest -c release
swift build -c release
python3 scripts/check_cli.py
python3 scripts/verify_artifacts.py
```

On a machine expected to expose a Metal GPU, set `HEATFLOW_REQUIRE_METAL=1` for both test commands so an inaccessible device fails verification. Without that setting, Swift Testing explicitly skips device tests when Metal is unavailable. Metal compilation or execution failures still fail enabled tests. The artifact check validates the recorded benchmark calculations and demo data; it does not establish GPU access on the current machine.

The [correctness workflow](../.github/workflows/ci.yml) runs these checks on a standard macOS runner. GPU execution depends on the device exposed by the runner. Tests are serialized to avoid simultaneous GPU workloads and timing-dependent interference. No benchmark timing from hosted CI is used in the recorded performance comparison.

## Command Line Tools compatibility

Standalone Xcode Command Line Tools may ship Swift Testing without XCTest or require explicit framework/macro-plugin discovery. The `scripts/swift.sh` wrapper supports that layout with local caches, native SwiftPM, `--disable-xctest` for tests, and Testing framework/plugin paths when present. Run `HEATFLOW_REQUIRE_METAL=1 ./scripts/verify.sh` for release numerical/device tests, a release build, CLI checks and recorded-artifact checks; omit the environment variable on a CPU-only host. For debug tests, use `./scripts/swift.sh test`.

The wrapper disables the SwiftPM subprocess sandbox for local compilation. Native build mode is deprecated in Swift 6.4. If a future toolchain removes it, use full Xcode with the standard commands above or adapt the wrapper to that toolchain and rerun verification.

Simulation code has no external dependencies. `requirements-demo.txt` pins the optional Python packages used to render the figure. No Python installation is required for the Swift numerical/Metal test suite.

## Repository policy

Generated build/cache/environment folders and ad hoc `output/` files are ignored. The small reference CSV/PNG, JSON benchmark samples and device verification logs are checked in for inspectable evidence. Update the performance document and raw data together when recording a new run. Keep measurement provenance, baseline scope and variability visible. A new backend requires device execution and parity/analytical tests in addition to source compilation.
