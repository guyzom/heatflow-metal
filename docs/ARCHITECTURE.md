# Architecture

`Configuration` is immutable and validates indexing and the stability coefficients before allocation. `HeatSolver.solve` accepts a finite full field and nonnegative step count and returns an owned full field. All outer nodes retain their initial values. `Solution.gpuSeconds` is absent for CPU results, so callers cannot mistake CPU wall time for GPU execution.

## CPU

Two arrays alternate roles. Unsafe buffer access removes repeated bounds checks in the hot loop after shape validation. This is a synchronous single-threaded reference; no external numerical library is required. Release compilation is essential for meaningful benchmarking.

## Metal

The backend creates the default Metal device and compiles the bundled readable shader once per solver instance, with fast math disabled. Grid dimensions and coefficients form a 16-byte parameter structure matching Metal's `uint,uint,float,float` layout. The Metal backend rejects grids larger than 32-bit shader indexing.

Each solve allocates two `storageModeShared` buffers. The input is copied into the first. Each dispatch writes every valid node, including edges, so the second needs no initialization. The threadgroup uses the pipeline execution width and up to eight rows. The bounds guard also documents the kernel's indexing contract for future rounded dispatches.

Every timestep has a separate serial compute encoder. Default tracked-resource hazards enforce the read/write dependency between successive ping-pong buffers. Up to 64 timesteps are encoded into one command buffer, then the CPU waits for completion before continuing. This bounds command-encoding memory and reduces submission overhead while preserving ordering. The final buffer is copied into a Swift array only after completed status is checked. On Apple Silicon, shared physical memory avoids a discrete PCIe transfer, but allocation, initial copy, synchronization and final array copy still cost time.

The public interface is intentionally synchronous, and an instance should not be used concurrently. An asynchronous/streaming interface could overlap independent simulations but would complicate correctness and timing. It is outside this project's scope.

## Extension to CUDA

A practical next step would be a separate C++/CUDA library exposing a C ABI, called from a Swift adapter implementing `HeatSolver`. Keep the CPU and analytical tests as the contract, map one thread to a node, and preserve two-buffer updates and fixed edges. Handle device availability explicitly. Use CUDA events for optional device diagnostics, and CPU monotonic wall time around allocation, H2D input, kernel launches, synchronization and D2H output for end-to-end results. NVIDIA hardware is needed to verify that backend; this Apple GPU cannot provide CUDA validation.

## References

- [Apple: performing calculations on a GPU](https://developer.apple.com/documentation/metal/performing-calculations-on-a-gpu)
- [Metal command buffer GPU start time](https://developer.apple.com/documentation/metal/mtlcommandbuffer/gpustarttime)
- [Metal command buffer GPU end time](https://developer.apple.com/documentation/metal/mtlcommandbuffer/gpuendtime)

These APIs describe the compute execution and timestamp mechanism used here. The numerical derivations above and in `NUMERICS.md` specify this project's discretization rather than relying on an opaque solver library.
