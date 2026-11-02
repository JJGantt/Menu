import Foundation
import SwiftUI

// MARK: - Models

struct BottleLocation: Codable, Equatable {
    var area: String?
    var row: Int?
    var column: Int?

    var isEmpty: Bool { area == nil && row == nil && column == nil }

    var displayString: String? {
        guard let area else { return nil }
        var parts = [area]
        if let row { parts.append("Row \(row)") }
        if let column { parts.append("Col \(column)") }
        return parts.joined(separator: " · ")
    }
}

struct Bottle: Codable, Identifiable, Hashable {
    let id: String
    var name: String?
    var kind: String?
    var category: String?
    var varietal: String?
    var producer: String?
    var producer_parent: String?
    var location: String?
    var pairing_style: String?
    var abv: String?
    var grapes: [String]?
    var grape_detail: String?
    var tasting_notes: String?
    var talking_points: String?
    var food_pairing: String?
    var image_url: String?
    var price: Double?
    var bottle_price: Double?
    var deleted: Bool?
    var readonly: Bool?
    var unverified: Bool?
    var primary_area: String?
    var primary_row: Int?
    var primary_column: Int?
    var backup_area: String?
    var backup_row: Int?
    var backup_column: Int?

    var displayName: String { name ?? id }
    var primary: BottleLocation { .init(area: primary_area, row: primary_row, column: primary_column) }
    var backup: BottleLocation { .init(area: backup_area, row: backup_row, column: backup_column) }
    var isDeleted: Bool { deleted == true }
    var isReadonly: Bool { readonly == true }
    var isUnverified: Bool { unverified == true }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: Bottle, rhs: Bottle) -> Bool { lhs.id == rhs.id }
}

struct BottleCategory: Identifiable {
    var id: String { name }
    let name: String
    let bottles: [Bottle]
}

/// A top-level spirit TYPE in the liquor "Type" view (e.g. "Whiskey", "Brandy", "Vodka").
/// `nested` is true when the type fans out into more than one style (Whiskey → Bourbon,
/// Rye, Scotch…; Brandy → Cognac, Brandy) and the UI should show a second collapsible
/// level. Single-style types (Vodka, Tequila, Gin…) have `nested == false` and the UI
/// opens straight to bottles. `styles` always holds the bottles, grouped by varietal.
struct BottleTypeGroup: Identifiable {
    var id: String { name }
    let name: String
    let nested: Bool
    let styles: [BottleCategory]
    var allBottles: [Bottle] { styles.flatMap { $0.bottles } }
}

/// Does a bottle match a search query? Scans every text field a guest might search by —
/// name, notes, talking points, producer/company, varietal, region, pairing style.
/// Shared by the wine and liquor lists and the search auto-switch counts.
func bottleMatches(_ b: Bottle, query q: String) -> Bool {
    if q.isEmpty { return true }
    let fields: [String?] = [b.name, b.tasting_notes, b.talking_points, b.producer,
                             b.producer_parent, b.varietal, b.category, b.location,
                             b.pairing_style, b.food_pairing, b.grape_detail]
    return fields.contains { ($0 ?? "").lowercased().contains(q) }
}

struct BottleArea: Codable, Identifiable, Hashable {
    var id: String { name }
    let name: String
}

/// A backend-defined view mode for a section (e.g. wine "By Type" / "By Producer").
/// Rows live in the `section_views` table — adding a new view is pure backend data,
/// no app change: the UI renders whatever views exist and groups by `group_by`.
struct BottleSectionView: Codable, Identifiable, Hashable {
    let id: String
    let section: String       // "wine" | "liquor"
    let label: String         // shown in the toggle
    let group_by: String      // bottle field to group on: "category","producer","producer_parent","varietal"
    let sort_order: Int
    let is_default: Bool
    let group_order: [String]? // explicit group ordering; nil = alphabetical
}

