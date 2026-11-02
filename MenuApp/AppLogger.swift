import Foundation

/// Fire-and-forget logger that buffers events during a user interaction and POSTs
/// the batch to Supabase after the response is returned. Never blocks the user path.
actor AppLogger {
    static let shared = AppLogger()

    struct Event {
        let timestamp: Date
        let interactionId: UUID
        let sessionId: String?
        let backend: String?
        let kind: String          // "interaction" | "api_request" | "api_error" | "tool_call" | "tool_error" | "fallback" | "voice_*" (the watch's recording and transcription, VoiceLog)
        let toolName: String?
        let input: Any?           // JSON-serializable
        let output: String?
        let error: String?
        let latencyMs: Int?
        let tokensIn: Int?
        let tokensOut: Int?
        let userInput: String?
        let finalAnswer: String?
    }

    private var buffers: [UUID: [Event]] = [:]
    /// Rows whose POST failed (no network, a timeout): they go up with the next flush instead of being
    /// lost, since a bad connection is exactly when the log is needed. Capped, oldest dropped first.
    private var unsent: [Event] = []
    private static let unsentCap = 500

    func record(_ event: Event) {
        buffers[event.interactionId, default: []].append(event)
    }

    /// Detach a fire-and-forget Task that POSTs the buffered events for this interaction, with any rows
    /// an earlier flush failed to send. Removes the buffer immediately so it can't be flushed twice.
    func flush(_ interactionId: UUID) {
        let events = unsent + (buffers.removeValue(forKey: interactionId) ?? [])
        unsent = []
        guard !events.isEmpty else { return }
        Task.detached(priority: .background) {
            if !(await Self.post(events: events)) { await self.keep(events) }
        }
    }

    private func keep(_ events: [Event]) {
        unsent = Array((events + unsent).suffix(Self.unsentCap))
    }

    /// False only when the network failed, so the rows are worth sending again. A refused insert is
    /// dropped: kept, it would sink every later batch with it.
    private static func post(events: [Event]) async -> Bool {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        // PostgREST rejects a bulk insert unless every object has the same keys
        // (PGRST102), and one interaction's events fill different fields — an
        // api_request has tokens, a tool_call has a tool name. So every row names
        // every column, with JSON null where this event has no value.
        func orNull(_ value: Any?) -> Any { value ?? NSNull() }
        let rows: [[String: Any]] = events.map { e in
            [
                "timestamp":      iso.string(from: e.timestamp),
                "interaction_id": e.interactionId.uuidString,
                "kind":           e.kind,
                "session_id":     orNull(e.sessionId),
                "backend":        orNull(e.backend),
                "tool_name":      orNull(e.toolName),
                "input":          orNull(e.input),
                "output":         orNull(e.output),
                "error":          orNull(e.error),
                "latency_ms":     orNull(e.latencyMs),
                "tokens_in":      orNull(e.tokensIn),
                "tokens_out":     orNull(e.tokensOut),
                "user_input":     orNull(e.userInput),
                "final_answer":   orNull(e.finalAnswer),
            ]
        }
        do {
            try await SupabaseClient.shared.insert(path: "app_logs", body: rows)
            return true
        } catch is URLError {
            return false
        } catch {
            // Logging must never crash anything.
            return true
        }
    }
}
