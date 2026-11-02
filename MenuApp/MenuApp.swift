import SwiftUI

@main
struct MenuApp: App {
    init() {
        APIKeyStore.seedFromSecretsIfNeeded()
        // Resolve gating from the bundled defaults immediately (synchronous), then
        // let Supabase override it in the background if a config row exists.
        AppGate.apply()
        Task { await AppGate.refreshFromSupabase() }
        WatchKeySync.activate()
        #if DEBUG
        // Diagnostic heartbeat — DEBUG only so TestFlight/App Store builds
        // don't ping Supabase on every cold start.
        Task.detached(priority: .background) {
            let url = URL(string: "https://felyggqjjhltwokdfhop.supabase.co/rest/v1/app_logs")!
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue(Secrets.supabaseKey, forHTTPHeaderField: "apikey")
            req.setValue("Bearer \(Secrets.supabaseKey)", forHTTPHeaderField: "Authorization")
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue("return=minimal", forHTTPHeaderField: "Prefer")
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let body: [String: Any] = [
                "timestamp":      iso.string(from: Date()),
                "interaction_id": UUID().uuidString,
                "kind":           "heartbeat",
                "output":         "build_2026-05-27_logger_test"
            ]
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
            _ = try? await URLSession.shared.data(for: req)
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.light)
        }
    }
}
