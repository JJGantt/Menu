import Foundation
import Security

/// Keychain-backed Anthropic API key store, shared by iOS and watchOS targets.
///
/// Reading order:
/// 1. Keychain (set by the user in Settings, or seeded from `Secrets` in DEBUG)
/// 2. Returns nil — caller surfaces "no key" error
///
/// On DEBUG builds, `seedFromSecretsIfNeeded()` copies `Secrets.anthropicAPIKey`
/// into Keychain on first launch. That way Jared's dev runs auto-populate the
/// key once, and the value persists into subsequent TestFlight installs of the
/// same bundle ID (Keychain is bundle-scoped, not build-config-scoped).
enum APIKeyStore {
    private static let service = "com.jaredgantt.CapitalGrille.anthropicAPIKey"
    private static let account = "default"

    static var current: String? {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8),
              !value.isEmpty else { return nil }
        return value
    }

    @discardableResult
    static func set(_ key: String) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return clear() }
        let data = Data(trimmed.utf8)
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attrs: [String: Any] = [
            kSecValueData as String:   data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
        if updateStatus == errSecSuccess { return true }
        if updateStatus == errSecItemNotFound {
            var addQuery = query
            for (k, v) in attrs { addQuery[k] = v }
            return SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess
        }
        return false
    }

    @discardableResult
    static func clear() -> Bool {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    /// In DEBUG, if Keychain is empty and `Secrets` carries a real-looking key,
    /// install it. This is the path that makes Jared's personal devices "just
    /// work" without any manual paste step.
    static func seedFromSecretsIfNeeded() {
        #if DEBUG
        if current != nil { return }
        let bundled = Secrets.anthropicAPIKey
        guard bundled.hasPrefix("sk-ant") else { return }
        _ = set(bundled)
        #endif
    }

    /// Looks like a real Anthropic key (cheap shape check, not validation).
    static func looksValid(_ key: String) -> Bool {
        let t = key.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.hasPrefix("sk-ant") && t.count > 20
    }
}
