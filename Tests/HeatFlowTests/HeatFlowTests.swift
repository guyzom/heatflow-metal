import Testing
import Foundation
#if canImport(Metal)
import Metal
#endif

private let metalTestsEnabled: Bool = {
    if ProcessInfo.processInfo.environment["HEATFLOW_REQUIRE_METAL"] == "1" { return true }
    #if canImport(Metal)
    return MTLCreateSystemDefaultDevice() != nil
    #else
    return false
    #endif
}()
@testable import HeatFlow

@Suite(.serialized)
struct HeatFlowTests {
    @Test func testRejectsUnstableAndInvalidConfigurations() throws {
        for dt: Float in [0, -1, .nan, .infinity, 0.251] {
            expectThrows(try Configuration(width: 8, height: 8, dt: dt))
        }
        expectThrows(try Configuration(width: 2, height: 8))
        expectThrows(try Configuration(width: 8, height: 8, dx: 0))
        expectThrows(try Configuration(width: 8, height: 8, dy: .nan))
        expectThrows(try Configuration(width: 8, height: 8, diffusivity: -1))
        expectThrows(try Configuration(width: Int.max, height: 8))
        expectThrows(try Configuration(width: 8, height: 8, dx: 1e-30))
        expectNoThrow(try Configuration(width: 8, height: 8, dt: 0.25))
    }

    @Test func testFieldAndStepValidation() throws {
        let c = try Configuration(width: 3, height: 3)
        expectThrows(try CPUSolver().solve([], configuration: c, steps: 1))
        expectThrows(try CPUSolver().solve([Float](repeating: 0, count: 9), configuration: c, steps: -1))
        for value: Float in [.nan, .infinity] {
            expectThrows(try CPUSolver().solve([Float](repeating: value, count: 9), configuration: c, steps: 0))
        }
    }

    @Test func testEvolvingFieldMagnitudeRange() throws {
        let c = try Configuration(width: 3, height: 3, dt: 0.25)
        let cpu = CPUSolver()
        let limit = Configuration.maximumFieldMagnitude
        for value in [Float.greatestFiniteMagnitude, -Float.greatestFiniteMagnitude,
                      limit.nextUp, -limit.nextUp] {
            let field = [Float](repeating: value, count: c.count)
            expectThrows(try cpu.solve(field, configuration: c, steps: 1))
        }
        for value in [limit, -limit] {
            let field = [Float](repeating: value, count: c.count)
            let result = try cpu.solve(field, configuration: c, steps: 80).field
            expectTrue(result.allSatisfy({ $0.isFinite }))
            expectEqual(result, field)
        }
        // At the stable timestep, four positive neighbours turn the negative center positive.
        let field: [Float] = [limit, limit, limit, limit, -limit, limit, limit, limit, limit]
        let result = try cpu.solve(field, configuration: c, steps: 1).field
        expectTrue(result.allSatisfy({ $0.isFinite }))
        expectEqual(result[4] / limit, 1, accuracy: 1e-6)
    }

    @Test func testMaximumErrorDoesNotMaskNonfiniteValues() {
        expectEqual(maximumError([1, -2], [1.5, -1]), 1)
        expectEqual(maximumError([], []), 0)
        for value: Float in [.nan, .infinity, -.infinity] {
            for field: [Float] in [[value, 0], [0, value]] {
                expectEqual(maximumError(field, [0, 0]), .infinity)
                expectEqual(maximumError([0, 0], field), .infinity)
                expectEqual(maximumError(field, field), .infinity)
            }
        }
        expectEqual(maximumError([Float.greatestFiniteMagnitude], [-Float.greatestFiniteMagnitude]), .infinity)
    }

    @Test func testHandCalculatedAnisotropicStep() throws {
        let c = try Configuration(width: 3, height: 3, dx: 1, dy: 2, dt: 0.2)
        let field: [Float] = [0, 2, 0, 1, 10, 3, 0, 4, 0]
        let result = try CPUSolver().solve(field, configuration: c, steps: 1).field
        // 10 + 0.2*(1 - 20 + 3) + 0.05*(2 - 20 + 4) = 6.1.
        expectEqual(result[4], 6.1, accuracy: 1e-6)
        for i in [0, 1, 2, 3, 5, 6, 7, 8] { expectEqual(result[i], field[i]) }
    }

    @Test func testZeroStepsReturnsExactInput() throws {
        let c = try Configuration(width: 19, height: 13)
        let field = Fields.hotSpot(c)
        expectEqual(try CPUSolver().solve(field, configuration: c, steps: 0).field, field)
        let extremes = (0..<c.count).map {
            $0 % 2 == 0 ? Float.greatestFiniteMagnitude : -Float.greatestFiniteMagnitude
        }
        expectEqual(try CPUSolver().solve(extremes, configuration: c, steps: 0).field, extremes)
    }

    @Test func testConstantFieldIsStationary() throws {
        let c = try Configuration(width: 11, height: 7)
        let field = [Float](repeating: 3.5, count: c.count)
        expectEqual(try CPUSolver().solve(field, configuration: c, steps: 80).field, field)
    }

    @Test func testFixedNonzeroBoundaryAndMaximumPrinciple() throws {
        let c = try Configuration(width: 17, height: 9)
        let field = (0..<c.count).map { Float(($0 * 17) % 101) / 100 }
        let result = try CPUSolver().solve(field, configuration: c, steps: 300).field
        expectGreaterEqual(result.min()!, field.min()!)
        expectLessEqual(result.max()!, field.max()!)
        for y in 0..<c.height {
            for x in 0..<c.width where x == 0 || y == 0 || x == c.width - 1 || y == c.height - 1 {
                let i = y * c.width + x
                expectEqual(result[i], field[i])
            }
        }
    }

