import Foundation

/// Shared chat engine — builds the system prompt + tool definitions from the
/// app's stores and runs a single turn through the Anthropic API. Used by both the iOS app and the watch app so they
/// answer identically.
@MainActor
final class ChatEngine {
    private let menuStore: MenuStore
    private let bottleStore: BottleStore
    private let restockStore: RestockStore
    /// Live cocktail catalog (Supabase-backed). Optional so the watch — which
    /// has no CocktailStore — falls back to the copy saved by the last fetch. iOS
    /// passes the live store so the assistant sees cocktail edits without a rebuild.
    private let cocktailStore: CocktailStore?

    /// Surface name (e.g., "iOS", "Watch") prepended to logs.
    private let surface: String

    /// Extra context appended to the system prompt — used by the watch to
    /// remind the model the answer will be read on a small screen.
    private let surfaceHint: String?

    init(menuStore: MenuStore,
         bottleStore: BottleStore,
         restockStore: RestockStore,
         cocktailStore: CocktailStore? = nil,
         surface: String = "ios",
         surfaceHint: String? = nil) {
        self.menuStore = menuStore
        self.bottleStore = bottleStore
        self.restockStore = restockStore
        self.cocktailStore = cocktailStore
        self.surface = surface
        self.surfaceHint = surfaceHint
    }

    func ask(question: String,
             history: [ChatTurn],
             sessionId: String,
             interactionId: UUID = UUID(),
             onActivity: (@MainActor (String?) -> Void)? = nil) async throws -> ChatTurn {
        let startedAt = Date()

        // The rule text comes from Supabase (app_content/system_prompt), or the copy saved by the
        // last fetch when the network fails.
        // The restock list is edited from other devices and cleared at 6am, so it is re-read for every
        // question rather than trusted from whenever this device last looked.
        async let blocks = Self.fetchPromptBlocks()
        await restockStore.refresh()
        let remotePrompt = await blocks
        let (systemStable, systemDynamic, tools) = buildPromptAndTools(remotePrompt: remotePrompt)

        func logInteraction(answer: String?, error: String?) async {
            await AppLogger.shared.record(.init(
                timestamp: startedAt, interactionId: interactionId, sessionId: sessionId,
                backend: "\(surface):api", kind: "interaction", toolName: nil, input: nil,
                output: nil, error: error,
                latencyMs: Int(Date().timeIntervalSince(startedAt) * 1000),
                tokensIn: nil, tokensOut: nil,
                userInput: question, finalAnswer: answer))
            await AppLogger.shared.flush(interactionId)
        }

        do {
            let turn = try await AnthropicClient.chatWithTools(
                question: question,
                history: history,
                systemStable: systemStable,
                systemDynamic: systemDynamic,
                tools: tools,
                interactionId: interactionId,
                sessionId: sessionId,
                onActivity: onActivity
            )
            await logInteraction(answer: turn.answer, error: nil)
            return turn
        } catch {
            await logInteraction(answer: nil, error: error.localizedDescription)
            throw error
        }
    }

    // MARK: - Prompt + tools

    /// Fetch the prompt's rule blocks from Supabase (app_content/system_prompt), kept on disk so a
    /// question asked on a bad connection still has them. Nil only when there is neither.
    static func fetchPromptBlocks() async -> [String: String]? {
        struct Row: Decodable { let data: [String: String] }
        let rows: [Row]? = await SupabaseClient.shared.getCached(
            path: "app_content?key=eq.system_prompt&select=data", key: "system_prompt", usable: { !$0.isEmpty })
        return rows?.first?.data
    }

    /// A prompt template with its `{{placeholders}}` filled in; `{{restaurant}}` is always available.
    static func fill(_ template: String, _ subs: [String: String] = [:]) -> String {
        var r = template.replacingOccurrences(of: "{{restaurant}}", with: Restaurant.name)
        for (k, v) in subs { r = r.replacingOccurrences(of: k, with: v) }
        return r
    }

