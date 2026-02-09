import XCTest
@testable import Qwen3ASR

final class Qwen3ASRCacheTests: XCTestCase {

    func testCachedModelSizeAndDeleteHonorsOverride() throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory
            .appendingPathComponent("qwen3asr-cache-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: base, withIntermediateDirectories: true)

        setenv("QWEN3_ASR_CACHE_DIR", base.path, 1)
        defer { unsetenv("QWEN3_ASR_CACHE_DIR") }

        let modelId = "mlx-community/Qwen3-ASR-0.6B-4bit"
        let cacheDir = try Qwen3ASRModel.cacheDirectoryURL(modelId: modelId)

        // Populate with a couple of fake downloads.
        try fm.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        try Data(repeating: 0xAB, count: 3).write(to: cacheDir.appendingPathComponent("config.json"), options: .atomic)
        try Data(repeating: 0xCD, count: 5).write(to: cacheDir.appendingPathComponent("model.safetensors"), options: .atomic)

        let bytes = try Qwen3ASRModel.cachedModelSizeBytes(modelId: modelId)
        XCTAssertEqual(bytes, 8)

        try Qwen3ASRModel.deleteCachedModel(modelId: modelId)
        XCTAssertFalse(fm.fileExists(atPath: cacheDir.path))
    }
}

