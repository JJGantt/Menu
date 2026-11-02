import Foundation

// MARK: - Top-level menu

struct MenuData {
    /// The menu's groups (lunch, dinner, ...) in display order, from `menu_groups`.
    var groups: [MenuGroup] = []
    var dishesByGroup: [String: [Dish]] = [:]
    var seasonal_programs: [SeasonalProgram] = []

    func dishes(in group: MenuGroup) -> [Dish] { dishesByGroup[group.id] ?? [] }
    /// Every regular-menu dish, group by group in display order.
    var allDishes: [Dish] { groups.flatMap { dishes(in: $0) } }
}

/// One `menu_groups` row: a group's id (what `menu_dishes.menu` holds), the title shown for it, and
/// the order of its sections. Sections not listed follow the listed ones.
struct MenuGroup: Codable, Identifiable {
    let id: String
    let title: String
    let sort: Int
    let sections: [String]
}

// MARK: - Seasonal programs (limited-time cards)
//
// Any number can run at once — one card each, shown in list order. A card is
// added or removed only when Jared says so; overlapping dates are normal. They
// live outside the regular menu groups — the model surfaces them only when the
// user asks about a program or one of its dishes or wines.

struct SeasonalProgram: Codable {
    let meta: SeasonalProgramMeta
    let wines: [SeasonalWine]
    let sections: [SeasonalSection]
}

struct SeasonalProgramMeta: Codable {
    let title: String
    let dates_active: String
    let notes: [String]?
}

struct SeasonalWine: Codable, Identifiable, Hashable {
    var id: String { name }
    let name: String
    let producer: String?
    let region: String?
    let varietal: String?
    let description: String?
    let tasting_notes: String?
    let suggested_pairing: String?
    let image_url: String?
}

struct SeasonalSection: Codable {
    let title: String
    let paired_wines: [String]
    let dishes: [Dish]
}

// MARK: - Dish

struct Dish: Codable, Identifiable, Hashable {
    var id: String { name }
    let name: String
    let section: String
    let page: Int?
    let price: Int?
    let calories: Int?
    let serves: Int?
    let menu_name: String?
    let description: String?
    let image: String?
    let serving_piece: String?
    let portion: [Ingredient]?
    let garnish: [Ingredient]?
    let to_bring: [String]?
    let questions_to_ask: [String]?
    let production_time: String?
    let station: String?
    let notes: [String]?
    let talking_points: [String]?
    let sizes: [String: String]?
    let variants: [String: String]?
    let tasting_notes: String?
    let ingredients: DishIngredients?

    func hash(into hasher: inout Hasher) { hasher.combine(name) }
    static func == (lhs: Dish, rhs: Dish) -> Bool { lhs.name == rhs.name }

    init(name: String, section: String, page: Int? = nil, price: Int? = nil,
         calories: Int? = nil, serves: Int? = nil, menu_name: String? = nil,
         description: String? = nil, image: String? = nil, serving_piece: String? = nil,
         portion: [Ingredient]? = nil, garnish: [Ingredient]? = nil, to_bring: [String]? = nil,
         questions_to_ask: [String]? = nil, production_time: String? = nil, station: String? = nil,
         notes: [String]? = nil, talking_points: [String]? = nil, sizes: [String: String]? = nil,
         variants: [String: String]? = nil, tasting_notes: String? = nil, ingredients: DishIngredients? = nil) {
        self.name = name
        self.section = section
        self.page = page
        self.price = price
        self.calories = calories
        self.serves = serves
        self.menu_name = menu_name
        self.description = description
        self.image = image
        self.serving_piece = serving_piece
        self.portion = portion
        self.garnish = garnish
        self.to_bring = to_bring
        self.questions_to_ask = questions_to_ask
        self.production_time = production_time
        self.station = station
        self.notes = notes
        self.talking_points = talking_points
        self.sizes = sizes
        self.variants = variants
        self.tasting_notes = tasting_notes
        self.ingredients = ingredients
    }