/// Maps a liquor `varietal` (the style, e.g. "Bourbon") to its parent spirit `type`
/// (e.g. "Whiskey"), with display ordering. Lives in the `spirit_types` table so the
/// type→style hierarchy is backend data, not hardcoded. A varietal with no row defaults
/// to a type equal to itself (a single-style type like Vodka or Tequila).
struct SpiritType: Codable, Hashable {
    let varietal: String
    let type: String
    let type_order: Int?
    let style_order: Int?
}

/// A learner-friendly description of a group value (a varietal, region, producer, or
/// company), shown in the expanded group header and the tap-through group screen.
struct GroupDescription: Codable {
    let dimension: String   // matches a view's group_by ("varietal","location","producer","producer_parent")
    let value: String
    let description: String
    /// "wine" | "liquor" when the value means different things per section (a location
    /// like France is a wine region AND a spirits region); nil = shared across sections
    /// (varietals/producers/companies don't overlap or mean the same either way).
    let section: String?
}

/// A dish↔wine-style pairing. Pairing is authored at the STYLE level (e.g. "Rich
/// Oaked Chardonnay"), not per bottle: every wine in the style inherits it. One bottle
/// may be flagged a `standout` when it has a specific, dish-specific resonance.
/// `dish_id` is the menu_dishes slug. Mirrored both directions in the UI.
struct StylePairing: Codable, Hashable, Identifiable {
    let dish_id: String
    let style: String
    let tier: String              // "Perfect" | "Great" | "Good"
    let justification: String
    var leaves_out: String?
    var standout_wine_id: String?
    var standout_reason: String?
    var sort_order: Int?
    var id: String { "\(dish_id)|\(style)" }
}

/// Minimal menu_dishes row — used only to map a pairing's `dish_id` slug back to a
/// normalized dish name so it lines up with the bundled food menu.
struct PairingDishRow: Codable { let id: String; let name: String }

/// A glossary entry: an obscure term (Madeira, mash bill, tahona…) with a plain-language
/// definition and any alias/plural forms to match in text.
struct GlossaryEntry: Codable {
    let term: String
    let definition: String
    var aliases: [String]?
    var category: String?
}

/// A resolved glossary match shown in the tap-up bottom sheet.
struct GlossaryHit: Identifiable, Hashable {
    let id: String        // lowercased canonical key
    let term: String      // display term
    let definition: String
}

/// One dish a wine pairs with (shown on the wine's detail), with the tier its style
/// earned and whether THIS wine is the standout for that dish.
struct WineDishPairing: Identifiable {
    var id: String { dish.id }
    let tier: String
    let dish: Dish
    let isStandout: Bool
    let standoutReason: String?
}

// MARK: - Store

@MainActor
final class BottleStore: ObservableObject {
    @Published var bottles: [String: Bottle] = [:]
    @Published var areas: [BottleArea] = []
    @Published var sectionViews: [BottleSectionView] = []
    @Published var spiritTypes: [SpiritType] = []   // varietal → parent type mapping (liquor)
    @Published var descriptions: [String: String] = [:]   // key "dimension|value" → description
    @Published var stylePairings: [StylePairing] = []
    @Published var glossary: [GlossaryEntry] = []
    /// lowercased surface form (term or alias) → resolved hit. Built from the glossary
    /// table plus the varietal descriptions we already have (reused so they never drift).
    private(set) var glossaryIndex: [String: GlossaryHit] = [:]
    /// every surface form, longest first, so "single malt" wins over "malt" when matching.
    private(set) var glossarySurfaces: [String] = []
    @Published var dishNameBySlug: [String: String] = [:] // menu_dishes slug → normalized dish name
    /// Normalized dish name → menu Dish, supplied by the view layer once the bundled
    /// food menu has loaded (the menu lives in MenuStore, not Supabase).
    var menuDishes: [String: Dish] = [:]
    @Published var loadError: String?

    private static let strengthRank = ["Perfect": 0, "Great": 1, "Good": 2]

    /// Best tier first (Perfect → Great → Good), then alphabetical by display name.
    private static func pairingBefore(_ aStrength: String, _ aName: String,
                                      _ bStrength: String, _ bName: String) -> Bool {
        let ra = strengthRank[aStrength] ?? 9
        let rb = strengthRank[bStrength] ?? 9
        if ra != rb { return ra < rb }
        return aName < bName
    }

