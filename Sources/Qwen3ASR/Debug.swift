import Foundation

enum Qwen3ASRDebug {
    // Evaluate once to avoid repeatedly reading ProcessInfo.
    static let enabled: Bool = {
        let raw = ProcessInfo.processInfo.environment["QWEN3_ASR_DEBUG"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        switch raw {
        case "1", "true", "yes", "y", "on":
            return true
        default:
            return false
        }
    }()

    // Heavy tensor statistics (mean/std/etc.) can significantly slow realtime and may stress iOS devices.
    // Keep it opt-in even when QWEN3_ASR_DEBUG is enabled.
    static let tensorStatsEnabled: Bool = {
        guard enabled else { return false }
        let raw = ProcessInfo.processInfo.environment["QWEN3_ASR_DEBUG_TENSOR_STATS"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        switch raw {
        case "1", "true", "yes", "y", "on":
            return true
        default:
            return false
        }
    }()

    // Weight-by-weight casting logs can be extremely verbose (thousands of lines) and can cause
    // Xcode console/memory issues on iOS. Keep it separately opt-in.
    static let weightsEnabled: Bool = {
        guard enabled else { return false }
        let raw = ProcessInfo.processInfo.environment["QWEN3_ASR_DEBUG_WEIGHTS"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        switch raw {
        case "1", "true", "yes", "y", "on":
            return true
        default:
            return false
        }
    }()

    // Best-effort memory logging (MB). Useful to catch iOS jetsam conditions while debugging.
    static let memoryEnabled: Bool = {
        guard enabled else { return false }
        let raw = ProcessInfo.processInfo.environment["QWEN3_ASR_DEBUG_MEM"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        switch raw {
        case "1", "true", "yes", "y", "on":
            return true
        default:
            return false
        }
    }()

    static func log(_ message: @autoclosure () -> String) {
        guard enabled else { return }
        print(message())
    }

    static func logWeights(_ message: @autoclosure () -> String) {
        guard weightsEnabled else { return }
        print(message())
    }

    static func logMemory(_ label: String) {
        guard memoryEnabled else { return }
        if let mb = Qwen3ASRRuntimeMetrics.residentMemoryMB() {
            print("Qwen3ASRDebug: mem_mb=\(mb) \(label)")
        }
    }

    static func logTensorStats(_ message: @autoclosure () -> String) {
        guard tensorStatsEnabled else { return }
        print(message())
    }
}