    enum CodingKeys: String, CodingKey {
        case name, section, page, price, calories, serves, menu_name, description,
             image, serving_piece, portion, garnish, to_bring, questions_to_ask,
             production_time, station, notes, talking_points, sizes, variants, tasting_notes,
             ingredients
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        section = try c.decode(String.self, forKey: .section)
        page = try c.decodeIfPresent(Int.self, forKey: .page)
        price = try c.decodeIfPresent(Int.self, forKey: .price)
        calories = try c.decodeIfPresent(Int.self, forKey: .calories)
        serves = try c.decodeIfPresent(Int.self, forKey: .serves)
        menu_name = try c.decodeIfPresent(String.self, forKey: .menu_name)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        image = try c.decodeIfPresent(String.self, forKey: .image)
        serving_piece = try c.decodeIfPresent(String.self, forKey: .serving_piece)
        portion = try c.decodeIfPresent([Ingredient].self, forKey: .portion)
        // garnish can be array of Ingredient OR a single string
        if let arr = try? c.decode([Ingredient].self, forKey: .garnish) {
            garnish = arr
        } else if let str = try? c.decode(String.self, forKey: .garnish) {
            garnish = [Ingredient(ingredient: str, amount: nil, prep: nil)]
        } else {
            garnish = nil
        }
        to_bring = try c.decodeIfPresent([String].self, forKey: .to_bring)
        questions_to_ask = try c.decodeIfPresent([String].self, forKey: .questions_to_ask)
        production_time = try c.decodeIfPresent(String.self, forKey: .production_time)
        station = try c.decodeIfPresent(String.self, forKey: .station)
        notes = try c.decodeIfPresent([String].self, forKey: .notes)
        talking_points = try c.decodeIfPresent([String].self, forKey: .talking_points)
        sizes = try c.decodeIfPresent([String: String].self, forKey: .sizes)
        variants = try c.decodeIfPresent([String: String].self, forKey: .variants)
        tasting_notes = try c.decodeIfPresent(String.self, forKey: .tasting_notes)
        ingredients = try c.decodeIfPresent(DishIngredients.self, forKey: .ingredients)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encode(section, forKey: .section)
        try c.encodeIfPresent(page, forKey: .page)
        try c.encodeIfPresent(price, forKey: .price)
        try c.encodeIfPresent(calories, forKey: .calories)
        try c.encodeIfPresent(serves, forKey: .serves)
        try c.encodeIfPresent(menu_name, forKey: .menu_name)
        try c.encodeIfPresent(description, forKey: .description)
        try c.encodeIfPresent(image, forKey: .image)
        try c.encodeIfPresent(serving_piece, forKey: .serving_piece)
        try c.encodeIfPresent(portion, forKey: .portion)
        try c.encodeIfPresent(garnish, forKey: .garnish)
        try c.encodeIfPresent(to_bring, forKey: .to_bring)
        try c.encodeIfPresent(questions_to_ask, forKey: .questions_to_ask)
        try c.encodeIfPresent(production_time, forKey: .production_time)
        try c.encodeIfPresent(station, forKey: .station)
        try c.encodeIfPresent(notes, forKey: .notes)
        try c.encodeIfPresent(talking_points, forKey: .talking_points)
        try c.encodeIfPresent(sizes, forKey: .sizes)
        try c.encodeIfPresent(variants, forKey: .variants)
        try c.encodeIfPresent(tasting_notes, forKey: .tasting_notes)
        try c.encodeIfPresent(ingredients, forKey: .ingredients)
    }
}

// MARK: - Ingredient (used for portion and garnish entries)

struct Ingredient: Codable, Hashable {
    let ingredient: String?
    let amount: String?
    let prep: String?
}

// MARK: - DishIngredients (used by Enhancement entries — rubs/crusts/sauces)

struct DishIngredients: Codable, Hashable {
    let rub: [String]?
    let finishing: [String]?
    let crust: [String]?
    let components: [String]?
    let note: String?
}

// MARK: - Menu loading

final class MenuStore: ObservableObject {
    @Published var menu: MenuData?

    private static let groupsPath = "menu_groups?select=id,title,sort,sections&order=sort.asc"
    private static let dishesPath = "menu_dishes?select=*&order=menu.asc,sort.asc"
    private static let seasonalPath = "app_content?key=eq.seasonal_programs&select=data"

    /// Shows the copy saved by the last fetch at once (offline-safe), then refreshes from Supabase in
    /// the background so database edits go live without a rebuild.
    func load() {
        menu = Self.assemble(groups: SupabaseClient.shared.cached(key: "menu_groups"),
                             dishes: SupabaseClient.shared.cached(key: "menu_dishes"),
                             seasonal: SupabaseClient.shared.cached(key: "seasonal_programs"))
        Task { await refreshFromRemote() }
    }

    /// Fetch the menu from Supabase (groups, per-dish rows, seasonal programs blob) and swap it in. A
    /// part that cannot be fetched comes from its saved copy, so a bad connection keeps the last menu.
    @MainActor
    func refreshFromRemote() async {
        async let groups: [MenuGroup]? = SupabaseClient.shared.getCached(
            path: Self.groupsPath, key: "menu_groups", usable: { !$0.isEmpty })
        async let dishes: [MenuDishRow]? = SupabaseClient.shared.getCached(
            path: Self.dishesPath, key: "menu_dishes", usable: { !$0.isEmpty })
        async let seasonal: [SeasonalProgramsRow]? = SupabaseClient.shared.getCached(
            path: Self.seasonalPath, key: "seasonal_programs")
        if let remote = Self.assemble(groups: await groups, dishes: await dishes, seasonal: await seasonal) {
            menu = remote
        }
    }

