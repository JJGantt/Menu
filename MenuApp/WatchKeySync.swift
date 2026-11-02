#if os(iOS)
import WatchConnectivity
import Foundation

/// Mirrors the Anthropic key to the watch over WatchConnectivity, so the watch has a key
/// without one being typed on it. Activate once at iOS app launch.
final class WatchKeySync: NSObject, WCSessionDelegate {
    static let shared = WatchKeySync()

    private override init() { super.init() }

    static func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = shared
        WCSession.default.activate()
    }

    /// Puts the current key in the watch's applicationContext. Safe to call repeatedly;
    /// identical contexts are coalesced by WatchConnectivity.
    func pushAPIKey(_ key: String?) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        var ctx = session.applicationContext
        if let key, !key.isEmpty {
            ctx["anthropic_api_key"] = key
        } else {
            ctx.removeValue(forKey: "anthropic_api_key")
        }
        try? session.updateApplicationContext(ctx)
    }

    // Required WCSessionDelegate stubs (iOS-only)
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { WCSession.default.activate() }
    func session(_ session: WCSession,
                 activationDidCompleteWith state: WCSessionActivationState,
                 error: Error?) {
        if state == .activated {
            pushAPIKey(APIKeyStore.current)
        }
    }
}
#endif
