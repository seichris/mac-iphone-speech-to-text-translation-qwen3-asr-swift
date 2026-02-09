import Foundation
import MLX
import MLXNN

public enum Qwen3ASRDiagnostics {
    /// Enable via `QWEN3_ASR_DIAGNOSTICS=1`.
    public static var enabled: Bool = {
        let raw = ProcessInfo.processInfo.environment["QWEN3_ASR_DIAGNOSTICS"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        switch raw {
        case "1", "true", "yes", "y", "on":
            return true
        default:
            return false
        }
    }()

    private static var shouldRun: Bool {
        // Users often already have `QWEN3_ASR_DEBUG=1` enabled when debugging iOS issues.
        // Treat that as enough to run basic kernel sanity checks.
        enabled || Qwen3ASRDebug.enabled
    }

    /// Basic correctness check for MLX's 4-bit `quantizedMM` implementation.
    ///
    /// On some iOS devices/OS versions, the Metal backend for quantized matmul can misbehave,
    /// which would produce completely nonsensical ASR outputs (random token IDs).
    ///
    /// This test compares:
    /// - `quantizedMM(x, wq, ...)`
    /// - `matmul(x, dequantized(wq, ...).T)`
    ///
    /// It prints max/mean absolute error. If errors are large (e.g. > 1e-2), quantized kernels are suspect.
    public static func runOnDeviceAfterLoad(textDecoder: QuantizedTextModel?) {
        guard shouldRun else { return }

        // 1) Pure synthetic quantizedMM check (detects backend/kernel issues).
        runQuantizedMMSanityCheck()

        // 2) If available, validate quantizedMM against a *real* model layer weight shape.
        if let textDecoder {
            runModelLayerSanityChecks(textDecoder: textDecoder)
        }
    }

    private static func runQuantizedMMSanityCheck() {
        guard shouldRun else { return }

        let env = ProcessInfo.processInfo.environment
        let rawIters = env["QWEN3_ASR_DIAGNOSTICS_ITERS"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let iters = max(1, Int(rawIters ?? "") ?? 3)

        // Use a couple of representative GEMM sizes:
        // - small "smoke" size
        // - model-like sizes (0.6B decoder uses 1024->2048 and 1024->3072 projections)
        let cases: [(name: String, batch: Int, inDim: Int, outDim: Int)] = [
            ("smoke", 2, 128, 256),
            ("q_proj_like", 1, 1024, 2048),
            ("mlp_like", 1, 1024, 3072),
        ]

        let groupSize = 64
        let bits = 4

        print("Qwen3ASRDiagnostics: running quantizedMM sanity (iters=\(iters))")

        for (name, batch, inDim, outDim) in cases {
            for i in 0..<iters {
                // Generate FP32 reference weights, then quantize using MLX so formats match the backend expectation.
                let x = MLXRandom.normal([batch, inDim]).asType(.float32)
                let w = MLXRandom.normal([outDim, inDim]).asType(.float32)
                let (wq, scales, biases) = MLX.quantized(w, groupSize: groupSize, bits: bits, mode: .affine)

                let yQuant = quantizedMM(
                    x, wq,
                    scales: scales,
                    biases: biases,
                    transpose: true,
                    groupSize: groupSize,
                    bits: bits,
                    mode: .affine
                ).asType(.float32)

                let wDeq = dequantized(
                    wq,
                    scales: scales,
                    biases: biases,
                    groupSize: groupSize,
                    bits: bits,
                    mode: .affine,
                    dtype: .float32
                )
                let yRef = matmul(x, wDeq.transposed(1, 0)).asType(.float32)

                let diff = abs(yQuant - yRef).flattened()
                let maxAbs = max(diff).item(Float.self)
                let meanAbs = mean(diff).item(Float.self)
                print("Qwen3ASRDiagnostics: case=\(name) iter=\(i) max_abs=\(maxAbs) mean_abs=\(meanAbs)")
            }
        }
    }

    private static func runModelLayerSanityChecks(textDecoder: QuantizedTextModel) {
        let env = ProcessInfo.processInfo.environment
        let rawIters = env["QWEN3_ASR_DIAGNOSTICS_ITERS"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let iters = max(1, Int(rawIters ?? "") ?? 2)

        guard !textDecoder.layers.isEmpty else { return }

        let l0 = textDecoder.layers[0]

        // Check a couple of representative layers (these match real in/out dims + packed weight formats).
        let layers: [(String, QuantizedLinear)] = [
            ("layers.0.self_attn.q_proj", l0.selfAttn.qProj),
            ("layers.0.mlp.gate_proj", l0.mlp.gateProj),
        ]

        print("Qwen3ASRDiagnostics: running model-layer quantizedMM checks (iters=\(iters))")

        for (name, layer) in layers {
            let inDim = layer.shape.1
            let outDim = layer.shape.0
            let groupSize = layer.groupSize
            let bits = layer.bits
            let mode = layer.mode

            for i in 0..<iters {
                let x = MLXRandom.normal([1, inDim]).asType(.float32)
                let yQuant = layer(x).asType(.float32)

                // Reconstruct reference via dequantize + matmul.
                let wDeq = dequantized(
                    layer.weight,
                    scales: layer.scales,
                    biases: layer.biases,
                    groupSize: groupSize,
                    bits: bits,
                    mode: mode,
                    dtype: .float32
                )
                let yRef = matmul(x, wDeq.transposed(1, 0)).asType(.float32)
                let diff = abs(yQuant - yRef).flattened()
                let maxAbs = max(diff).item(Float.self)
                let meanAbs = mean(diff).item(Float.self)
                print("Qwen3ASRDiagnostics: layer=\(name) dims=\(inDim)->\(outDim) iter=\(i) max_abs=\(maxAbs) mean_abs=\(meanAbs)")
            }
        }
    }
}