    private static func assemble(groups: [MenuGroup]?, dishes: [MenuDishRow]?, seasonal: [SeasonalProgramsRow]?) -> MenuData? {
        guard let groups, !groups.isEmpty, let dishes, !dishes.isEmpty else { return nil }
        var data = MenuData(groups: groups.sorted { $0.sort < $1.sort })
        for r in dishes { data.dishesByGroup[r.menu, default: []].append(r.dish) }
        data.seasonal_programs = seasonal?.first?.data ?? []
        return data
    }
}

/// One `menu_dishes` row: the dish fields (decoded straight into `Dish`) plus the
/// menu group it belongs to. Extra columns (id, sort, extra, updated_at) are ignored.
private struct MenuDishRow: Decodable {
    let menu: String
    let dish: Dish
    enum CodingKeys: String, CodingKey { case menu }
    init(from decoder: Decoder) throws {
        menu = try decoder.container(keyedBy: CodingKeys.self).decode(String.self, forKey: .menu)
        dish = try Dish(from: decoder)
    }
}

private struct SeasonalProgramsRow: Decodable { let data: [SeasonalProgram] }

// MARK: - Seasonal program search helpers

func seasonalWineMatches(_ w: SeasonalWine, query q: String) -> Bool {
    let fields = [w.name, w.producer, w.region, w.varietal, w.description, w.tasting_notes, w.suggested_pairing]
    return fields.contains { ($0?.lowercased().contains(q)) == true }
}

func seasonalDishMatches(_ d: Dish, query q: String) -> Bool {
    if d.name.lowercased().contains(q) { return true }
    if let desc = d.description?.lowercased(), desc.contains(q) { return true }
    if let mn = d.menu_name?.lowercased(), mn.contains(q) { return true }
    return false
}

// MARK: - Seasonal program → full-recipe resolution
//
// Seasonal program dishes are stubs (menu-line only). Some of them are the
// exact same dish that appears on the regular menu with full recipe details
// (portion, talking points, etc.). Resolve a stub to its full menu dish by an
// exact *normalized* name match so the detail view shows the real recipe. Only
// confident (normalized-equal) matches substitute — program-specific platings
// that have no twin on the regular menu keep their stub.

func normalizeDishName(_ s: String) -> String {
    var t = s.lowercased()
    for prefix in ["seasonal:", "upgrade:"] where t.hasPrefix(prefix) {
        t = String(t.dropFirst(prefix.count))
    }
    t = t.replacingOccurrences(of: "&", with: "and")
    // Drop all punctuation, collapse whitespace.
    let words = t.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
    return words.joined(separator: " ")
}

/// Builds a lookup of the regular menu (every group) keyed by normalized dish
/// name. First occurrence wins.
func fullMenuDishIndex(_ menu: MenuData) -> [String: Dish] {
    var index: [String: Dish] = [:]
    for dish in menu.allDishes {
        let key = normalizeDishName(dish.name)
        if index[key] == nil { index[key] = dish }
    }
    return index
}

extension Dish {
    /// Fills in only the missing *qualitative* recipe details from a regular-menu
    /// twin. Every field the seasonal entry already specifies is kept exactly
    /// (the program's spec trumps). Portion sizes, à-la-carte price, calories, and
    /// serving counts are intentionally NOT borrowed — those don't transfer to the
    /// program's own plating and pricing. A stub's "recipe details to follow"
    /// placeholder note is dropped once the real details are filled in.
    func fillingRecipeDetails(from source: Dish) -> Dish {
        let gpRealNotes = (notes ?? []).filter { !$0.lowercased().contains("recipe details to follow") }
        let mergedNotes = gpRealNotes.isEmpty ? source.notes : gpRealNotes
        return Dish(
            name: name,
            section: section,
            page: page ?? source.page,
            price: price,                 // the program prices its own items — never borrow à-la-carte price
            calories: calories,           // portion-dependent — never borrow
            serves: serves,               // never borrow
            menu_name: menu_name ?? source.menu_name,
            description: description ?? source.description,
            image: image ?? source.image,
            serving_piece: serving_piece ?? source.serving_piece,
            portion: portion,             // portion sizes don't transfer — keep the program's own only
            garnish: garnish ?? source.garnish,
            to_bring: to_bring ?? source.to_bring,
            questions_to_ask: questions_to_ask ?? source.questions_to_ask,
            production_time: production_time ?? source.production_time,
            station: station ?? source.station,
            notes: mergedNotes,
            talking_points: talking_points ?? source.talking_points,
            sizes: sizes,                 // portion sizes don't transfer — keep the program's own only
            variants: variants ?? source.variants,
            tasting_notes: tasting_notes ?? source.tasting_notes,
            ingredients: ingredients ?? source.ingredients
        )
    }
}