    private static let wineCategoryOrder = ["Sparkling & Rosé", "White Wine", "Red Wine"]

    /// Wines (kind == "wine") grouped by category, in canonical order. Each group sorted by name.
    var wineCategories: [BottleCategory] {
        let wines = bottles.values.filter { ($0.kind ?? "wine") == "wine" && !$0.isDeleted }
        let grouped = Dictionary(grouping: wines, by: { $0.category ?? "Other" })
        let sortKey: (Bottle, Bottle) -> Bool = { a, b in
            let av = a.varietal ?? "~"  // nulls sort last
            let bv = b.varietal ?? "~"
            if av != bv { return av < bv }
            return a.displayName < b.displayName
        }
        let known = Self.wineCategoryOrder.compactMap { name -> BottleCategory? in
            guard let entries = grouped[name], !entries.isEmpty else { return nil }
            return BottleCategory(name: name, bottles: entries.sorted(by: sortKey))
        }
        let unknownNames = grouped.keys.filter { !Self.wineCategoryOrder.contains($0) }.sorted()
        let unknown = unknownNames.map { name in
            BottleCategory(name: name, bottles: grouped[name]!.sorted(by: sortKey))
        }
        return known + unknown
    }

    // MARK: - Backend-defined views (section = "wine" | "liquor")

    /// Available view modes for a section, ordered. Falls back to a built-in "Type"
    /// view if the backend table hasn't loaded (so the app always works first launch).
    func views(for section: String) -> [BottleSectionView] {
        let v = sectionViews.filter { $0.section == section }.sorted { $0.sort_order < $1.sort_order }
        if !v.isEmpty { return v }
        switch section {
        case "liquor":
            return [BottleSectionView(id: "liquor-by-type", section: "liquor", label: "Type",
                                      group_by: "varietal", sort_order: 0, is_default: true, group_order: nil)]
        default:
            return [BottleSectionView(id: "wine-by-type", section: "wine", label: "Type",
                                      group_by: "category", sort_order: 0, is_default: true,
                                      group_order: Self.wineCategoryOrder)]
        }
    }

    /// The bottle field a view groups on, resolved by name (kept in sync with the
    /// `group_by` values the backend may use). Unknown fields fall back to nil → "Other".
    private func groupValue(_ b: Bottle, field: String) -> String? {
        switch field {
        case "category":        return b.category
        case "producer":        return b.producer
        case "producer_parent": return b.producer_parent
        case "location":        return b.location
        case "varietal":        return b.varietal
        case "pairing_style":   return b.pairing_style
        default:                return nil
        }
    }

    /// A single bottle's value for a given view's grouping field (for surfacing all
    /// of a bottle's attributes on its detail screen, regardless of the active view).
    func viewValue(_ b: Bottle, for view: BottleSectionView) -> String? {
        groupValue(b, field: view.group_by)
    }

    /// The learner description for a group value (e.g. dimension "location", value
    /// "Napa Valley"), if one exists in the backend `group_descriptions` table.
    /// Prefers a section-specific row (a location means different things for wine vs
    /// liquor) and falls back to the shared row for dimensions that don't vary.
    func description(dimension: String, value: String, section: String) -> String? {
        descriptions["\(dimension)|\(value)|\(section)"] ?? descriptions["\(dimension)|\(value)"]
    }

    // MARK: - Glossary (clickable term definitions)

    /// Rebuilds the surface→definition index from the glossary table plus the existing
    /// varietal descriptions (so a tap on "Chardonnay" in a note shows the same blurb as
    /// its group screen). Glossary entries win on any collision.
    func rebuildGlossary() {
        var idx: [String: GlossaryHit] = [:]
        // Reuse in-app varietal descriptions as glossary terms.
        for (key, desc) in descriptions {
            let parts = key.split(separator: "|").map(String.init)
            guard parts.count >= 2, parts[0] == "varietal" else { continue }
            let value = parts[1]
            idx[value.lowercased()] = GlossaryHit(id: value.lowercased(), term: value, definition: desc)
        }
        // Glossary table (and aliases) — override varietals on collision.
        for e in glossary {
            let hit = GlossaryHit(id: e.term.lowercased(), term: e.term, definition: e.definition)
            idx[e.term.lowercased()] = hit
            for a in e.aliases ?? [] { idx[a.lowercased()] = hit }
        }
        glossaryIndex = idx
        glossarySurfaces = idx.keys.sorted { $0.count > $1.count }
    }

