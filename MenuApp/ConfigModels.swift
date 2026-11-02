import Foundation
import CryptoKit

/// App configuration that can be overridden from Supabase without an app rebuild.
/// Ships with bundled defaults so the app works first-launch / offline — the DB
/// is an override layer, never a hard dependency.
struct AppConfig {
    var allowedModels: [String]     // subset of ["haiku","sonnet","opus"]
    var defaultModel: String        // "haiku" | "sonnet" | "opus"

    /// Owner (Jared's device): everything unlocked.
    static let owner = AppConfig(
        allowedModels:   ["haiku", "sonnet", "opus"],
        defaultModel:    "sonnet"
    )

    /// Everyone else: Haiku only.
    static let restricted = AppConfig(
        allowedModels:   ["haiku"],
        defaultModel:    "haiku"
    )
}

/// Resolves device identity (owner vs everyone else) and publishes the active
/// gating that `AIModel` clamps to. Fails closed: until `apply()` runs,
/// only Haiku is permitted.
enum AppGate {
    /// SHA-256 of the owner's Anthropic API key. Hash only — safe to ship, reveals
    /// nothing. The owner device is whichever one holds that key.
    static let ownerKeyHash = "0c4eb3445e20e7d8b5164aca839f65fad2d05683f7556addbf4ca774d9a9c990"

    private(set) static var config: AppConfig = .restricted

    static var allowedModels: Set<String> { Set(config.allowedModels) }
    static var defaultModel: String { config.defaultModel }
    static var isOwnerDevice: Bool { isOwner(APIKeyStore.current) }

    static func isOwner(_ key: String?) -> Bool {
        guard let key, !key.isEmpty else { return false }
        let hex = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return hex == ownerKeyHash
    }

    /// Resolve the bundled-default config from the current key, then the saved Supabase rows over
    /// it. Synchronous and instant — call at launch and whenever the key changes.
    static func apply(key: String? = APIKeyStore.current) {
        config = isOwner(key) ? .owner : .restricted
        applyCached(key: key)
    }

    /// Pull the `app_config` rows from Supabase (kept on disk for offline launches), apply this
    /// device's profile (owner|default) and the restaurant's name. Graceful: with no answer and no
    /// saved copy, the bundled config stays.
    static func refreshFromSupabase(key: String? = APIKeyStore.current) async {
        guard let rows: [AppConfigRow] = await SupabaseClient.shared.getCached(
                path: AppConfigRow.path, key: AppConfigRow.cacheKey, usable: { !$0.isEmpty }) else { return }
        applyRows(rows, key: key)
    }

    /// The saved rows, applied without waiting on the network — what a launch starts from.
    static func applyCached(key: String? = APIKeyStore.current) {
        if let rows: [AppConfigRow] = SupabaseClient.shared.cached(key: AppConfigRow.cacheKey) { applyRows(rows, key: key) }
    }

    private static func applyRows(_ rows: [AppConfigRow], key: String?) {
        let profile = isOwner(key) ? "owner" : "default"
        if let r = rows.first(where: { $0.profile == profile }) {
            config = AppConfig(allowedModels: r.allowed_models, defaultModel: r.default_model)
        }
        if let name = rows.compactMap(\.restaurant_name).first(where: { !$0.isEmpty }) { Restaurant.name = name }
    }
}

/// One `app_config` row: a profile's model gating, and on the `default` row the restaurant's name.
struct AppConfigRow: Decodable {
    static let path = "app_config?select=profile,allowed_models,default_model,restaurant_name"
    static let cacheKey = "app_config"
    let profile: String
    let allowed_models: [String]
    let default_model: String
    let restaurant_name: String?
}

/// The restaurant the app is for. Its name lives in Supabase (`app_config.restaurant_name`) and is
/// put into every prompt that names it.
enum Restaurant {
    static var name = "the restaurant"
}

enum AIModel: String, CaseIterable, Identifiable {
    case haiku  = "claude-haiku-4-5"
    case sonnet = "claude-sonnet-5"
    case opus   = "claude-opus-5-5"

    var id: String { rawValue }
    var label: String {
        switch self {
        case .haiku:  return "Haiku"
        case .sonnet: return "Sonnet"
        case .opus:   return "Opus"
        }
    }

    /// The request's thinking settings. Answers here are short lookups where speed matters most, so
    /// thinking is off wherever the model allows it. Opus 5.5 cannot turn it off (the API rejects
    /// `disabled`), so it runs at the lowest effort instead. Haiku 4.5 thinks only when asked.
    var thinkingParams: [String: Any] {
        switch self {
        case .haiku:  return [:]
        case .sonnet: return ["thinking": ["type": "disabled"]]
        case .opus:   return ["output_config": ["effort": "low"]]
        }
    }

    /// Short stable key used by the gating config (independent of the model id,
    /// which can change on a version bump).
    var key: String {
        switch self {
        case .haiku:  return "haiku"
        case .sonnet: return "sonnet"
        case .opus:   return "opus"
        }
    }

    init?(key: String) {
        switch key {
        case "haiku":  self = .haiku
        case "sonnet": self = .sonnet
        case "opus":   self = .opus
        default:       return nil
        }
    }

    static var current: AIModel {
        get {
            let raw = UserDefaults.standard.string(forKey: "model") ?? AIModel.sonnet.rawValue
            let m = AIModel(rawValue: raw) ?? .sonnet
            // Enforce gating — a stored model that isn't permitted falls back to
            // the configured default.
            if AppGate.allowedModels.contains(m.key) { return m }
            return AIModel(key: AppGate.defaultModel) ?? .haiku
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "model") }
    }
}
