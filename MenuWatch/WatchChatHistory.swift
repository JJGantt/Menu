import Foundation

/// Conversation history that survives watch app restarts.
///
/// Persisted to UserDefaults — small, reliable, no file I/O ceremony. The watch
/// app gets killed aggressively by watchOS, so keeping this purely in-memory
/// caused fresh sessions to lose all context. UserDefaults survives kills and
/// reboots.
final class WatchChatHistory: ObservableObject {
    /// One conversation, shared by the chat page and Settings (which clears it).
    static let shared = WatchChatHistory()

    private(set) var sessionId: String
    private(set) var pairs: [ChatTurn] = []

    /// Turns carry their tool calls (`ChatTurn`). The old question/answer-only history under
    /// "chatHistoryPairs" is dropped rather than carried over: tool-less "Added X" answers are what
    /// taught the model to claim an add without making it.
    private static let pairsKey   = "chatHistoryTurns"
    private static let sessionKey = "chatHistorySessionId"
    private static let maxPairs   = 40

    private init() {
        let d = UserDefaults.standard
        self.sessionId = d.string(forKey: Self.sessionKey) ?? {
            let new = UUID().uuidString
            d.set(new, forKey: Self.sessionKey)
            return new
        }()
        d.removeObject(forKey: "chatHistoryPairs")
        if let data = d.data(forKey: Self.pairsKey),
           let stored = try? JSONDecoder().decode([ChatTurn].self, from: data) {
            self.pairs = stored
        }
    }

    func append(_ turn: ChatTurn) {
        objectWillChange.send()
        pairs.append(turn)
        if pairs.count > Self.maxPairs { pairs.removeFirst() }
        persist()
    }

    func clear() {
        objectWillChange.send()
        pairs.removeAll()
        // Start a new session id too so the model treats it as a fresh chat.
        sessionId = UUID().uuidString
        let d = UserDefaults.standard
        d.set(sessionId, forKey: Self.sessionKey)
        d.removeObject(forKey: Self.pairsKey)
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(pairs) else { return }
        UserDefaults.standard.set(data, forKey: Self.pairsKey)
    }
}