    func glossaryHit(_ surface: String) -> GlossaryHit? { glossaryIndex[surface.lowercased()] }

    /// Renders `text` with the FIRST occurrence of each glossary term bolded, accent-
    /// colored, and linked to `glossary:<key>` (intercepted to open the bottom sheet).
    /// Longest terms match first; matches are whole-word and never overlap.
    func glossaryAttributed(_ text: String) -> AttributedString {
        var matches: [(Range<String.Index>, String)] = []
        var used: [Range<String.Index>] = []
        for surface in glossarySurfaces {
            if let r = firstWordRange(of: surface, in: text, avoiding: used) {
                used.append(r); matches.append((r, surface))
            }
        }
        matches.sort { $0.0.lowerBound < $1.0.lowerBound }
        var out = AttributedString("")
        var cursor = text.startIndex
        for (r, key) in matches {
            if cursor < r.lowerBound { out += AttributedString(String(text[cursor..<r.lowerBound])) }
            var run = AttributedString(String(text[r]))
            let enc = key.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? key
            run.link = URL(string: "glossary:\(enc)")
            run.inlinePresentationIntent = .stronglyEmphasized
            out += run
            cursor = r.upperBound
        }
        if cursor < text.endIndex { out += AttributedString(String(text[cursor...])) }
        return out
    }

    /// First whole-word, case-insensitive occurrence of `surface` not overlapping a range
    /// already claimed by a longer term.
    private func firstWordRange(of surface: String, in text: String,
                                avoiding used: [Range<String.Index>]) -> Range<String.Index>? {
        var start = text.startIndex
        while let r = text.range(of: surface, options: .caseInsensitive, range: start..<text.endIndex) {
            let before = r.lowerBound == text.startIndex ? Character(" ") : text[text.index(before: r.lowerBound)]
            let after = r.upperBound == text.endIndex ? Character(" ") : text[r.upperBound]
            let wordOK = !before.isLetter && !before.isNumber && !after.isLetter && !after.isNumber
            if wordOK && !used.contains(where: { $0.overlaps(r) }) { return r }
            start = r.upperBound
        }
        return nil
    }

    // MARK: - Pairings (dish ↔ wine-style, mirrored)

    /// All wines in a pairing style, sorted with the standout (if any) first, then by name.
    func wines(inStyle style: String, standoutId: String? = nil) -> [Bottle] {
        bottles.values
            .filter { ($0.kind ?? "wine") == "wine" && !$0.isDeleted && $0.pairing_style == style }
            .sorted { a, b in
                if (a.id == standoutId) != (b.id == standoutId) { return a.id == standoutId }
                return a.displayName < b.displayName
            }
    }

    /// The style pairings for a dish (by its menu_dishes slug), best tier first.
    /// Resolves the slug from the dish's normalized name so it works off the bundled menu.
    func stylePairings(forDishName name: String) -> [StylePairing] {
        let target = normalizeDishName(name)
        let slugs = Set(dishNameBySlug.filter { $0.value == target }.map { $0.key })
        return stylePairings
            .filter { slugs.contains($0.dish_id) }
            .sorted { ($0.sort_order ?? 9, $0.style) < ($1.sort_order ?? 9, $1.style) }
    }

