import Foundation

/// **Order recordings that have not reached the list yet.** A recording whose transcription failed (no
/// network, a link too slow to finish the upload) is kept here, on disk, instead of being deleted, and
/// `WatchOrdersView` sends it again when the network comes back, when the app comes to the front, and
/// after any order lands. It keeps its interaction id, so a resend is the same recording to the hub (a
/// second write under one id answers with the rows already written) and in `app_logs`.
///
/// The clips live in Application Support, not the temporary directory the recorder writes to, because
/// the system may empty that while the app is suspended.
@MainActor
final class OrderOutbox: ObservableObject {
    struct Item: Codable, Identifiable, Hashable {
        let id: UUID
        let file: String
        let duration: TimeInterval
        let recordedAt: Date
    }

    @Published private(set) var items: [Item] = []

    private let dir: URL
    private var index: URL { dir.appendingPathComponent("index.json") }

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        dir = base.appendingPathComponent("unsent-orders", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let saved = (try? Data(contentsOf: index)).flatMap { try? JSONDecoder().decode([Item].self, from: $0) } ?? []
        // A clip whose file has gone cannot be sent, so its row is dropped rather than shown forever.
        items = saved.filter { FileManager.default.fileExists(atPath: url(of: $0).path) }
    }

    func url(of item: Item) -> URL { dir.appendingPathComponent(item.file) }

    func clip(of item: Item) -> Recorder.Clip { .init(url: url(of: item), duration: item.duration) }

    /// Moves the clip in and lists it. Oldest first, so they go again in the order they were taken.
    func keep(_ clip: Recorder.Clip, id: UUID) {
        guard !items.contains(where: { $0.id == id }) else { return }
        let item = Item(id: id, file: id.uuidString + ".m4a", duration: clip.duration, recordedAt: Date())
        do {
            try FileManager.default.moveItem(at: clip.url, to: url(of: item))
        } catch {
            VoiceLog.record("orders_keep_failed", id: id, sessionId: "orders", error: String(describing: error), ends: true)
            return
        }
        items.append(item)
        save(id)
    }

    /// Deletes the clip: it is on the list, or it was thrown away.
    func remove(_ id: UUID) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        try? FileManager.default.removeItem(at: url(of: item))
        items.removeAll { $0.id == id }
        save(id)
    }

    /// `id` is the recording whose change is being saved, for the log row if the write fails.
    private func save(_ id: UUID) {
        do { try JSONEncoder().encode(items).write(to: index, options: .atomic) } catch {
            VoiceLog.record("orders_keep_failed", id: id, sessionId: "orders", error: String(describing: error), ends: true)
        }
    }
}
