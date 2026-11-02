#if os(watchOS)
import WatchConnectivity
import Foundation

/// Takes the Anthropic key the phone pushes (`WatchKeySync`) and stores it on the watch.
@MainActor
final class PhoneKeyReceiver: NSObject, WCSessionDelegate {
    static let shared = PhoneKeyReceiver()

    private override init() {
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
            // Pick up a key the phone may have pushed in a previous session.
            ingestContext(WCSession.default.receivedApplicationContext)
        }
    }

    private func ingestContext(_ ctx: [String: Any]) {
        if let key = ctx["anthropic_api_key"] as? String, !key.isEmpty {
            _ = APIKeyStore.set(key)
            // The key picks the gating profile (owner vs default), so re-resolve it.
            AppGate.apply()
            Task { await AppGate.refreshFromSupabase() }
        }
    }

    nonisolated func session(_ session: WCSession,
                             activationDidCompleteWith state: WCSessionActivationState,
                             error: Error?) {}

    nonisolated func session(_ session: WCSession,
                             didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in self.ingestContext(applicationContext) }
    }
}
#endif