    /// The dishes a wine pairs with — every dish whose pairing includes this wine's
    /// style — grouped best tier first, flagging the dishes this exact bottle stars for.
    func dishPairings(forWine wine: Bottle) -> [WineDishPairing] {
        guard let style = wine.pairing_style else { return [] }
        var byDish: [String: WineDishPairing] = [:]
        for p in stylePairings where p.style == style {
            guard let norm = dishNameBySlug[p.dish_id], let dish = menuDishes[norm] else { continue }
            // collapse duplicate menu slugs (same dish in two sections) by normalized name
            if byDish[norm] != nil { continue }
            byDish[norm] = WineDishPairing(
                tier: p.tier, dish: dish,
                isStandout: p.standout_wine_id == wine.id,
                standoutReason: p.standout_wine_id == wine.id ? p.standout_reason : nil)
        }
        return byDish.values.sorted { (a: WineDishPairing, b: WineDishPairing) in
            Self.pairingBefore(a.tier, a.dish.name, b.tier, b.dish.name)
        }
    }

    /// Dimensions whose values span both wines and liquors (a corporate parent like
    /// Constellation, or a producer that makes both). Tapping one on an item should
    /// surface EVERY product sharing it — wine and liquor — not just the same section.
    private static let crossSectionDimensions: Set<String> = ["producer", "producer_parent"]

    /// Bottles matching `value` for a grouping `field`, backing the tap-through group
    /// screen. For company/producer the result spans all sections (so a company shows
    /// its wines and liquors together); for type/location it stays within `section`.
    func bottles(section: String, field: String, equals value: String) -> [Bottle] {
        let crossSection = Self.crossSectionDimensions.contains(field)
        return bottles.values
            .filter { b in
                !b.isDeleted
                && groupValue(b, field: field) == value
                && (crossSection || (b.kind ?? "wine") == section)
            }
            .sorted { a, b in
                let av = a.varietal ?? "~", bv = b.varietal ?? "~"
                if av != bv { return av < bv }
                return a.displayName < b.displayName
            }
    }

    /// Bottles in a section grouped per a backend-defined view: by `view.group_by`,
    /// ordered by `view.group_order` (known groups first in that order), then any
    /// remaining groups alphabetically. Each group sorted by varietal then name.
    func groups(for view: BottleSectionView) -> [BottleCategory] {
        let items = bottles.values.filter { ($0.kind ?? "wine") == view.section && !$0.isDeleted }
        let grouped = Dictionary(grouping: items, by: { groupValue($0, field: view.group_by) ?? "Other" })
        let sortKey: (Bottle, Bottle) -> Bool = { a, b in
            let av = a.varietal ?? "~"
            let bv = b.varietal ?? "~"
            if av != bv { return av < bv }
            return a.displayName < b.displayName
        }
        let order = view.group_order ?? []
        let known = order.compactMap { name -> BottleCategory? in
            guard let entries = grouped[name], !entries.isEmpty else { return nil }
            return BottleCategory(name: name, bottles: entries.sorted(by: sortKey))
        }
        let unknownNames = grouped.keys.filter { !order.contains($0) }.sorted()
        let unknown = unknownNames.map { name in
            BottleCategory(name: name, bottles: grouped[name]!.sorted(by: sortKey))
        }
        return known + unknown
    }

    var liquors: [Bottle] {
        bottles.values
            .filter { ($0.kind ?? "") == "liquor" && !$0.isDeleted }
            .sorted { $0.displayName < $1.displayName }
    }

    /// Liquors grouped by varietal (Tequila, Bourbon, Vodka, etc.), alphabetical by varietal then name.
    var liquorCategories: [BottleCategory] {
        let onlyLiquors = bottles.values.filter { ($0.kind ?? "") == "liquor" && !$0.isDeleted }
        let grouped = Dictionary(grouping: onlyLiquors, by: { $0.varietal ?? "Other" })
        return grouped.keys.sorted().map { name in
            BottleCategory(name: name, bottles: grouped[name]!.sorted { $0.displayName < $1.displayName })
        }
    }

    /// varietal → its spirit-type mapping row.
    private var spiritTypeByVarietal: [String: SpiritType] {
        Dictionary(spiritTypes.map { ($0.varietal, $0) }, uniquingKeysWith: { a, _ in a })
    }

    /// type name → its display order (lowest type_order among the type's varietals).
    private var orderByType: [String: Int] {
        var m: [String: Int] = [:]
        for s in spiritTypes {
            guard let o = s.type_order else { continue }
            m[s.type] = min(m[s.type] ?? o, o)
        }
        return m
    }

