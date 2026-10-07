# Numerical method and correctness

The domain has `width × height` nodes, including boundary nodes. Node `(x,y)` is at `(x dx, y dy)`. Domain lengths are `(width−1)dx` and `(height−1)dy`. Values are stored in row-major order, `index = y*width+x`. No ghost cells are used.

Forward Euler in time and centered second differences in space give an error of order `O(dt + dx² + dy²)` for smooth solutions. To demonstrate second-order spatial convergence, the test reduces `dt` proportionally to `h²`, so temporal error decreases at the same rate. It compares grids 17², 33², and 65² on a unit square at `t = 0.01`, starting from `sin(πx)sin(πy)`. The exact continuous solution is `exp(−2π²αt) sin(πx)sin(πy)`.

The discrete sine mode supplies a second, independent reference without spatial truncation error. Its one-step amplification is:

```text
g = 1 − 4 rx sin²(π / [2(width−1)])
      − 4 ry sin²(π / [2(height−1)])
u_n = g^n u_0
```

This validates accumulation over many steps with unequal grid spacings. A tiny hand-worked grid validates the index ordering and coefficients directly.

The stencil weights are `1−2rx−2ry`, `rx`, `rx`, `ry`, `ry`. Positive diffusivity/spacing/timestep with `rx+ry≤1/2` makes the update a convex combination, proving a discrete maximum principle and giving the explicit stability bound. The implementation validates the actual Float32 coefficients used by the kernel, including overflow/underflow. At the limiting timestep the scheme is stable but high-frequency modes can oscillate; a smaller timestep is generally preferable.

Every step reads the entire old field and writes the new field. An in-place update would be a different algorithm and is deliberately avoided. CPU boundaries survive because both arrays start from the initial field; the GPU explicitly copies boundary nodes each step. Nonzero boundary tests verify this contract. There is no periodic wrapping.

Float32 limits very fine-grid and very-long-time accuracy. Absolute parity tolerances in this project apply to normalized test fields, not arbitrary physical temperatures. For high dynamic ranges, use scaled absolute/relative tolerances, condition-aware validation and potentially Float64 on a supported backend. Apple Metal does not provide a general double-precision shader path in this implementation.

Both solvers require a finite initial field of exactly `width × height` values and a nonnegative step count. For positive step counts, each value must have magnitude at most `Float.greatestFiniteMagnitude / 8`. This conservative bound leaves headroom for the intermediate additions and differences in the Float32 stencil, even for opposite-sign neighboring values. A zero-step solve accepts every finite Float32 value and returns the initial field unchanged. The bound addresses arithmetic range; it does not improve precision or establish accuracy for high-dynamic-range fields.

`maximumError` returns positive infinity if either field contains a non-finite value, or if a finite pair's absolute difference overflows Float32. Such comparisons fail a finite parity tolerance. It requires equal-length fields.

No test claims conservation with these cold boundaries. Energy dissipates through the edges. For an insulated-boundary extension, add a consistent Neumann discretization and conservation tests.
