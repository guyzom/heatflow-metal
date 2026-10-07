import Foundation
import HeatFlow

private struct Options {
    let command: String
    var values: [String: String] = [:]
    init(_ args: [String]) throws {
        command = args.first ?? "help"
        var i = 1
        let allowed = ["backend", "size", "steps", "repeats", "output", "batch-size"]
        while i < args.count {
            guard args[i].hasPrefix("--"), i + 1 < args.count else {
                throw HeatFlowError.invalid("Options require --name value. Run heatflow help.")
            }
            let key = String(args[i].dropFirst(2))
            guard allowed.contains(key), values[key] == nil else {
                throw HeatFlowError.invalid("Unknown or duplicate option: \(args[i])")
            }
            values[key] = args[i + 1]; i += 2
        }
        let valid: [String: Set<String>] = [
            "info": [], "help": [],
            "demo": ["backend", "size", "steps", "output", "batch-size"],
            "benchmark": ["size", "steps", "repeats", "output", "batch-size"]
        ]
        guard let permitted = valid[command], Set(values.keys).isSubset(of: permitted) else {
            throw HeatFlowError.invalid("Unknown command or option not applicable to \(command).")
        }
    }
    func int(_ key: String, _ fallback: Int, minimum: Int = 1) throws -> Int {
        guard let raw = values[key] else { return fallback }
        guard let value = Int(raw), value >= minimum else {
            throw HeatFlowError.invalid("--\(key) must be an integer >= \(minimum).")
        }
        return value
    }
}

private func seconds<T>(_ operation: () throws -> T) rethrows -> (T, Double) {
    let start = DispatchTime.now().uptimeNanoseconds
    let result = try operation()
    return (result, Double(DispatchTime.now().uptimeNanoseconds - start) / 1e9)
}
private func median(_ values: [Double]) -> Double {
    let sorted = values.sorted()
    let mid = sorted.count / 2
    return sorted.count % 2 == 0 ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
}
private func writeJSON(_ value: Any, path: String) throws {
    let url = URL(fileURLWithPath: path)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
    try data.write(to: url, options: .atomic)
}

private func benchmark(_ options: Options) throws {
    let steps = try options.int("steps", 200)
    let repeats = try options.int("repeats", 5)
    let batch = try options.int("batch-size", 64)
    let sizes: [Int]
    if options.values["size"] != nil { sizes = [try options.int("size", 256, minimum: 3)] }
    else { sizes = [64, 256, 1024] }
    let cpu = CPUSolver()
    // No fallback: a benchmark requesting both solvers must have an actual GPU.
    let (gpu, setup) = try seconds { try MetalSolver(batchSize: batch) }
    var rows: [[String: Any]] = []
    print("Metal device: \(gpu.deviceName); setup \(String(format: "%.3f", setup)) s (excluded)")
    print("grid      CPU median ms    Metal median ms    CPU/Metal     max error")
    for size in sizes {
        let c = try Configuration(width: size, height: size)
        let initial = Fields.hotSpot(c)
        _ = try cpu.solve(initial, configuration: c, steps: steps)
        _ = try gpu.solve(initial, configuration: c, steps: steps)
        var cpuTimes: [Double] = [], gpuTimes: [Double] = [], deviceTimes: [Double] = []
        var maxError: Float = 0
        // Alternate order to reduce consistent thermal/order bias.
        for repeatIndex in 0..<repeats {
            let a: (Solution, Double), b: (Solution, Double)
            if repeatIndex % 2 == 0 {
                a = try seconds { try cpu.solve(initial, configuration: c, steps: steps) }
                b = try seconds { try gpu.solve(initial, configuration: c, steps: steps) }
            } else {
                b = try seconds { try gpu.solve(initial, configuration: c, steps: steps) }
                a = try seconds { try cpu.solve(initial, configuration: c, steps: steps) }
            }
            guard b.0.field.allSatisfy({ $0.isFinite }) else {
                throw HeatFlowError.execution("Metal returned a non-finite field.")
            }
            let error = maximumError(a.0.field, b.0.field)
            guard error <= 2e-5 else { throw HeatFlowError.execution("CPU/Metal mismatch: \(error)") }
            maxError = max(maxError, error)
            cpuTimes.append(a.1); gpuTimes.append(b.1); deviceTimes.append(b.0.gpuSeconds ?? 0)
        }
        let cpuMedian = median(cpuTimes), gpuMedian = median(gpuTimes)
        let updates = Double((size - 2) * (size - 2)) * Double(steps)
        let row: [String: Any] = [
            "width": size, "height": size, "steps": steps, "repeats": repeats,
            "cpu_wall_seconds": cpuTimes, "metal_wall_seconds": gpuTimes,
            "metal_command_gpu_seconds": deviceTimes,
            "cpu_median_seconds": cpuMedian, "metal_median_seconds": gpuMedian,
            "cpu_over_metal_wall_ratio": cpuMedian / gpuMedian,
            "metal_interior_updates_per_second": updates / gpuMedian,
            "max_absolute_error": maxError
        ]
        rows.append(row)
        print(String(format: "%4d²       %10.3f         %10.3f        %7.3f       %.3g",
                     size, cpuMedian * 1000, gpuMedian * 1000, cpuMedian / gpuMedian, maxError))
    }
    #if DEBUG
    let buildMode = "debug"
    #else
    let buildMode = "release"
    #endif
    let report: [String: Any] = [
        "schema_version": 1, "created_at_utc": ISO8601DateFormatter().string(from: Date()),
        "os": ProcessInfo.processInfo.operatingSystemVersionString,
        "logical_cpu_count": ProcessInfo.processInfo.processorCount,
        "physical_memory_bytes": ProcessInfo.processInfo.physicalMemory,
        "metal_device": gpu.deviceName, "unified_memory": gpu.unifiedMemory,
        "build_mode": buildMode, "precision": "Float32", "batch_size": batch,
        "dx": 1, "dy": 1, "diffusivity": 1, "dt": 0.2,
        "setup_seconds_excluded": setup, "warmups_per_backend_per_grid": 1,
        "timing_scope": "solve: validation, allocation, encoding, execution, wait, final array readback; excludes pipeline setup and initial field generation",
        "cases": rows
    ]
    let path = options.values["output"] ?? "output/benchmark.json"
    try writeJSON(report, path: path)
    print("Saved raw samples: \(path)")
}

