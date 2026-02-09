import Foundation

enum Qwen3ASRRuntimeConfig {
    // Evaluate once.
    static let useManualSoftmax: Bool = {
        let raw = ProcessInfo.processInfo.environment["QWEN3_ASR_MANUAL_SOFTMAX"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        switch raw {
        case "1", "true", "yes", "y", "on":
            return true
        default:
            return false
        }
    }()
}

