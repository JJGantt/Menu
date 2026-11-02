import Foundation
import Network

/// Tells the watch when its network comes back (`NWPathMonitor`), so recordings that could not be sent
/// go again the moment they can. Used only as a trigger, never as a gate: whether a send works is
/// decided by sending it, because a path the monitor calls down still sometimes carries a request, and
/// a request with no network fails within a second anyway.
@MainActor
final class Connectivity: ObservableObject {
    static let shared = Connectivity()

    /// Bumped each time the path goes from unusable to usable.
    @Published private(set) var cameBack = 0

    private let monitor = NWPathMonitor()
    private var online = true

    private init() {
        monitor.pathUpdateHandler = { path in
            let now = path.status == .satisfied
            Task { @MainActor in Connectivity.shared.update(now) }
        }
        monitor.start(queue: DispatchQueue(label: "connectivity"))
    }

    private func update(_ now: Bool) {
        if now && !online { cameBack += 1 }
        online = now
    }
}
