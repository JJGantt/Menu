import SwiftUI

@main
struct MenuWatchApp: App {
    init() {
        APIKeyStore.seedFromSecretsIfNeeded()
        // Activates WCSession early and picks up the API key the phone has already pushed.
        _ = PhoneKeyReceiver.shared
        // Gating decides which models are permitted. Unapplied, it
        // stays on the bundled restricted profile (Haiku only) and silently
        // overrides whatever is picked in Settings.
        AppGate.apply()
        Task { await AppGate.refreshFromSupabase() }
    }

    var body: some Scene {
        WindowGroup {
            WatchContentView()
        }
    }
}
