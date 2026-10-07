/// Single-threaded Float32 reference. Two arrays implement a Jacobi update, never in-place.
public struct CPUSolver: HeatSolver {
    public let name = "cpu"
    public init() {}
    public func solve(_ initial: [Float], configuration c: Configuration, steps: Int) throws -> Solution {
        try c.validate(initial, steps: steps)
        guard steps > 0 else { return Solution(field: initial) }
        var current = initial
        var next = initial
        for _ in 0..<steps {
            current.withUnsafeBufferPointer { src in
                next.withUnsafeMutableBufferPointer { dst in
                    for y in 1..<(c.height - 1) {
                        for x in 1..<(c.width - 1) {
                            let i = y * c.width + x
                            let center = src[i]
                            dst[i] = center + c.rx * (src[i - 1] - 2 * center + src[i + 1])
                                + c.ry * (src[i - c.width] - 2 * center + src[i + c.width])
                        }
                    }
                }
            }
            swap(&current, &next)
        }
        return Solution(field: current)
    }
}
