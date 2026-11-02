import SwiftUI

// MARK: - Theme colors

extension Color {
    static let cgBackground = Color(red: 0.96, green: 0.94, blue: 0.90)
    static let cgCard = Color(red: 0.98, green: 0.97, blue: 0.94)
    static let cgText = Color(red: 0.16, green: 0.11, blue: 0.08)
    static let cgTextMuted = Color(red: 0.42, green: 0.34, blue: 0.29)
    static let cgAccent = Color(red: 0.45, green: 0.18, blue: 0.21)
    static let cgBorder = Color(red: 0.85, green: 0.80, blue: 0.72)
}

// MARK: - Close-detail action (jump straight out of a pushed detail stack)

/// Lets any view deep in a detail NavigationStack dismiss the whole fullScreenCover
/// (back to the main list) without popping level by level. Set once on the stack;
/// every pushed view inherits it via the environment.
private struct CloseDetailKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}
extension EnvironmentValues {
    var closeDetail: () -> Void {
        get { self[CloseDetailKey.self] }
        set { self[CloseDetailKey.self] = newValue }
    }
}