    /// Liquors as a two-level tree: spirit TYPE → STYLE (varietal) → bottles. The Whiskey
    /// type fans its eight styles out under one umbrella; single-style types (Vodka,
    /// Tequila…) collapse to a flat list. Driven by the backend `spirit_types` table; if
    /// that table hasn't loaded, every varietal becomes its own type → identical to the
    /// old flat-by-varietal view, so the app still works first launch.
    func liquorTypeGroups() -> [BottleTypeGroup] {
        let items = bottles.values.filter { ($0.kind ?? "") == "liquor" && !$0.isDeleted }
        let mapByVarietal = spiritTypeByVarietal
        let typeOrder = orderByType

        // Bucket bottles by parent type (fallback type = the varietal itself).
        var byType: [String: [Bottle]] = [:]
        for b in items {
            let varietal = b.varietal ?? "Other"
            let type = mapByVarietal[varietal]?.type ?? varietal
            byType[type, default: []].append(b)
        }

        let sortedTypeNames = byType.keys.sorted { a, b in
            let oa = typeOrder[a] ?? Int.max
            let ob = typeOrder[b] ?? Int.max
            return oa != ob ? oa < ob : a < b
        }

        return sortedTypeNames.map { typeName in
            let bs = byType[typeName]!
            var byStyle: [String: [Bottle]] = [:]
            for b in bs { byStyle[b.varietal ?? "Other", default: []].append(b) }
            let sortedStyleNames = byStyle.keys.sorted { a, b in
                let oa = mapByVarietal[a]?.style_order ?? Int.max
                let ob = mapByVarietal[b]?.style_order ?? Int.max
                return oa != ob ? oa < ob : a < b
            }
            let styles = sortedStyleNames.map { styleName in
                BottleCategory(name: styleName,
                               bottles: byStyle[styleName]!.sorted { $0.displayName < $1.displayName })
            }
            // Nested when the type splits into multiple styles, or its one style is named
            // differently from the type (so the style header still carries its own blurb).
            let nested = styles.count > 1 || (styles.first.map { $0.name != typeName } ?? false)
            return BottleTypeGroup(name: typeName, nested: nested, styles: styles)
        }
    }

    /// One catalog read: from Supabase, falling back to the copy kept on disk (`getCached`), or that
    /// copy alone when `cachedOnly`.
    private func read<T: Decodable>(_ path: String, key: String, cachedOnly: Bool,
                                    usable: (T) -> Bool = { _ in true }) async -> T? {
        if cachedOnly { return SupabaseClient.shared.cached(key: key) }
        return await SupabaseClient.shared.getCached(path: path, key: key, usable: usable)
    }

    /// Bottles and areas: the only catalog tables the assistant's tools write. Each read is kept on
    /// disk, so a bad connection shows the last catalog fetched instead of none.
    private func loadBottles(cachedOnly: Bool = false) async throws {
        async let bottlesTask: [Bottle]? = read("bottles?select=*&deleted=eq.false&unverified=eq.false",
                                                key: "bottles", cachedOnly: cachedOnly, usable: { !$0.isEmpty })
        async let areasTask: [BottleArea]? = read("bottle_areas?select=*&order=name.asc",
                                                  key: "bottle_areas", cachedOnly: cachedOnly)
        guard let rows = await bottlesTask, let areaList = await areasTask else { throw URLError(.notConnectedToInternet) }
        self.bottles = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
        self.areas = areaList
    }

    /// Re-read after a write. One round trip, where the full refresh is seven, most of them reference
    /// tables (views, types, descriptions, pairings, glossary, dishes) that no write here touches.
    func refreshBottles() async {
        do {
            try await loadBottles()
        } catch {
            self.loadError = "Supabase fetch failed: \(error.localizedDescription)"
        }
    }

    /// The whole catalog. A store opening empty shows the saved copy first, so a slow connection does
    /// not hold the list (or the assistant's catalog) blank while the fetch runs.
    func refreshFromSupabase() async {
        if bottles.isEmpty { await loadCatalog(cachedOnly: true) }
        await loadCatalog(cachedOnly: false)
    }

