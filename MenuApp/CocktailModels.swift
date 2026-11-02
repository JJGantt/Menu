import Foundation

// MARK: - Cocktail models

struct CocktailIngredient: Codable, Hashable {
    let name: String
    let amount: String?
}

struct Cocktail: Codable, Identifiable, Hashable {
    var id: String { name }
    let name: String
    let glass: String?
    let garnish: String?
    let service: String?
    let ingredients: [CocktailIngredient]
    let prep: [String]
}

// MARK: - Loading

final class CocktailStore: ObservableObject {
    @Published var cocktails: [Cocktail] = []

    private static let path = "cocktails?select=*&order=sort.asc"
    static let cacheKey = "cocktails"

    /// Shows the copy saved by the last fetch at once (offline-safe), then refreshes from Supabase so
    /// database edits go live without a rebuild.
    func load() {
        cocktails = Self.cached()
        Task { await refreshFromRemote() }
    }

    @MainActor
    func refreshFromRemote() async {
        if let remote: [Cocktail] = await SupabaseClient.shared.getCached(
                path: Self.path, key: Self.cacheKey, usable: { !$0.isEmpty }) {
            cocktails = remote
        }
    }

    /// The saved cocktail list, without going through the `@Published` store or the network.
    static func cached() -> [Cocktail] {
        SupabaseClient.shared.cached(key: cacheKey) ?? []
    }
}

/// Compact one-block rendering of our cocktails for the assistant's system
/// prompt — name, glass/garnish/service, full build, and method per drink.
func cocktailSkeleton(_ cocktails: [Cocktail]) -> String {
    guard !cocktails.isEmpty else { return "" }
    var lines: [String] = []
    for (i, c) in cocktails.enumerated() {
        var head = "\(i + 1). \(c.name)"
        if let g = c.glass { head += " | Glass: \(g)" }
        if let garnish = c.garnish { head += " | Garnish: \(garnish)" }
        if let s = c.service { head += " | Service: \(s)" }
        lines.append(head)
        let build = c.ingredients.map { ing in
            ing.amount.map { "\(ing.name) \($0)" } ?? ing.name
        }.joined(separator: ", ")
        if !build.isEmpty { lines.append("   Build: \(build)") }
        if !c.prep.isEmpty { lines.append("   Method: \(c.prep.joined(separator: " "))") }
    }
    return lines.joined(separator: "\n")
}

func cocktailMatches(_ c: Cocktail, query q: String) -> Bool {
    if c.name.lowercased().contains(q) { return true }
    if let glass = c.glass?.lowercased(), glass.contains(q) { return true }
    if c.ingredients.contains(where: { $0.name.lowercased().contains(q) }) { return true }
    return false
}
