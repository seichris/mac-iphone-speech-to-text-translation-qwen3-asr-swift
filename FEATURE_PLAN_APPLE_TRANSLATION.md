# Feature Plan: Apple Translation (Real Translation For Realtime)

## Goal

Replace the current realtime `[TRANS]` behavior (a second ASR decode pass with `language {X}<asr_text>`) with an actual text-translation step backed by Apple's `Translation` framework, so speech in Chinese can reliably produce English translations.

## Current State (Problem)

- Realtime currently generates `[TRANS]` by re-running ASR on the same audio window and forcing the decoder prompt to `language {target}<asr_text>`.
- In practice the model still tends to *transcribe* the spoken language (Chinese) rather than *translate* it, so `[TRANS]` often equals `[FINAL]`.

## Constraints / Reality Check

- Apple's `Translation` framework is available on iOS/macOS, but **a usable translation session is not something we can reliably create inside a plain CLI process** on macOS 14/iOS 17.
- The supported way to get a `TranslationSession` on modern OS versions is via SwiftUI’s `.translationTask(...)` (UI-driven lifecycle).
- Therefore:
  - **Library** can support Apple Translation when a `TranslationSession` is provided by a SwiftUI host app.
  - **CLI** should keep the existing behavior (or disable translation) and document that Apple Translation is for app integrations.

## Design

### API Surface

1. Add a small helper that performs translation with a provided `TranslationSession`:
   - `AppleTranslation.translate(text:using:) async throws -> String`
2. Add an opt-in realtime API that uses Apple Translation for `[TRANS]` when a session is available:
   - `Qwen3ASRModel.realtimeTranslate(audioSource:options:translationSession:)` (wrapper that translates `.final` events)
3. Keep the existing realtime API untouched for backwards compatibility:
   - `Qwen3ASRModel.realtimeTranslate(audioSource:options:)`

### Behavior

- `[FINAL]` continues to come from ASR.
- `[TRANS]` becomes **true text translation** (final transcript -> translated text).
- Translation runs only for committed/final segments (not every partial update) to keep latency reasonable.

### Platform Gating

- All Apple Translation integration is guarded by:
  - `#if canImport(Translation)`
  - `@available(macOS 15.0, iOS 18.0, *)` (current SDK availability for `TranslationSession`)

## Implementation Steps

1. Add `Sources/Qwen3ASR/AppleTranslation.swift`:
   - Wrap the minimal `TranslationSession.Request` + `session.translations(from:)` call.
2. Add `Sources/Qwen3ASR/RealtimeTranslationApple.swift`:
   - Wrap the core realtime stream and emit `.translation` events for `.final` segments using `TranslationSession`.
3. Make `MicrophoneAudioSource` compile on iOS:
   - Add `AVAudioSession` setup and permission flow under `#if os(iOS)`.
4. Update docs:
   - README: explain that CLI translation is model-based, and Apple Translation is for SwiftUI host apps via `translationTask`.
   - Provide a short code snippet showing how to pass a `TranslationSession` into realtime.
5. Add tests:
   - Unit test the helper parsing/suffix logic stays intact.
   - Apple Translation calls are not unit-testable offline; keep them behind compile guards.

## Acceptance Criteria

- A SwiftUI host app can:
  - Run realtime ASR.
  - Translate final segments to English via Apple Translation.
  - See `[FINAL]` in Chinese and `[TRANS]` in English for the same utterance.
- Existing CLI workflow keeps working unchanged.

## Follow-ups (Optional)

- Add a `--translator` flag in CLI and print a clear message that Apple Translation requires a SwiftUI host.
- Add an `Examples/` SwiftUI demo app (Xcode project) that wires everything together.