    @Test func testDiscreteSineEigenmode() throws {
        let c = try Configuration(width: 31, height: 23, dx: 0.7, dy: 1.1, dt: 0.1)
        let initial = Fields.sineMode(c)
        let steps = 170
        let gain = 1 - 4 * Double(c.rx) * pow(sin(Double.pi / Double(2 * (c.width - 1))), 2)
            - 4 * Double(c.ry) * pow(sin(Double.pi / Double(2 * (c.height - 1))), 2)
        let expected = initial.map { Float(Double($0) * pow(gain, Double(steps))) }
        let actual = try CPUSolver().solve(initial, configuration: c, steps: steps).field
        expectLess(maximumError(expected, actual), 3e-6)
    }

    @Test func testSecondOrderConvergenceAgainstContinuousSolution() throws {
        let finalTime = 0.01
        var errors: [Float] = []
        for size in [17, 33, 65] {
            let h = 1.0 / Double(size - 1)
            let steps = Int(ceil(finalTime / (0.2 * h * h)))
            let dt = finalTime / Double(steps)
            let c = try Configuration(width: size, height: size, dx: Float(h), dy: Float(h), dt: Float(dt))
            let initial = Fields.sineMode(c)
            let actual = try CPUSolver().solve(initial, configuration: c, steps: steps).field
            let expected = initial.map { Float(Double($0) * exp(-2 * Double.pi * Double.pi * finalTime)) }
            errors.append(maximumError(actual, expected))
        }
        expectGreater(errors[0] / errors[1], 3.0)
        expectGreater(errors[1] / errors[2], 3.0)
        expectLess(errors[2], 1e-4)
    }

    @Test func testCoolingSymmetryAndLongTimeDecay() throws {
        let c = try Configuration(width: 25, height: 25)
        let initial = Fields.hotSpot(c)
        let result = try CPUSolver().solve(initial, configuration: c, steps: 2000).field
        expectLess(result.max()!, 1e-5)
        expectGreaterEqual(result.min()!, 0)
        for y in 0..<c.height {
            for x in 0..<c.width {
                expectEqual(result[y * c.width + x], result[x * c.width + y], accuracy: 1e-7)
            }
        }
    }

    @Test func testSplittingTimestepsMatchesSingleRun() throws {
        let c = try Configuration(width: 15, height: 11)
        let initial = Fields.hotSpot(c)
        let cpu = CPUSolver()
        let first = try cpu.solve(initial, configuration: c, steps: 13).field
        let split = try cpu.solve(first, configuration: c, steps: 18).field
        expectEqual(split, try cpu.solve(initial, configuration: c, steps: 31).field)
    }

    private func metal(batchSize: Int = 64) throws -> MetalSolver {
        try MetalSolver(batchSize: batchSize)
    }

    @Test(.enabled(if: metalTestsEnabled, "No accessible Metal GPU")) func testMetalParityOddRectangularGridsAndBatchTransitions() throws {
        let gpu = try metal()
        let c = try Configuration(width: 33, height: 19, dx: 0.7, dy: 1.1, dt: 0.1)
        let initial = (0..<c.count).map { Float(($0 * 31) % 103) / 103 }
        for steps in [0, 1, 2, 63, 64, 65, 129] {
            let expected = try CPUSolver().solve(initial, configuration: c, steps: steps).field
            let actual = try gpu.solve(initial, configuration: c, steps: steps)
            expectTrue(actual.field.allSatisfy({ $0.isFinite }))
            expectLessEqual(maximumError(expected, actual.field), 2e-5, "steps=\(steps)")
            expectNotNil(actual.gpuSeconds)
        }
    }

    @Test(.enabled(if: metalTestsEnabled, "No accessible Metal GPU")) func testMetalMinimumGridAndFixedEdges() throws {
        let gpu = try metal(batchSize: 1)
        let c = try Configuration(width: 3, height: 3)
        let initial: [Float] = [1, 2, 3, 4, 9, 6, 7, 8, 9]
        let actual = try gpu.solve(initial, configuration: c, steps: 7).field
        let expected = try CPUSolver().solve(initial, configuration: c, steps: 7).field
        expectLess(maximumError(actual, expected), 1e-5)
        for i in [0, 1, 2, 3, 5, 6, 7, 8] { expectEqual(actual[i], initial[i]) }
    }

    @Test(.enabled(if: metalTestsEnabled, "No accessible Metal GPU")) func testMetalDeterminismAndInvalidInputs() throws {
        let gpu = try metal()
        let c = try Configuration(width: 64, height: 64, dt: 0.25)
        let initial = Fields.hotSpot(c)
        let a = try gpu.solve(initial, configuration: c, steps: 200).field
        let b = try gpu.solve(initial, configuration: c, steps: 200).field
        expectEqual(a, b)
        expectThrows(try gpu.solve([], configuration: c, steps: 1))
        expectThrows(try gpu.solve(initial, configuration: c, steps: -1))
        for value in [Float.greatestFiniteMagnitude, -Float.greatestFiniteMagnitude] {
            let field = [Float](repeating: value, count: c.count)
            expectThrows(try gpu.solve(field, configuration: c, steps: 1))
            expectEqual(try gpu.solve(field, configuration: c, steps: 0).field, field)
        }
        expectThrows(try MetalSolver(batchSize: 0))
    }
}