    private func loadCatalog(cachedOnly: Bool) async {
        do {
            try await loadBottles(cachedOnly: cachedOnly)
            // View definitions are a soft dependency — a failure here must not break
            // the catalog, so fetch separately and ignore errors (falls back to By Type).
            if let views: [BottleSectionView] = await read(
                "section_views?select=*&order=sort_order.asc", key: "section_views", cachedOnly: cachedOnly) {
                self.sectionViews = views
            }
            if let types: [SpiritType] = await read("spirit_types?select=*", key: "spirit_types", cachedOnly: cachedOnly) {
                self.spiritTypes = types
            }
            if let descs: [GroupDescription] = await read(
                "group_descriptions?select=*", key: "group_descriptions", cachedOnly: cachedOnly) {
                self.descriptions = Dictionary(descs.map { d in
                    let key = d.section.map { "\(d.dimension)|\(d.value)|\($0)" }
                        ?? "\(d.dimension)|\(d.value)"
                    return (key, d.description)
                }, uniquingKeysWith: { a, _ in a })
            }
            if let pairs: [StylePairing] = await read("style_pairings?select=*", key: "style_pairings", cachedOnly: cachedOnly) {
                self.stylePairings = pairs
            }
            if let terms: [GlossaryEntry] = await read("glossary?select=*", key: "glossary", cachedOnly: cachedOnly) {
                self.glossary = terms
            }
            rebuildGlossary()
            if let dishRows: [PairingDishRow] = await read(
                "menu_dishes?select=id,name", key: "menu_dish_names", cachedOnly: cachedOnly) {
                self.dishNameBySlug = Dictionary(dishRows.map { ($0.id, normalizeDishName($0.name)) },
                                                 uniquingKeysWith: { a, _ in a })
            }
        } catch {
            // Nothing saved yet is not a failure; only a real fetch reports one.
            if !cachedOnly { self.loadError = "Supabase fetch failed: \(error.localizedDescription)" }
        }
    }

    // MARK: - Mutations (Supabase)

    /// Apply a batch of location updates against EXISTING bottles only.
    /// Returns (updated ids, missing ids). Missing ids → caller should suggest add_product.
    func updateLocations(_ updates: [[String: Any]]) async throws -> (updated: [String], missing: [String]) {
        var updated: [String] = []
        var missing: [String] = []
        for u in updates {
            guard let bottleId = u["bottle_id"] as? String ?? u["wine_id"] as? String else { continue }

            var patch: [String: Any?] = [:]
            if let p = u["primary"] as? [String: Any] {
                if let v = p["area"]   as? String { patch["primary_area"]   = v }
                if let v = p["row"]    as? Int    { patch["primary_row"]    = v }
                if let v = p["column"] as? Int    { patch["primary_column"] = v }
            }
            if let b = u["backup"] as? [String: Any] {
                if let v = b["area"]   as? String { patch["backup_area"]   = v }
                if let v = b["row"]    as? Int    { patch["backup_row"]    = v }
                if let v = b["column"] as? Int    { patch["backup_column"] = v }
            }
            if patch.isEmpty { continue }

            let rows = try await SupabaseClient.shared.patchReturning(path: "bottles?id=eq.\(bottleId)", body: patch)
            if rows.isEmpty { missing.append(bottleId) } else { updated.append(bottleId) }
        }
        await refreshBottles()
        return (updated, missing)
    }

    func addArea(_ name: String) async throws {
        try await SupabaseClient.shared.upsert(path: "bottle_areas",
            body: [["name": name]], onConflict: "name")
        await refreshBottles()
    }

    func renameArea(_ name: String, to newName: String) async throws {
        try await SupabaseClient.shared.patch(path: "bottle_areas?name=eq.\(name)",
            body: ["name": newName])
        await refreshBottles()
    }

    func removeArea(_ name: String) async throws {
        try await SupabaseClient.shared.delete(path: "bottle_areas?name=eq.\(name)")
        await refreshBottles()
    }
}
