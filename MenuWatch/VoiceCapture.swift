import Foundation
import WatchKit

/// The microphone for a question. A press starts it and a press ends it; nothing ends it on its own
/// except the system taking the microphone away.
@MainActor
final class VoiceCapture: ObservableObject {
    static let shared = VoiceCapture()

    @Published private(set) var recording = false

    /// The complication asked for a recording (`menuapp://record`); the chat page starts it once
    /// the app is active and showing. A request that could not be met right away (the app was not in
    /// front) must not start a recording on whatever later raise of the wrist brings the app back, so
    /// it lapses after `requestWindow` — StatusHub's watch does the same.
    @Published var recordRequested = false
    private(set) var requestedAt = Date.distantPast
    static let requestWindow: TimeInterval = 20

    /// Which page a request is for: the chat (`menuapp://record`) or the order list
    /// (`menuapp://order`). Only that page starts it.
    enum Target { case chat, orders }
    private(set) var requestedFor = Target.chat

    func requestRecording(for target: Target = .chat) {
        requestedFor = target
        requestedAt = Date()
        recordRequested = true
    }

    var requestIsFresh: Bool { Date().timeIntervalSince(requestedAt) < Self.requestWindow }

    private let recorder = Recorder()
    /// Started, microphone not open yet. A stop in this window cancels instead of sending.
    private var arming = false
    /// The recorder is still opening, so no second start may begin even after a cancel.
    private var opening = false
    /// Runs when the system takes the microphone mid-recording (Siri, a call).
    private var onTaken: (() -> Void)?

    private init() {
        recorder.onInterruption = { [weak self] began in
            guard began, let self, self.recording else { return }
            self.onTaken?()
        }
    }

    func start(onTaken: @escaping () -> Void, onFailure: @escaping @MainActor (Error) -> Void) {
        guard !recording, !opening else { return }
        recording = true
        self.onTaken = onTaken
        arming = true
        opening = true
        Task {
            defer { opening = false }
            do {
                try await recorder.start()
            } catch {
                arming = false
                reset()
                onFailure(error)
                return
            }
            guard arming else { recorder.cancel(); return }   // stopped while the microphone opened
            arming = false
            // Told the moment the microphone is actually live: words before this are not recorded.
            WKInterfaceDevice.current().play(.directionUp)
            recorder.cue()
        }
    }

    /// Ends the recording and hands back the clip; nil when the microphone never opened.
    func stop() -> Recorder.Clip? {
        guard recording else { return nil }
        reset()
        if arming { arming = false; return nil }
        return recorder.stop()
    }

    /// Ends the recording and throws it away.
    func cancel() {
        guard recording else { return }
        reset()
        if arming { arming = false; return }
        recorder.cancel()
    }

    private func reset() {
        recording = false
        onTaken = nil
    }
}

/// Turns a clip into words through the hub's owner-only route (`/api/cg/transcribe` in status-hub), the
/// same Groq Whisper as every other voice input. The hub knows the owner by this device's Anthropic key.
enum Transcriber {
    enum Failure: LocalizedError {
        case noKey
        case http(Int)
        var errorDescription: String? {
            switch self {
            case .noKey: return "No API key"
            case .http(let code): return "Transcription failed (\(code))"
            }
        }
    }

    private static let url = URL(string: "https://jared-status-hub.fly.dev/api/cg/transcribe")!

    /// A short clip normally comes back in 1-9s, so a try that has not finished in its limit is stuck,
    /// not slow: it is dropped and the clip sent again. The limit grows with the clip, because the upload
    /// does: a clip is about 9 KB a second, the watch's link has measured about 45 KB/s, so a 72s order
    /// (~625 KB) needs ~14s just to upload on a good link and never fit a flat 15s. A clip that still
    /// fails is not lost: the order page keeps it to send again (`OrderOutbox`), the chat to retry.
    private static func attemptLimit(_ clip: Recorder.Clip) -> TimeInterval { 15 + clip.duration / 2 }
    private static let attempts = 3

    /// `interactionId` rides as `X-Interaction-Id`, so the hub's timing row (`voice_hub`) lands under
    /// the same question as the watch's own steps. `onRetry` is told each time a stuck try is dropped.
    static func transcribe(_ clip: Recorder.Clip, interactionId: UUID,
                           onRetry: (Int, Error) -> Void = { _, _ in }) async throws -> String {
        var attempt = 1
        while true {
            do {
                return try await once(clip, interactionId: interactionId, limit: attemptLimit(clip))
            } catch {
                guard attempt < attempts, retryable(error), !Task.isCancelled else { throw error }
                onRetry(attempt, error)
                attempt += 1
            }
        }
    }

    /// A dropped or failed connection, or the hub/Groq failing, is worth another try; a refused key is not.
    private static func retryable(_ error: Error) -> Bool {
        if error is URLError { return true }
        if case Failure.http(let code) = error { return code >= 500 || code == 0 }
        return false
    }

    /// `timeoutIntervalForResource` is a cap on the WHOLE request; a URLRequest's own timeout only fires
    /// after that long with no bytes moving, so a trickling upload never trips it. The cap is a session
    /// setting, so each try gets a session sized to its clip.
    private static func once(_ clip: Recorder.Clip, interactionId: UUID, limit: TimeInterval) async throws -> String {
        guard let key = APIKeyStore.current else { throw Failure.noKey }
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForResource = limit
        c.timeoutIntervalForRequest = limit
        let session = URLSession(configuration: c)
        defer { session.finishTasksAndInvalidate() }
        var r = URLRequest(url: url)
        r.httpMethod = "POST"
        r.setValue(key, forHTTPHeaderField: "X-Owner-Key")
        r.setValue("audio/mp4", forHTTPHeaderField: "Content-Type")
        r.setValue(interactionId.uuidString, forHTTPHeaderField: "X-Interaction-Id")
        let (data, resp) = try await session.upload(for: r, fromFile: clip.url)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else { throw Failure.http(code) }
        struct Body: Decodable { let transcript: String }
        return try JSONDecoder().decode(Body.self, from: data).transcript
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// The voice path's steps, written to `app_logs` under the same `interaction_id` as the question they
/// became, so a failed question shows every step from the press to the answer in one place. Kinds:
/// `voice_mic_failed`, `voice_cancelled`, `voice_recorded` (latency = how long it recorded, output = the clip size),
/// `voice_transcribed` (latency = the hub round trip, output = the words), `voice_transcribe_retry` (a try
/// that hung or failed was dropped and the clip sent again; output = which try), `voice_transcribe_failed`,
/// `voice_empty` (the hub heard no words), `voice_phase` (the app went to the background or came back
/// while the question was being worked on), `voice_stay_awake_expired` (the minute StayAwake holds ran
/// out before the answer). The hub writes `voice_hub` under the same id: when the upload arrived, how
/// long the body took, and how long Groq took. A step that ends the path flushes; otherwise `ChatEngine`
/// flushes the whole interaction when it answers.
enum VoiceLog {
    static func record(_ kind: String, id: UUID, sessionId: String, output: String? = nil,
                       error: String? = nil, latencyMs: Int? = nil, ends: Bool = false) {
        Task {
            await AppLogger.shared.record(.init(
                timestamp: Date(), interactionId: id, sessionId: sessionId, backend: "watch:voice",
                kind: kind, toolName: nil, input: nil, output: output, error: error,
                latencyMs: latencyMs, tokensIn: nil, tokensOut: nil, userInput: nil, finalAnswer: nil))
            if ends { await AppLogger.shared.flush(id) }
        }
    }
}
