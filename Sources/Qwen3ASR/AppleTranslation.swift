import Foundation

#if canImport(Translation)
@preconcurrency import Translation

/// Thin wrapper around Apple's `Translation` framework.
///
/// Notes:
/// - On current OS versions, a `TranslationSession` is typically provided by a SwiftUI host via `.translationTask`.
/// - This helper intentionally does not attempt to create/manages sessions.
@available(macOS 15.0, iOS 18.0, *)
public enum AppleTranslation {
    /// Translate a single string using a provided `TranslationSession`.
    public static func translate(
        _ text: String,
        clientIdentifier: String = "qwen3-asr-swift",
        using session: TranslationSession
    ) async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let req = TranslationSession.Request(
            sourceText: trimmed,
            clientIdentifier: clientIdentifier
        )
        let responses = try await session.translations(from: [req])
        return responses.first?.targetText.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}
#endif