/// Resolves a seasonal stub against the regular menu by exact normalized
/// name. On a confident match, the stub is enriched with the twin's recipe
/// details (the program's spec always wins; portion/price specs are not borrowed).
/// No match → returned unchanged.
func resolveSeasonalDish(_ dish: Dish, using index: [String: Dish]) -> Dish {
    if let full = index[normalizeDishName(dish.name)] { return dish.fillingRecipeDetails(from: full) }
    if let mn = dish.menu_name, let full = index[normalizeDishName(mn)] { return dish.fillingRecipeDetails(from: full) }
    return dish
}

/// One-glance summary of every seasonal program for the assistant's prompt —
/// title, dates, notes, and the names of its dishes and wines — so the model
/// can recognise a question about a program and route it to the tool that
/// returns the full data.
func seasonalProgramSkeleton(_ programs: [SeasonalProgram]) -> String {
    guard !programs.isEmpty else { return "SEASONAL PROGRAMS: none running." }
    var out: [String] = []
    for p in programs {
        var header = "SEASONAL PROGRAM: \(p.meta.title) (\(p.meta.dates_active))"
        if let notes = p.meta.notes, !notes.isEmpty { header += " — " + notes.joined(separator: "; ") }
        out.append(header)
        for s in p.sections where !s.dishes.isEmpty {
            out.append("  \(s.title): " + s.dishes.map(\.name).joined(separator: "; "))
        }
        if !p.wines.isEmpty { out.append("  Wines: " + p.wines.map(\.name).joined(separator: "; ")) }
    }
    return out.joined(separator: "\n")
}

/// Compact food menu for the assistant's prompt — name, price, a short
/// description, and key ingredients per dish, grouped by menu and section. Lets
/// the model answer menu questions from context instead of a tool round-trip.
/// Built from the live menu, so database edits flow through automatically.
func foodMenuSkeleton(_ menu: MenuData?) -> String {
    guard let menu else { return "" }
    func ingredients(_ d: Dish) -> String {
        var parts: [String] = []
        if let ing = d.ingredients {
            if let r = ing.rub, !r.isEmpty { parts.append("rub: " + r.joined(separator: ", ")) }
            if let c = ing.crust, !c.isEmpty { parts.append("crust: " + c.joined(separator: ", ")) }
            if let f = ing.finishing, !f.isEmpty { parts.append("finishing: " + f.joined(separator: ", ")) }
            if let comp = ing.components, !comp.isEmpty { parts.append("components: " + comp.joined(separator: ", ")) }
        }
        if let portion = d.portion, !portion.isEmpty {
            let names = portion.compactMap { $0.ingredient }.prefix(8)
            if !names.isEmpty { parts.append("portion: " + names.joined(separator: ", ")) }
        }
        return parts.joined(separator: " | ")
    }
    func line(_ d: Dish) -> String {
        var bits = [d.name]
        if let p = d.price { bits.append("$\(p)") }
        if let desc = d.description, !desc.isEmpty { bits.append(String(desc.prefix(140))) }
        let ing = ingredients(d)
        if !ing.isEmpty { bits.append(ing) }
        return bits.joined(separator: " — ")
    }
    var out: [String] = []
    for group in menu.groups {
        let dishes = menu.dishes(in: group)
        guard !dishes.isEmpty else { continue }
        out.append("== \(group.title.uppercased()) ==")
        var section: String?
        for d in dishes {
            if d.section != section { section = d.section; out.append("-- \(d.section) --") }
            out.append("  " + line(d))
        }
    }
    return out.joined(separator: "\n")
}

func dishesBySection(_ dishes: [Dish], sectionOrder: [String]) -> [(String, [Dish])] {
    var grouped: [String: [Dish]] = [:]
    for d in dishes {
        grouped[d.section, default: []].append(d)
    }
    var result: [(String, [Dish])] = []
    for s in sectionOrder where grouped[s] != nil {
        result.append((s, grouped[s]!))
    }
    for s in grouped.keys where !sectionOrder.contains(s) {
        result.append((s, grouped[s]!))
    }
    return result
}
