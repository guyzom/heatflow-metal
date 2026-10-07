import Foundation

public enum HeatFlowError: Error, CustomStringConvertible {
    case invalid(String)
    case unavailable(String)
    case execution(String)
    public var description: String {
        switch self {
        case .invalid(let text), .unavailable(let text), .execution(let text): return text
        }
    }
}

/// Nodal rectangular grid including the fixed boundary; row-major index = y * width + x.
public struct Configuration {
    /// Largest absolute field value accepted when advancing one or more timesteps.
    /// Leaves headroom for the centered-difference Float32 intermediate expressions.
    public static let maximumFieldMagnitude = Float.greatestFiniteMagnitude / 8
    public let width: Int
    public let height: Int
    public let dx: Float
    public let dy: Float
    public let diffusivity: Float
    public let dt: Float
    public let rx: Float
    public let ry: Float
    public var count: Int { width * height }

    public init(width: Int, height: Int, dx: Float = 1, dy: Float = 1,
                diffusivity: Float = 1, dt: Float = 0.2) throws {
        guard width >= 3, height >= 3, width <= Int(UInt32.max), height <= Int(UInt32.max),
              width <= Int.max / height / MemoryLayout<Float>.stride else {
            throw HeatFlowError.invalid("Grid dimensions must be >= 3 and fit in memory indexing.")
        }
        guard [dx, dy, diffusivity, dt].allSatisfy({ $0.isFinite && $0 > 0 }) else {
            throw HeatFlowError.invalid("dx, dy, diffusivity and dt must be finite and positive.")
        }
        let rx = diffusivity * dt / (dx * dx)
        let ry = diffusivity * dt / (dy * dy)
        guard rx.isFinite, ry.isFinite, rx > 0, ry > 0, rx + ry <= 0.5 else {
            throw HeatFlowError.invalid("Unstable timestep: require alpha*dt*(1/dx² + 1/dy²) <= 0.5.")
        }
        self.width = width; self.height = height
        self.dx = dx; self.dy = dy; self.diffusivity = diffusivity; self.dt = dt
        self.rx = rx; self.ry = ry
    }

    public func validate(_ field: [Float], steps: Int) throws {
        guard steps >= 0, field.count == count, field.allSatisfy({ $0.isFinite }) else {
            throw HeatFlowError.invalid("Require nonnegative steps and a finite field matching the grid.")
        }
        guard steps == 0 || field.allSatisfy({ abs($0) <= Self.maximumFieldMagnitude }) else {
            throw HeatFlowError.invalid("Field exceeds the Float32 stencil arithmetic range: require abs(value) <= Float.greatestFiniteMagnitude/8 for positive steps.")
        }
    }
}

public struct Solution {
    public let field: [Float]
    /// Sum of completed Metal command-buffer GPU intervals; nil for CPU.
    public let gpuSeconds: Double?
    public init(field: [Float], gpuSeconds: Double? = nil) {
        self.field = field; self.gpuSeconds = gpuSeconds
    }
}

/// Each solver advances the same stencil and preserves the initial outer nodes (Dirichlet).
public protocol HeatSolver {
    var name: String { get }
    func solve(_ initial: [Float], configuration: Configuration, steps: Int) throws -> Solution
}

public enum Fields {
    public static func hotSpot(_ c: Configuration) -> [Float] {
        var field = [Float](repeating: 0, count: c.count)
        for y in 1..<(c.height - 1) {
            for x in 1..<(c.width - 1) {
                let nx = Float(x) / Float(c.width - 1) - 0.5
                let ny = Float(y) / Float(c.height - 1) - 0.5
                field[y * c.width + x] = exp(-80 * (nx * nx + ny * ny))
            }
        }
        return field
    }

    public static func sineMode(_ c: Configuration) -> [Float] {
        var field = [Float](repeating: 0, count: c.count)
        for y in 1..<(c.height - 1) {
            for x in 1..<(c.width - 1) {
                field[y * c.width + x] = Float(
                    sin(Double.pi * Double(x) / Double(c.width - 1)) *
                    sin(Double.pi * Double(y) / Double(c.height - 1)))
            }
        }
        return field
    }
}

/// Maximum absolute difference; infinity if either field contains a non-finite value.
public func maximumError(_ a: [Float], _ b: [Float]) -> Float {
    precondition(a.count == b.count)
    var error: Float = 0
    for (lhs, rhs) in zip(a, b) {
        guard lhs.isFinite, rhs.isFinite else { return .infinity }
        error = max(error, abs(lhs - rhs))
    }
    return error
}