    private func buildPromptAndTools(remotePrompt: [String: String]?) -> (stable: String, dynamic: String, tools: [AnthropicTool]) {
        // Catalog skeleton
        func locStr(_ l: BottleLocation) -> String? {
            guard let area = l.area else { return nil }
            var parts = [area]
            if let r = l.row    { parts.append("R\(r)") }
            if let c = l.column { parts.append("C\(c)") }
            return parts.joined(separator: " ")
        }
        func formatBottle(_ b: Bottle) -> String {
            var s = "\(b.displayName) [id:\(b.id)]"
            // Compact attribute tags so company/region/style/ABV questions are
            // answerable straight from the (cached) skeleton without a tool call.
            var tags: [String] = []
            if let pp = b.producer_parent { tags.append(pp) }
            if let loc = b.location { tags.append(loc) }
            if let st = b.pairing_style { tags.append(st) }
            if let abv = b.abv { tags.append(abv) }
            if !tags.isEmpty { s += " (" + tags.joined(separator: ", ") + ")" }
            let primary = locStr(b.primary)
            let backup  = locStr(b.backup)
            if let p = primary, let bk = backup { s += " @ \(p) | bk \(bk)" }
            else if let p = primary             { s += " @ \(p)" }
            else if let bk = backup             { s += " | bk \(bk)" }
            return s
        }
        var skeletonLines: [String] = ["WINES:"]
        for cat in bottleStore.wineCategories {
            let byVar = Dictionary(grouping: cat.bottles, by: { $0.varietal ?? "?" })
            for varietal in byVar.keys.sorted() {
                skeletonLines.append("[\(cat.name) · \(varietal)]")
                for b in byVar[varietal]!.sorted(by: { $0.displayName < $1.displayName }) {
                    skeletonLines.append("  \(formatBottle(b))")
                }
            }
        }
        skeletonLines.append("\nLIQUORS:")
        let byVarLiq = Dictionary(grouping: bottleStore.liquors, by: { $0.varietal ?? "?" })
        for varietal in byVarLiq.keys.sorted() {
            let bottles = byVarLiq[varietal]!.sorted(by: { $0.displayName < $1.displayName })
            skeletonLines.append("[\(varietal)] (\(bottles.count))")
            for b in bottles { skeletonLines.append("  \(formatBottle(b))") }
        }
        let bottleSkeleton = skeletonLines.joined(separator: "\n")

        let areas = bottleStore.areas.map(\.name)
        let areasJSON = (try? String(data: JSONSerialization.data(withJSONObject: areas), encoding: .utf8)) ?? "[]"

        let toolName = "update_bottle_locations"
        let areaTool = "edit_areas"
        let restockTool = "update_restock"
        let addProductTool = "add_product"
        let deleteProductTool = "delete_product"
        let detailsTool = "get_bottle_details"
        let byVarietalTool = "get_bottles_by_varietal"
        let searchTool = "search_bottles"
        let pairingsTool = "get_pairings"
        let foodTool = "get_food_menu"
        let seasonalTool = "get_seasonal_program"

        let restockCtx = restockStore.items.map { item -> [String: Any] in
            ["product_id": item.product_id, "quantity": item.quantity]
        }
        let restockJSON = (try? String(data: JSONSerialization.data(withJSONObject: restockCtx), encoding: .utf8)) ?? "[]"

        // Prefer the live, Supabase-backed cocktail list (same treatment as bottles);
        // fall back to the saved copy only if the live store hasn't loaded.
        let liveCocktails = cocktailStore?.cocktails ?? []
        let cocktailsList = liveCocktails.isEmpty ? CocktailStore.cached() : liveCocktails
        let cocktailSkel = cocktailsList.isEmpty ? "" : cocktailSkeleton(cocktailsList)
        let foodSkeleton = foodMenuSkeleton(menuStore.menu)
        let seasonalSkeleton = seasonalProgramSkeleton(menuStore.menu?.seasonal_programs ?? [])

        // The rule blocks live in Supabase (app_content/system_prompt), with {{tool}}/{{data}}
        // placeholders that resolve to the live backend + data.
        let promptSub: [String: String] = [
            "{{food_tool}}": foodTool, "{{details_tool}}": detailsTool, "{{by_varietal_tool}}": byVarietalTool,
            "{{search_tool}}": searchTool, "{{pairings_tool}}": pairingsTool,
            "{{seasonal_tool}}": seasonalTool, "{{location_tool}}": toolName, "{{area_tool}}": areaTool,
            "{{restock_tool}}": restockTool, "{{add_product_tool}}": addProductTool, "{{delete_product_tool}}": deleteProductTool,
            "{{bottle_skeleton}}": bottleSkeleton, "{{areas}}": areasJSON, "{{cocktail_skeleton}}": cocktailSkel, "{{restock}}": restockJSON,
            "{{food_skeleton}}": foodSkeleton, "{{seasonal_skeleton}}": seasonalSkeleton,
        ]
        func promptBlock(_ key: String) -> String {
            guard let remote = remotePrompt?[key], !remote.isEmpty else { return "" }
            return Self.fill(remote, promptSub)
        }

        var systemStable = promptBlock("base_rules")
        let cocktailRouting = promptBlock("cocktail_routing")
        if !cocktailRouting.isEmpty { systemStable += "\n\n" + cocktailRouting }
        let foodMenu = promptBlock("food_menu")
        if !foodMenu.isEmpty { systemStable += "\n\n" + foodMenu }

        if let hint = surfaceHint {
            systemStable += "\n\nSURFACE NOTE: \(hint)"
        }

        // The catalog skeleton + all the static rules are effectively static (the
        // skeleton changes only on a location edit), so fold them into the cached
        // prefix instead of re-billing them on every call. Only the live restock
        // list — which changes frequently — stays in the uncached block.
        systemStable += "\n\n" + promptBlock("catalog_rules")

        let systemDynamic = promptBlock("restock")

        // Tools — capture stores via closure
        let menuStore = self.menuStore
        let bottleStore = self.bottleStore
        let restockStore = self.restockStore

        let menuGroups = menuStore.menu?.groups ?? []
        let sectionList = menuGroups.map { g in
            "\(g.id)=[" + g.sections.map { "'\($0)'" }.joined(separator: ",") + "]"
        }.joined(separator: ", ")
        let getFoodMenuTool = AnthropicTool(
            name: "get_food_menu",
            description: "Get \(Restaurant.name) food menu. ALWAYS call this for food/dish questions. Use the 'section' parameter to narrow down — calling without a section returns just the list of section names + dish names (compact), which lets you pick the right section to drill into. Sections: \(sectionList). NEVER call this for alcohol questions — use get_bottle_details or get_bottles_by_varietal instead.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "section": ["type": "string", "description": "Optional. Name of a section to drill into (returns full dish details for that section only). Omit to get a high-level list of sections + dish names."],
                    "meal": ["type": "string", "enum": menuGroups.map(\.id), "description": "Optional. Restrict to a meal time."]
                ],
                "required": []
            ],
            handler: { input in
                guard let menu = await menuStore.menu else { return "(menu unavailable)" }
                let section = input["section"] as? String
                let meal = input["meal"] as? String

                let mealList: [(String, [Dish])] = menu.groups
                    .filter { meal == nil || $0.id == meal }
                    .map { ($0.id, menu.dishes(in: $0)) }

                if section == nil {
                    var out: [String] = []
                    for (m, ds) in mealList {
                        out.append("=== \(m.uppercased()) (\(ds.count) dishes) ===")
                        let groups = Dictionary(grouping: ds, by: { $0.section })
                        for s in groups.keys.sorted() {
                            let names = groups[s]!.map { $0.name }
                            out.append("[\(s)] (\(names.count)): \(names.joined(separator: ", "))")
                        }
                        out.append("")
                    }
                    return out.joined(separator: "\n")
                }

                let targetSection = section!.lowercased()
                var matched: [Dish] = []
                for (_, ds) in mealList {
                    matched.append(contentsOf: ds.filter { $0.section.lowercased() == targetSection })
                }
                if matched.isEmpty { return "No dishes found in section '\(section!)'. Try calling without a section to see available section names." }
                let enc = JSONEncoder()
                enc.outputFormatting = [.prettyPrinted]
                if let data = try? enc.encode(matched), let s = String(data: data, encoding: .utf8) { return s }
                return "(encode error)"
            }
        )

        let getSeasonalProgramTool = AnthropicTool(
            name: "get_seasonal_program",
            description: "Get the current seasonal programs — the limited-time cards that run alongside the regular menu (their titles, dates, and item names are in the system prompt). Returns every program: each dish with its description and notes, each wine with its description, tasting notes, and suggested pairing. Call this when the user names a program, asks about one of its dishes or wines, or asks what is new, seasonal, or featured. They are NOT part of the regular menu — never call it for ordinary food, wine, or dish questions.",
            inputSchema: [
                "type": "object",
                "properties": [:],
                "required": []
            ],
            handler: { input in
                _ = input
                let programs = await menuStore.menu?.seasonal_programs ?? []
                guard !programs.isEmpty else { return "(no seasonal programs running)" }
                let enc = JSONEncoder()
                enc.outputFormatting = [.prettyPrinted]
                if let data = try? enc.encode(programs), let s = String(data: data, encoding: .utf8) { return s }
                return "(encode error)"
            }
        )

        let getBottleDetailsTool = AnthropicTool(
            name: "get_bottle_details",
            description: "Fetch full details (tasting notes, image URL, locations, category, varietal) for one bottle by id. ALWAYS call this when the user asks about a specific bottle's flavor, history, production, additives, age, or any substantive characteristic. Use the bottle id from the catalog skeleton.",
            inputSchema: [
                "type": "object",
                "properties": ["bottle_id": ["type": "string"]],
                "required": ["bottle_id"]
            ],
            handler: { input in
                let bid = (input["bottle_id"] as? String) ?? ""
                let rows: [Bottle] = (try? await SupabaseClient.shared.get(path: "bottles?id=eq.\(bid)&unverified=eq.false&select=*")) ?? []
                guard let b = rows.first else { return "Bottle '\(bid)' not found." }
                var out = "\(b.displayName) [\(b.varietal ?? "?")]"
                if let c = b.category { out += " · \(c)" }
                var attrs: [String] = []
                if let p = b.producer { attrs.append("Producer: \(p)") }
                if let pp = b.producer_parent { attrs.append("Company: \(pp)") }
                if let loc = b.location { attrs.append("Region: \(loc)") }
                if let abv = b.abv { attrs.append("ABV: \(abv)") }
                if let st = b.pairing_style { attrs.append("Pairing style: \(st)") }
                if !attrs.isEmpty { out += "\n" + attrs.joined(separator: " · ") }
                if let s = b.primary.displayString { out += "\nPrimary: \(s)" }
                if let s = b.backup.displayString  { out += "\nBackup: \(s)" }
                if let g = b.grape_detail   { out += "\n\nGrapes/grain bill: \(g)" }
                if let t = b.tasting_notes  { out += "\n\nTasting notes: \(t)" }
                if let tp = b.talking_points { out += "\n\nTalking points: \(tp)" }
                if let fp = b.food_pairing  { out += "\n\nFood pairing: \(fp)" }
                if let u = b.image_url      { out += "\n\nImage: \(u)" }
                // Curated pairings via the bottle's style
                if let style = b.pairing_style, (b.kind ?? "wine") == "wine" {
                    let enc = style.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? style
                    struct SP: Decodable { let dish_id: String; let tier: String; let standout_wine_id: String?; let standout_reason: String? }
                    struct MD: Decodable { let id: String; let name: String }
                    let sp: [SP] = (try? await SupabaseClient.shared.get(path: "style_pairings?style=eq.\(enc)&select=dish_id,tier,standout_wine_id,standout_reason&order=sort_order.asc")) ?? []
                    if !sp.isEmpty {
                        let dishes: [MD] = (try? await SupabaseClient.shared.get(path: "menu_dishes?select=id,name")) ?? []
                        let nameBy = Dictionary(dishes.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
                        var seen = Set<String>(); var lines: [String] = []
                        for p in sp {
                            guard let nm = nameBy[p.dish_id], !seen.contains(nm) else { continue }
                            seen.insert(nm)
                            let star = (p.standout_wine_id == b.id && p.standout_reason != nil) ? " ★ \(p.standout_reason!)" : ""
                            lines.append("  [\(p.tier)] \(nm)\(star)")
                        }
                        if !lines.isEmpty { out += "\n\nPairs with (as a \(style)):\n" + lines.joined(separator: "\n") }
                    }
                }
                return out
            }
        )

        let getBottlesByVarietalTool = AnthropicTool(
            name: "get_bottles_by_varietal",
            description: "Fetch ALL bottles of a given varietal with full tasting notes and locations. ALWAYS call this when the user asks about a category (e.g. 'what cabernets do you have', 'what are the smoky scotches', 'recommend a bourbon'). Returns the complete authoritative set — your knowledge is welcome to add color but the tool data is the source of truth.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "varietal": ["type": "string", "description": "Varietal name as it appears in the catalog skeleton (e.g. 'Cabernet Sauvignon', 'Bourbon', 'Scotch', 'Tequila', 'Champagne')."]
                ],
                "required": ["varietal"]
            ],
            handler: { input in
                let v = (input["varietal"] as? String) ?? ""
                struct Row: Decodable {
                    let id: String; let name: String?; let varietal: String?; let category: String?
                    let tasting_notes: String?
                    let primary_area: String?; let primary_row: Int?; let primary_column: Int?
                    let backup_area: String?; let backup_row: Int?; let backup_column: Int?
                }
                let escaped = v.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? v
                let rows: [Row] = (try? await SupabaseClient.shared.get(path: "bottles?varietal=eq.\(escaped)&deleted=eq.false&unverified=eq.false&select=id,name,varietal,category,tasting_notes,primary_area,primary_row,primary_column,backup_area,backup_row,backup_column&order=name.asc")) ?? []
                if rows.isEmpty { return "No bottles with varietal '\(v)' found." }
                var out: [String] = ["\(v.uppercased()) (\(rows.count) bottles):\n"]
                for b in rows {
                    var line = "• \(b.name ?? b.id)"
                    if let p = b.primary_area {
                        var s = " @ \(p)"
                        if let r = b.primary_row { s += " R\(r)" }
                        if let c = b.primary_column { s += " C\(c)" }
                        line += s
                    }
                    if let bk = b.backup_area {
                        var s = " | bk \(bk)"
                        if let r = b.backup_row { s += " R\(r)" }
                        if let c = b.backup_column { s += " C\(c)" }
                        line += s
                    }
                    out.append(line)
                    if let t = b.tasting_notes { out.append("  \(t)") }
                    out.append("")
                }
                return out.joined(separator: "\n")
            }
        )

        let updateTool = AnthropicTool(
            name: "update_bottle_locations",
            description: "Set the primary or backup location for one or more wines. The 'area' must be one of the existing areas. 'row' and 'column' are integers (positive, zero, or negative). When the user lists multiple wines in sequence on the same row, batch them all into one call with auto-incrementing columns.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "updates": [
                        "type": "array",
                        "items": [
                            "type": "object",
                            "properties": [
                                "bottle_id": ["type": "string", "description": "Wine ID from the WINES list"],
                                "primary": [
                                    "type": "object",
                                    "properties": [
                                        "area":   ["type": "string"],
                                        "row":    ["type": "integer"],
                                        "column": ["type": "integer"]
                                    ]
                                ],
                                "backup": [
                                    "type": "object",
                                    "properties": [
                                        "area":   ["type": "string"],
                                        "row":    ["type": "integer"],
                                        "column": ["type": "integer"]
                                    ]
                                ]
                            ],
                            "required": ["bottle_id"]
                        ]
                    ]
                ],
                "required": ["updates"]
            ],
            handler: { input in
                let updates = (input["updates"] as? [[String: Any]]) ?? []
                let result = try await bottleStore.updateLocations(updates)
                // Each bottle's locations as saved, read back after the refresh, not as requested.
                let saved = result.updated.map { id -> String in
                    guard let b = bottleStore.bottles[id] else { return id }
                    return "\(b.displayName): primary \(locStr(b.primary) ?? "none"), backup \(locStr(b.backup) ?? "none")"
                }
                var msg = saved.isEmpty ? "Nothing updated." : "Saved — " + saved.joined(separator: "; ")
                let skipped = updates.count - result.updated.count - result.missing.count
                if skipped > 0 { msg += ". \(skipped) update(s) had no bottle_id or no location and were skipped" }
                if !result.missing.isEmpty {
                    msg += ". MISSING (these wines don't exist — call add_product first): \(result.missing.joined(separator: ", "))"
                }
                return msg
            }
        )

        let deleteProductDef = AnthropicTool(
            name: "delete_product",
            description: "Soft-delete a product from the catalog. Fails if the product is readonly. Data is preserved.",
            inputSchema: [
                "type": "object",
                "properties": ["id": ["type": "string"]],
                "required": ["id"]
            ],
            handler: { input in
                let pid = (input["id"] as? String) ?? ""
                struct Row: Decodable { let readonly: Bool?; let name: String? }
                let existing: [Row] = (try? await SupabaseClient.shared.get(path: "bottles?id=eq.\(pid)&select=readonly,name")) ?? []
                if existing.first?.readonly == true {
                    return "'\(existing.first?.name ?? pid)' is readonly and can't be deleted by the AI."
                }
                let rows = try await SupabaseClient.shared.patchReturning(path: "bottles?id=eq.\(pid)", body: ["deleted": true])
                await bottleStore.refreshBottles()
                if rows.isEmpty { return "Nothing deleted: no product with id '\(pid)'." }
                return "Deleted '\(existing.first?.name ?? pid)'."
            }
        )

        let addProductDef = AnthropicTool(
            name: "add_product",
            description: "Register a new product (wine, liquor, soda) in the catalog. Set name, kind, category, varietal, and optional location. DO NOT populate tasting_notes, food_pairing, or image_url here — those are filled in later via update_bottle_details and set_bottle_image. id is a kebab-case slug of the product name. For wines, category MUST be one of: 'Sparkling & Rosé', 'White Wine', 'Red Wine'; leave category empty for liquors. varietal is the marketing name on the bottle — for wines: 'Cabernet Sauvignon', 'Pinot Noir', 'Red Blend', 'Champagne', 'Prosecco', etc.; for liquors: 'Tequila', 'Bourbon', 'Vodka', 'Gin', 'Rum', 'Whiskey', 'Scotch', 'Cognac', 'Liqueur', etc. Use the bottle's own label.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "id":              ["type": "string"],
                    "name":            ["type": "string"],
                    "kind":            ["type": "string", "enum": ["wine","liquor","soda"]],
                    "category":        ["type": "string", "enum": ["Sparkling & Rosé","White Wine","Red Wine"]],
                    "varietal":        ["type": "string"],
                    "primary_area":    ["type": "string"],
                    "primary_row":     ["type": "integer"],
                    "primary_column":  ["type": "integer"],
                    "backup_area":     ["type": "string"],
                    "backup_row":      ["type": "integer"],
                    "backup_column":   ["type": "integer"]
                ],
                "required": ["id","name","kind"]
            ],
            handler: { input in
                var row: [String: Any] = [
                    "id": (input["id"] as? String) ?? "",
                    "name": (input["name"] as? String) ?? "",
                    "kind": (input["kind"] as? String) ?? "wine"
                ]
                for k in ["category","varietal","primary_area","primary_row","primary_column","backup_area","backup_row","backup_column"] {
                    if let v = input[k] { row[k] = v }
                }
                try await SupabaseClient.shared.upsert(path: "bottles", body: [row], onConflict: "id")
                await bottleStore.refreshBottles()
                guard let b = bottleStore.bottles[row["id"] as? String ?? ""] else {
                    return "Not saved: '\(row["name"] ?? "?")' is not in the catalog after the write."
                }
                return "Saved \(b.kind ?? "?") '\(b.displayName)' [id:\(b.id)]: primary \(locStr(b.primary) ?? "none"), backup \(locStr(b.backup) ?? "none")."
            }
        )

        let setImageDef = AnthropicTool(
            name: "set_bottle_image",
            description: "Set or replace a wine's bottle image URL. Prefer saratogawine.com product images (uniform white-background catalog shots like https://www.saratogawine.com/wp-content/uploads/.../xxx.jpg). If unavailable on Saratoga, fall back to the winery's own website. Always use a DIRECT image URL ending in .jpg/.png/.webp — never a product page URL.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "bottle_id":    ["type": "string"],
                    "image_url":  ["type": "string"]
                ],
                "required": ["bottle_id", "image_url"]
            ],
            handler: { input in
                let wid = (input["bottle_id"] as? String) ?? ""
                let url = (input["image_url"] as? String) ?? ""
                let rows = try await SupabaseClient.shared.patchReturning(path: "bottles?id=eq.\(wid)", body: ["image_url": url])
                await bottleStore.refreshBottles()
                if rows.isEmpty { return "Wine '\(wid)' not found — call add_product first." }
                return "Set image for '\(wid)'."
            }
        )

        let updateDetailsDef = AnthropicTool(
            name: "update_bottle_details",
            description: "Edit a bottle's name, category, varietal, tasting notes, or food pairing. Only include fields you want to change. Use \(Restaurant.name)'s voice for tasting notes and pairings — concise, professional, sensory-forward.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "bottle_id":     ["type": "string"],
                    "name":          ["type": "string"],
                    "category":      ["type": "string", "enum": ["Sparkling & Rosé","White Wine","Red Wine"]],
                    "varietal":      ["type": "string"],
                    "tasting_notes": ["type": "string"],
                    "food_pairing":  ["type": "string"]
                ],
                "required": ["bottle_id"]
            ],
            handler: { input in
                let wid = (input["bottle_id"] as? String) ?? ""
                var patch: [String: Any?] = [:]
                for k in ["name","category","varietal","tasting_notes","food_pairing"] {
                    if let v = input[k] as? String { patch[k] = v }
                }
                if patch.isEmpty { return "Nothing to update for '\(wid)'." }
                let rows = try await SupabaseClient.shared.patchReturning(path: "bottles?id=eq.\(wid)", body: patch)
                await bottleStore.refreshBottles()
                if rows.isEmpty { return "Wine '\(wid)' not found." }
                return "Updated '\(wid)': \(patch.keys.sorted().joined(separator: ", "))."
            }
        )

        // Applies restock updates (`add` or `set`) to the list as freshly fetched, so no count is ever worked out
        // against a stale copy, and returns what each item went from and to, so an answer reports the change
        // itself instead of working it out from a list that already holds the new item.
        func saveRestock(_ raw: [[String: Any]]) async throws -> [String] {
            await restockStore.refresh()
            let was = Dictionary(restockStore.items.map { ($0.product_id, $0.quantity) }, uniquingKeysWith: { a, _ in a })
            let updates = raw.map { u -> [String: Any] in
                let pid = u["product_id"] as! String
                var u = u
                u.removeValue(forKey: "quantity")
                if let set = u["set"] as? Int { u["quantity"] = max(set, 0) }
                else if let floor = u.removeValue(forKey: "at_least") as? Int { u["quantity"] = max(was[pid] ?? 0, floor) }
                else { u["quantity"] = max((was[pid] ?? 0) + (u["add"] as! Int), 0) }
                // A catalogued bottle's kind comes from its own row, never from the model: left to the
                // model it gets omitted or wrong, and the upsert overwrites a right kind with it.
                if let kind = bottleStore.bottles[pid]?.kind { u["product_kind"] = kind }
                return u
            }
            try await restockStore.apply(updates)
            return updates.map { u -> String in
                let pid = u["product_id"] as! String, qty = u["quantity"] as! Int
                let name = (u["name"] as? String) ?? bottleStore.bottles[pid]?.displayName ?? pid
                let before = was[pid] ?? 0
                if qty <= 0 { return "\(name) removed (was ×\(before))" }
                return "\(name) now ×\(qty) on the list (was " + (before > 0 ? "×\(before))" : "not on it)")
            }
        }

        let restockToolDef = AnthropicTool(
            name: "update_restock",
            description: "Add/change/remove items on the restock list. Give each item either `add` (how many more, negative to take some off — the tool adds it to whatever is on the list) or `set` (the exact new total; set 0 removes it). For real products use their existing id. For free-text items (oranges, lemons, etc.) use product_kind 'misc', a slug id, AND a name.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "updates": [
                        "type": "array",
                        "items": [
                            "type": "object",
                            "properties": [
                                "product_id":   ["type": "string", "description": "Slug. Real product → its existing id; free-text → kebab-case of the name."],
                                "product_kind": ["type": "string", "enum": ["wine","liquor","soda","misc"]],
                                "add":          ["type": "integer", "description": "Change in count: 1 for 'add X', 2 for 'two more', -1 for 'take one off'."],
                                "set":          ["type": "integer", "minimum": 0, "description": "Exact new total, only when the user names one ('make it 3') or to remove (0)."],
                                "name":         ["type": "string", "description": "Display name. REQUIRED when product_kind is 'misc'."]
                            ],
                            "required": ["product_id"]
                        ]
                    ]
                ],
                "required": ["updates"]
            ],
            handler: { input in
                // An update with neither `add` nor `set` (e.g. the old `quantity` field, which the model copies
                // from earlier turns' tool calls in its history) rejects the whole call, so it is resent rather
                // than dropped while the answer claims it saved.
                let raw = (input["updates"] as? [[String: Any]]) ?? []
                let bad = raw.filter { $0["product_id"] as? String == nil || ($0["add"] as? Int == nil && $0["set"] as? Int == nil) }
                if raw.isEmpty || !bad.isEmpty {
                    return "Nothing saved: every update needs product_id and either `add` or `set`. Send the whole call again."
                }
                return "Saved: " + (try await saveRestock(raw)).joined(separator: "; ") + ". This request is complete; do not change these items again for it."
            }
        )

        // Par sheets for the backup liquor cabinets live in Supabase (cabinets / cabinet_pars).
        struct CabinetRow: Decodable { let id: String; let name: String; let note: String? }
        struct ParRow: Decodable { let product_id: String; let product_kind: String; let name: String?; let quantity: Int }
        // The comparison is done here, not by the model: left to the model it dropped par items he never read
        // out, and answered with the shortfall when he asked for what was over par.
        let checkCabinetTool = AnthropicTool(
            name: "check_cabinet",
            description: "Use when the user reads out what is in a backup liquor cabinet. Pass every bottle he read, as catalog ids with counts. The tool compares it against the cabinet's par and returns the reply: what is missing and what is over par. Set add_to_restock only when he asks for the missing bottles to go on the restock list; if he asks for that after a check, call check_cabinet again with the same contents and add_to_restock true. Answer with the reply exactly as returned, nothing added. Never call update_restock for the shortfall.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "cabinet": ["type": "string", "description": "Cabinet id: 'dark' (dark liquor) or 'light' (light liquor)."],
                    "add_to_restock": ["type": "boolean", "description": "True only when he asked for the missing bottles to be added to the restock list. Omit otherwise."],
                    "contents": [
                        "type": "array",
                        "description": "Everything he read out as in the cabinet. Empty if he said it is empty.",
                        "items": [
                            "type": "object",
                            "properties": [
                                "product_id": ["type": "string", "description": "The bottle's catalog id. Match by sound: names arrive mangled by speech-to-text. A bare brand is that brand's plain bottle (Woodford Reserve, not Double Oaked or Rye); a variant only when its word is said."],
                                "count":      ["type": "integer", "minimum": 0]
                            ],
                            "required": ["product_id", "count"]
                        ]
                    ]
                ],
                "required": ["cabinet", "contents"]
            ],
            handler: { input in
                let cabinet = (input["cabinet"] as? String) ?? ""
                let enc = cabinet.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? cabinet
                let cabs: [CabinetRow] = (try? await SupabaseClient.shared.get(path: "cabinets?select=id,name,note&order=sort_order.asc")) ?? []
                guard cabs.contains(where: { $0.id == cabinet }) else {
                    return "Nothing saved: unknown cabinet. Cabinets: " + cabs.map { "\($0.id) (\($0.name))" }.joined(separator: ", ")
                }
                let pars: [ParRow] = try await SupabaseClient.shared.get(path: "cabinet_pars?cabinet_id=eq.\(enc)&select=product_id,product_kind,name,quantity&order=sort_order.asc")
                // What he read, in the order he said it.
                var read: [(key: String, name: String, count: Int)] = []
                for c in (input["contents"] as? [[String: Any]]) ?? [] {
                    guard let pid = c["product_id"] as? String, let b = bottleStore.bottles[pid] else {
                        return "Nothing saved: '\((c["product_id"] as? String) ?? "?")' is not a catalog id. Send the whole call again with ids from the catalog."
                    }
                    let count = (c["count"] as? Int) ?? 1
                    if let i = read.firstIndex(where: { $0.key == pid }) { read[i].count += count }
                    else { read.append((pid, b.displayName, count)) }
                }
                let have = Dictionary(read.map { ($0.key, $0.count) }, uniquingKeysWith: +)
                var adds: [[String: Any]] = []
                for p in pars where (have[p.product_id] ?? 0) < p.quantity {
                    // Raised to the shortfall, never added to it: the same reading checked twice (a retry after
                    // a timeout whose write had landed, or him reading it out again) otherwise doubles the list.
                    var u: [String: Any] = ["product_id": p.product_id, "product_kind": p.product_kind, "at_least": p.quantity - (have[p.product_id] ?? 0)]
                    if let n = p.name { u["name"] = n }
                    adds.append(u)
                }
                let parQty = Dictionary(pars.map { ($0.product_id, $0.quantity) }, uniquingKeysWith: +)
                let over = read.compactMap { r -> String? in
                    let n = r.count - (parQty[r.key] ?? 0)
                    return n > 0 ? "\(r.name) ×\(n)" : nil
                }
                let missing = adds.map { u -> String in
                    let pid = u["product_id"] as! String
                    return "\((u["name"] as? String) ?? bottleStore.bottles[pid]?.displayName ?? pid) ×\(u["at_least"] as! Int)"
                }
                // Only on his say-so: a check by itself writes nothing, so reading a cabinet out again never
                // touches the list.
                let adding = (input["add_to_restock"] as? Bool) == true && !adds.isEmpty
                let saved = adding ? try await saveRestock(adds) : []
                var reply: [String] = []
                if adding { reply.append("Shortfall was added to the restock list.") }
                if !missing.isEmpty { reply += ["Missing"] + missing }
                if !over.isEmpty { reply += (reply.isEmpty ? [] : [""]) + ["Over par"] + over }
                if missing.isEmpty && over.isEmpty { reply.append("At par") }
                return "Saved: " + (saved.isEmpty ? "nothing" : saved.joined(separator: "; ")) + ".\n\nReply:\n" + reply.joined(separator: "\n")
            }
        )

        let areasTool = AnthropicTool(
            name: "edit_areas",
            description: "Add, rename, or remove a wine storage area. Only call when the user explicitly asks to manage area names.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "action":   ["type": "string", "enum": ["add","rename","remove"]],
                    "name":     ["type": "string"],
                    "new_name": ["type": "string", "description": "Required for rename"]
                ],
                "required": ["action","name"]
            ],
            handler: { input in
                let action = (input["action"] as? String) ?? ""
                let name = (input["name"] as? String) ?? ""
                switch action {
                case "add":
                    try await bottleStore.addArea(name)
                case "rename":
                    guard let newName = input["new_name"] as? String else { return "Missing new_name." }
                    try await bottleStore.renameArea(name, to: newName)
                case "remove":
                    try await bottleStore.removeArea(name)
                default:
                    return "Unknown action '\(action)'."
                }
                // The areas as saved, so a rename or remove that matched nothing shows as unchanged.
                return "Areas now: " + bottleStore.areas.map(\.name).joined(separator: ", ")
            }
        )

        let searchBottlesTool = AnthropicTool(
            name: "search_bottles",
            description: "Search the wine & liquor catalog by any attribute and get the matching bottles with details. Use this for company/producer/region/style questions the varietal tool can't answer: 'what does Buffalo Trace make', 'which wines are from Napa', 'what does Pernod Ricard own', 'recommend a Structured Bold Red'. Returns the authoritative set — the tool data is the source of truth.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "field": ["type": "string", "enum": ["producer", "producer_parent", "location", "pairing_style", "varietal", "kind"],
                              "description": "Attribute to filter on. producer_parent = overarching company; location = region/country; pairing_style = wine-pairing style bucket; kind = 'wine' or 'liquor'."],
                    "value": ["type": "string", "description": "Value to match exactly, as it appears in the catalog."]
                ],
                "required": ["field", "value"]
            ],
            handler: { input in
                let field = (input["field"] as? String) ?? ""
                let value = (input["value"] as? String) ?? ""
                let allowed = ["producer", "producer_parent", "location", "pairing_style", "varietal", "kind"]
                guard allowed.contains(field), !value.isEmpty else { return "field must be one of \(allowed) and value is required." }
                let enc = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
                struct Row: Decodable {
                    let id: String; let name: String?; let kind: String?; let varietal: String?
                    let producer: String?; let producer_parent: String?; let location: String?
                    let abv: String?; let pairing_style: String?; let tasting_notes: String?
                }
                let rows: [Row] = (try? await SupabaseClient.shared.get(path: "bottles?\(field)=eq.\(enc)&deleted=eq.false&unverified=eq.false&select=id,name,kind,varietal,producer,producer_parent,location,abv,pairing_style,tasting_notes&order=name.asc")) ?? []
                if rows.isEmpty { return "No bottles where \(field) = '\(value)'." }
                var out = ["\(field.uppercased()) = \(value) (\(rows.count) bottles):", ""]
                for b in rows {
                    let bits = [b.varietal, b.abv].compactMap { $0 }
                    out.append("• \(b.name ?? b.id) [id:\(b.id)]" + (bits.isEmpty ? "" : " — \(bits.joined(separator: " · "))"))
                    if let t = b.tasting_notes { out.append("  \(t)") }
                }
                return out.joined(separator: "\n")
            }
        )

        let getPairingsTool = AnthropicTool(
            name: "get_pairings",
            description: "Get the curated wine pairings for a DISH (which wine styles go with it, with reasons and the bottles in each) or the dishes a WINE pairs with. ALWAYS call this for pairing questions ('what wine goes with the ribeye', 'what should I drink with the lobster mac', 'what does the Cabernet pair with'). These are hand-authored, mechanism-based pairings and the source of truth — do NOT improvise pairings from general knowledge when this can answer.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "dish_name": ["type": "string", "description": "A dish name (or close phrase) to get its wine pairings."],
                    "wine_id": ["type": "string", "description": "A wine's bottle id to get the dishes it pairs with."]
                ],
                "required": []
            ],
            handler: { input in
                let dishName = (input["dish_name"] as? String) ?? ""
                let wineId = (input["wine_id"] as? String) ?? ""
                struct MD: Decodable { let id: String; let name: String }
                struct W: Decodable { let id: String; let name: String?; let pairing_style: String? }
                struct SP: Decodable { let style: String?; let dish_id: String?; let tier: String; let justification: String?; let leaves_out: String?; let standout_wine_id: String?; let standout_reason: String? }
                let dishes: [MD] = (try? await SupabaseClient.shared.get(path: "menu_dishes?select=id,name")) ?? []
                let wines: [W] = (try? await SupabaseClient.shared.get(path: "bottles?kind=eq.wine&deleted=eq.false&select=id,name,pairing_style")) ?? []
                let wname = Dictionary(wines.map { ($0.id, $0.name ?? $0.id) }, uniquingKeysWith: { a, _ in a })
                if !wineId.isEmpty {
                    guard let style = wines.first(where: { $0.id == wineId })?.pairing_style else { return "\(wname[wineId] ?? wineId) has no pairing style set." }
                    let enc = style.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? style
                    let sp: [SP] = (try? await SupabaseClient.shared.get(path: "style_pairings?style=eq.\(enc)&select=dish_id,tier,standout_wine_id,standout_reason&order=sort_order.asc")) ?? []
                    let nameBy = Dictionary(dishes.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
                    var seen = Set<String>(); var lines: [String] = []
                    for p in sp {
                        guard let did = p.dish_id, let nm = nameBy[did], !seen.contains(nm) else { continue }
                        seen.insert(nm)
                        let star = (p.standout_wine_id == wineId && p.standout_reason != nil) ? " ★ \(p.standout_reason!)" : ""
                        lines.append("[\(p.tier)] \(nm)\(star)")
                    }
                    return lines.isEmpty ? "No pairings found for \(wname[wineId] ?? wineId)." : "\(wname[wineId] ?? wineId) (as a \(style)) pairs with:\n" + lines.joined(separator: "\n")
                }
                if !dishName.isEmpty {
                    let tgt = normalizeDishName(dishName)
                    var slugs = dishes.filter { normalizeDishName($0.name) == tgt }.map { $0.id }
                    if slugs.isEmpty { slugs = dishes.filter { normalizeDishName($0.name).contains(tgt) || tgt.contains(normalizeDishName($0.name)) }.map { $0.id } }
                    guard let slug = slugs.first else { return "No dish matching '\(dishName)'." }
                    let dn = dishes.first(where: { $0.id == slug })?.name ?? dishName
                    let sp: [SP] = (try? await SupabaseClient.shared.get(path: "style_pairings?dish_id=eq.\(slug.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? slug)&select=style,tier,justification,leaves_out,standout_wine_id,standout_reason&order=sort_order.asc")) ?? []
                    if sp.isEmpty { return "No curated pairings for \(dn)." }
                    var out = ["Wine pairings for \(dn):", ""]
                    for p in sp {
                        out.append("[\(p.tier)] \(p.style ?? "?") — \(p.justification ?? "")")
                        if let sid = p.standout_wine_id, let r = p.standout_reason { out.append("   ★ \(wname[sid] ?? sid): \(r)") }
                        if let st = p.style {
                            struct BN: Decodable { let name: String? }
                            let bn: [BN] = (try? await SupabaseClient.shared.get(path: "bottles?kind=eq.wine&deleted=eq.false&pairing_style=eq.\(st.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? st)&select=name&order=name.asc")) ?? []
                            let names = bn.compactMap { $0.name }
                            if !names.isEmpty { out.append("   bottles: " + names.joined(separator: ", ")) }
                        }
                        out.append("")
                    }
                    if let lo = sp.first?.leaves_out, !lo.isEmpty { out.append("Not listed: \(lo)") }
                    return out.joined(separator: "\n")
                }
                return "Provide either dish_name or wine_id."
            }
        )

        let tools: [AnthropicTool] = [
            getFoodMenuTool, getSeasonalProgramTool, getBottleDetailsTool, getBottlesByVarietalTool,
            searchBottlesTool, getPairingsTool,
            updateTool, areasTool, restockToolDef, checkCabinetTool,
            addProductDef, deleteProductDef, setImageDef, updateDetailsDef,
        ]
        return (systemStable, systemDynamic, tools)
    }
}
