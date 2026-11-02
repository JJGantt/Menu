import SwiftUI

// MARK: - Content View

enum TopSection: String, CaseIterable, Identifiable {
    case food = "Food"
    case wine = "Wine"
    case liquor = "Liquor"
    case cocktails = "Cocktails"
    case restock = "Restock"
    case orders = "Orders"
    var id: String { rawValue }

    /// The order list is the owner's alone (it sits behind the hub's owner-gated route).
    static var shown: [TopSection] { allCases.filter { $0 != .orders || AppGate.isOwnerDevice } }
}

struct ContentView: View {
    @StateObject private var store = MenuStore()
    @StateObject private var bottleStore = BottleStore()
    @StateObject private var restockStore = RestockStore()
    @StateObject private var cocktailStore = CocktailStore()
    @StateObject private var orderStore = OrderStore()
    @StateObject private var voice = VoiceRecorder()
    @State private var searchText = ""
    @State private var section: TopSection = .food

    @State private var liquorExpanded: Set<String> = []
    @State private var selectedDish: Dish?
    @State private var selectedWine: Bottle?
    @State private var selectedCocktail: Cocktail?
    @State private var selectedSeasonalWine: SeasonalWine?
    @State private var showSettings = false
    @State private var aiMode = true        // AI is the default field mode
    @State private var showAIResults = false  // chat overlay visibility
    @State private var aiInput = ""
    @State private var aiHistory: [QAExchange] = []
    @State private var aiSessionId: String = UUID().uuidString
    @State private var aiBusy = false
    @State private var aiError: String?
    @State private var aiActivity: String?
    @State private var pendingQuestion: String?

    struct QAExchange: Identifiable {
        let id = UUID()
        let turn: ChatTurn
        var question: String { turn.question }
        var answer: String { turn.answer }
    }