private func demo(_ options: Options) throws {
    let size = try options.int("size", 96, minimum: 3)
    let steps = try options.int("steps", 1500, minimum: 0)
    let backend = options.values["backend"] ?? "metal"
    let solver: any HeatSolver
    switch backend {
    case "cpu": solver = CPUSolver()
    case "metal": solver = try MetalSolver(batchSize: options.int("batch-size", 64))
    default: throw HeatFlowError.invalid("--backend must be cpu or metal.")
    }
    let c = try Configuration(width: size, height: size)
    let initial = Fields.hotSpot(c)
    let snapshotSteps = [0, steps / 15, steps / 3, steps]
    var snapshots: [[Float]] = [], wall = 0.0
    for n in snapshotSteps {
        let (result, elapsed) = try seconds { try solver.solve(initial, configuration: c, steps: n) }
        snapshots.append(result.field); wall += elapsed
    }
    let directory = options.values["output"] ?? "output/demo"
    try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
    var csv = "x,y,initial,early,middle,final\n"
    for y in 0..<size {
        for x in 0..<size {
            let i = y * size + x
            csv += "\(x),\(y)," + snapshots.map { String($0[i]) }.joined(separator: ",") + "\n"
        }
    }
    try csv.write(toFile: directory + "/field.csv", atomically: true, encoding: .utf8)
    try writeJSON([
        "backend": backend, "width": size, "height": size, "dt": c.dt,
        "snapshot_steps": snapshotSteps, "snapshot_times": snapshotSteps.map { Double($0) * Double(c.dt) },
        "maxima": snapshots.map { $0.max() ?? 0 }, "solve_wall_seconds_total": wall,
        "boundary": "fixed zero Dirichlet", "precision": "Float32"
    ], path: directory + "/metadata.json")
    print("Saved \(backend) demo fields: \(directory)/field.csv")
    print("Render: python3 scripts/render_demo.py \(directory)")
}

let help = """
HeatFlow Metal — verified 2D heat diffusion
Usage:
  heatflow info
  heatflow demo [--backend metal|cpu] [--size 96] [--steps 1500] [--output output/demo]
  heatflow benchmark [--size N] [--steps 200] [--repeats 5] [--output output/benchmark.json]
  heatflow help
Metal commands accept --batch-size 64. Benchmark defaults to 64², 256², 1024².
Benchmark reports synchronized end-to-end wall time and separate command-buffer GPU time.
"""
do {
    let options = try Options(Array(CommandLine.arguments.dropFirst()))
    switch options.command {
    case "help": print(help)
    case "info":
        print("OS: \(ProcessInfo.processInfo.operatingSystemVersionString)")
        print("CPU: available; single-threaded Float32 reference")
        do {
            let gpu = try MetalSolver()
            print("Metal: \(gpu.deviceName); unified memory: \(gpu.unifiedMemory)")
        } catch { print("Metal: unavailable (\(error))") }
    case "demo": try demo(options)
    case "benchmark": try benchmark(options)
    default: break
    }
} catch {
    FileHandle.standardError.write(Data("error: \(error)\n".utf8))
    exit(1)
}
