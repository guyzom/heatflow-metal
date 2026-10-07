import Foundation
#if canImport(Metal)
import Metal

private struct Parameters {
    var width: UInt32
    var height: UInt32
    var rx: Float
    var ry: Float
}

/// Synchronous public interface: shared storage, tracked hazards, ping-pong buffers.
/// Instances must not be called concurrently. Pipeline compilation occurs at initialization.
public final class MetalSolver: HeatSolver {
    public let name = "metal"
    public let deviceName: String
    public let unifiedMemory: Bool
    public let batchSize: Int
    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pipeline: MTLComputePipelineState

    public init(batchSize: Int = 64) throws {
        guard batchSize > 0 else { throw HeatFlowError.invalid("Batch size must be positive.") }
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            throw HeatFlowError.unavailable("No accessible Metal GPU. Use --backend cpu.")
        }
        guard let url = Bundle.module.url(forResource: "heat", withExtension: "metal") else {
            throw HeatFlowError.execution("Missing bundled Metal shader.")
        }
        let source = try String(contentsOf: url, encoding: .utf8)
        let options = MTLCompileOptions()
        options.fastMathEnabled = false
        let library = try device.makeLibrary(source: source, options: options)
        guard let function = library.makeFunction(name: "heatStep") else {
            throw HeatFlowError.execution("Missing heatStep kernel.")
        }
        self.pipeline = try device.makeComputePipelineState(function: function)
        self.device = device; self.queue = queue; self.batchSize = batchSize
        self.deviceName = device.name; self.unifiedMemory = device.hasUnifiedMemory
    }

    public func solve(_ initial: [Float], configuration c: Configuration, steps: Int) throws -> Solution {
        try c.validate(initial, steps: steps)
        // Shader uint indexing must not overflow even on a 64-bit host.
        guard c.count <= Int(UInt32.max) else {
            throw HeatFlowError.invalid("Metal grid exceeds 32-bit shader indexing.")
        }
        guard steps > 0 else { return Solution(field: initial, gpuSeconds: 0) }
        let byteCount = c.count * MemoryLayout<Float>.stride
        let first = initial.withUnsafeBytes {
            device.makeBuffer(bytes: $0.baseAddress!, length: byteCount, options: .storageModeShared)
        }
        guard var current = first,
              var next = device.makeBuffer(length: byteCount, options: .storageModeShared) else {
            throw HeatFlowError.execution("Metal buffer allocation failed.")
        }
        var params = Parameters(width: UInt32(c.width), height: UInt32(c.height), rx: c.rx, ry: c.ry)
        let threads = MTLSize(width: pipeline.threadExecutionWidth,
                              height: min(8, pipeline.maxTotalThreadsPerThreadgroup / pipeline.threadExecutionWidth),
                              depth: 1)
        let grid = MTLSize(width: c.width, height: c.height, depth: 1)
        var completed = 0
        var gpuSeconds = 0.0
        while completed < steps {
            guard let command = queue.makeCommandBuffer() else {
                throw HeatFlowError.execution("Metal command buffer creation failed.")
            }
            for _ in 0..<min(batchSize, steps - completed) {
                // A separate serial encoder per step gives tracked buffers an inter-dispatch dependency.
                guard let encoder = command.makeComputeCommandEncoder() else {
                    throw HeatFlowError.execution("Metal compute encoder creation failed.")
                }
                encoder.setComputePipelineState(pipeline)
                encoder.setBuffer(current, offset: 0, index: 0)
                encoder.setBuffer(next, offset: 0, index: 1)
                encoder.setBytes(&params, length: MemoryLayout<Parameters>.stride, index: 2)
                encoder.dispatchThreads(grid, threadsPerThreadgroup: threads)
                encoder.endEncoding()
                swap(&current, &next)
            }
            command.commit()
            command.waitUntilCompleted()
            guard command.status == .completed else {
                throw HeatFlowError.execution(command.error?.localizedDescription ?? "Metal command failed.")
            }
            gpuSeconds += command.gpuEndTime - command.gpuStartTime
            completed += min(batchSize, steps - completed)
        }
        let pointer = current.contents().bindMemory(to: Float.self, capacity: c.count)
        return Solution(field: Array(UnsafeBufferPointer(start: pointer, count: c.count)), gpuSeconds: gpuSeconds)
    }
}
#else
public final class MetalSolver: HeatSolver {
    public let name = "metal"
    public let deviceName = "unavailable"
    public let unifiedMemory = false
    public init(batchSize: Int = 64) throws {
        throw HeatFlowError.unavailable("Metal requires macOS and an accessible Metal GPU. Use --backend cpu.")
    }
    public func solve(_ initial: [Float], configuration: Configuration, steps: Int) throws -> Solution {
        throw HeatFlowError.unavailable("Metal is unavailable on this platform.")
    }
}
#endif