    var body: some View {
        mainContent
            .background(Color.cgBackground.ignoresSafeArea())
            .fullScreenCover(item: $selectedDish) { dish in
                NavigationStack {
                    DishDetailView(dish: dish, store: bottleStore)
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button(action: { selectedDish = nil }) {
                                    Image(systemName: "chevron.left").foregroundColor(.cgAccent)
                                }
                            }
                        }
                }
                .environment(\.closeDetail) { selectedDish = nil }
                .glossaryHost(bottleStore)
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(bottleStore: bottleStore)
            }
            .fullScreenCover(item: $selectedCocktail) { cocktail in
                NavigationStack {
                    CocktailDetailView(cocktail: cocktail)
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button(action: { selectedCocktail = nil }) {
                                    Image(systemName: "chevron.left").foregroundColor(.cgAccent)
                                }
                            }
                        }
                }
            }
            .fullScreenCover(item: $selectedSeasonalWine) { wine in
                NavigationStack {
                    SeasonalWineDetailView(wine: wine)
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button(action: { selectedSeasonalWine = nil }) {
                                    Image(systemName: "chevron.left").foregroundColor(.cgAccent)
                                }
                            }
                        }
                }
            }
            .fullScreenCover(item: $selectedWine) { wine in
                NavigationStack {
                    WineDetailView(wine: wine, store: bottleStore)
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button(action: { selectedWine = nil }) {
                                    Image(systemName: "chevron.left").foregroundColor(.cgAccent)
                                }
                            }
                        }
                }
                .environment(\.closeDetail) { selectedWine = nil }
                .glossaryHost(bottleStore)
            }
            .onAppear {
                if store.menu == nil { store.load() }
                if cocktailStore.cocktails.isEmpty { cocktailStore.load() }
                Task {
                    await bottleStore.refreshFromSupabase()
                    await restockStore.refresh()
                    #if DEBUG
                    // Simulator hooks, so a check needs no typing: `-simSection <tab>` opens a tab,
                    // `-simSearch <text>` searches, and `-simAsk "<question>"` asks the assistant once
                    // the catalog is in.
                    if let tab = UserDefaults.standard.string(forKey: "simSection"),
                       let s = TopSection.allCases.first(where: { $0.rawValue.lowercased() == tab.lowercased() }) {
                        section = s
                    }
                    if let q = UserDefaults.standard.string(forKey: "simSearch") { searchText = q }
                    if let q = UserDefaults.standard.string(forKey: "simAsk") { askAI(question: q) }
                    #endif
                }
            }
            // Hand the loaded food menu to the bottle store so it can resolve pairing
            // dish slugs to real Dishes (the menu lives here, the pairings there).
            .onReceive(store.$menu.compactMap { $0 }) { menu in
                bottleStore.menuDishes = fullMenuDishIndex(menu)
                let seasonal = menu.seasonal_programs.flatMap { $0.sections.flatMap(\.dishes) }
                let photos = (menu.allDishes + seasonal).compactMap { dishPhotoURL($0.image) }
                Task { await RemoteImageCache.shared.prefetch(photos) }
            }
    }

    var mainContent: some View {
        VStack(spacing: 0) {
            // Top: Food / Wine / Liquor / Restock segmented control.
            // Tapping any segment also closes the AI conversation view — including
            // the currently-active segment (which native Picker wouldn't notify us about).
            HStack(spacing: 0) {
                ForEach(TopSection.shown) { s in
                    Button(action: {
                        withAnimation {
                            section = s
                            if showAIResults { showAIResults = false }
                        }
                    }) {
                        Text(s.rawValue)
                            .font(.subheadline.weight(section == s ? .semibold : .regular))
                            .foregroundColor(section == s ? .cgText : .cgTextMuted)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: 7)
                                    .fill(section == s ? Color.cgCard : Color.clear)
                                    .padding(2)
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(Color.cgBorder.opacity(0.25))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .onChange(of: searchText) { _ in autoSwitchForSearch() }
            .padding(.horizontal, 12)
            .padding(.top, 6)
            .padding(.bottom, 8)

            // Content first, takes remaining space; input bar pinned below it.
            contentArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            MenuInputBar(
                voice: voice,
                section: section,
                aiMode: $aiMode,
                aiInput: $aiInput,
                searchText: $searchText,
                showAIResults: $showAIResults,
                busy: aiBusy,
                hasChat: !aiHistory.isEmpty,
                onAsk: { askAI(question: $0) },
                onShowSettings: { showSettings = true },
                onClearChat: clearChat
            )
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    @ViewBuilder
    var contentArea: some View {
        if showAIResults {
            AssistantChatView(history: aiHistory, pendingQuestion: pendingQuestion,
                              busy: aiBusy, activity: aiActivity, error: aiError)
        } else if section == .wine {
            WineListView(store: bottleStore, searchText: searchText) { wine in
                selectedWine = wine
            }
        } else if section == .liquor {
            LiquorListView(bottleStore: bottleStore, expanded: $liquorExpanded, searchText: searchText) { bottle in
                selectedWine = bottle
            }
        } else if section == .cocktails {
            CocktailsListView(cocktails: cocktailStore.cocktails,
                              searchText: searchText) { cocktail in
                selectedCocktail = cocktail
            }
        } else if section == .restock {
            RestockListView(restockStore: restockStore, bottleStore: bottleStore)
        } else if section == .orders {
            OrdersListView(store: orderStore)
        } else {
            FoodMenuView(menu: store.menu, searchText: searchText,
                         onTapDish: { selectedDish = $0 },
                         onTapSeasonalWine: { selectedSeasonalWine = $0 })
        }
    }

    /// When the user types a search, jump to whichever tab has the most matches.
    /// Stays put if the current tab has the most (or if there are no matches anywhere).
    private func autoSwitchForSearch() {
        let q = searchText.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }

        let foodCount: Int = {
            guard let menu = store.menu else { return 0 }
            var n = menu.allDishes.filter { dishMatches($0, query: q) }.count
            for program in menu.seasonal_programs {
                n += program.wines.filter { seasonalWineMatches($0, query: q) }.count
                n += program.sections.reduce(0) { $0 + $1.dishes.filter { seasonalDishMatches($0, query: q) }.count }
            }
            return n
        }()
        let wineCount = bottleStore.wineCategories.flatMap(\.bottles).filter { bottleMatches($0, query: q) }.count
        let liquorCount = bottleStore.liquors.filter { bottleMatches($0, query: q) }.count
        let cocktailCount = cocktailStore.cocktails.filter { cocktailMatches($0, query: q) }.count

        let counts: [(TopSection, Int)] = [
            (.food, foodCount), (.wine, wineCount), (.liquor, liquorCount), (.cocktails, cocktailCount)
        ]
        guard let best = counts.max(by: { $0.1 < $1.1 }), best.1 > 0 else { return }

        // Stay put if current tab already has matches at the top.
        let currentCount = counts.first(where: { $0.0 == section })?.1 ?? 0
        if currentCount == best.1 { return }

        withAnimation { section = best.0 }
    }

    func askAI(question: String) {
        guard !aiBusy else { return }
        let history = aiHistory.map(\.turn)
        aiBusy = true
        aiError = nil
        aiActivity = nil
        aiInput = ""
        pendingQuestion = question
        withAnimation { showAIResults = true }

        Task {
            do {
                let turn = try await askAnything(question: question, history: history)
                await MainActor.run {
                    aiHistory.append(QAExchange(turn: turn))
                    pendingQuestion = nil
                    aiBusy = false
                    aiActivity = nil
                }
            } catch {
                await MainActor.run {
                    aiError = error.localizedDescription
                    pendingQuestion = nil
                    aiBusy = false
                    aiActivity = nil
                }
            }
        }
    }

    private func clearChat() {
        aiHistory.removeAll()
        aiError = nil
        showAIResults = false
        aiSessionId = UUID().uuidString
    }

    @MainActor
    private func askAnything(question: String, history: [ChatTurn]) async throws -> ChatTurn {
        let engine = ChatEngine(menuStore: store, bottleStore: bottleStore, restockStore: restockStore, cocktailStore: cocktailStore, surface: "ios")
        return try await engine.ask(question: question, history: history, sessionId: aiSessionId) { activity in
            self.aiActivity = activity
        }
    }
}
