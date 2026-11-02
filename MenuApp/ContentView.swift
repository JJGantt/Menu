import SwiftUI

// MARK: - Pulsing mic indicator

struct PulsingMic: View {
    @State private var pulse = false
    var body: some View {
        Image(systemName: "mic.fill")
            .foregroundColor(.green)
            .scaleEffect(pulse ? 1.15 : 0.95)
            .opacity(pulse ? 1.0 : 0.6)
            .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: pulse)
            .onAppear { pulse = true }
    }
}

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

            inputBar
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
    }

    @ViewBuilder
    var contentArea: some View {
        if showAIResults {
            aiResultsView
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
            menuListView
        }
    }

    var inputBar: some View {
        VStack(spacing: 6) {
        HStack(alignment: .top, spacing: 8) {
                if voice.isRecording {
                    HStack(alignment: .top, spacing: 8) {
                        PulsingMic()
                            .padding(.top, 2)
                        Text(voice.transcript.isEmpty ? "Listening…" : voice.transcript)
                            .font(.body)
                            .foregroundColor(.cgText)
                            .lineLimit(6, reservesSpace: false)
                            .truncationMode(.head)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color.cgCard)
                    .clipShape(RoundedRectangle(cornerRadius: 22))
                    .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.green.opacity(0.7), lineWidth: 1.5))
                } else if aiMode || section != .restock {
                    HStack(spacing: 8) {
                        Image(systemName: aiMode ? "sparkles" : "magnifyingglass")
                            .foregroundColor(aiMode ? .cgAccent : .cgTextMuted)
                        if aiMode {
                            TextField("Ask the menu…", text: $aiInput)
                                .submitLabel(.send)
                                .onSubmit { askAI() }
                                .disabled(aiBusy)
                        } else {
                            TextField(section == .wine ? "Search wines…" : "Search dishes, ingredients…", text: $searchText)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .submitLabel(.search)
                        }
                        if aiMode {
                            if aiBusy {
                                ProgressView().progressViewStyle(.circular).scaleEffect(0.8)
                            } else {
                                Button(action: askAI) {
                                    Image(systemName: "arrow.up.circle.fill")
                                        .font(.title2)
                                        .foregroundColor(aiInput.trimmingCharacters(in: .whitespaces).isEmpty ? .cgBorder : .cgAccent)
                                }
                                .disabled(aiInput.trimmingCharacters(in: .whitespaces).isEmpty)
                            }
                        } else if !searchText.isEmpty {
                            Button(action: { searchText = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.cgTextMuted)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color.cgCard)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(aiMode ? Color.cgAccent : Color.cgBorder, lineWidth: aiMode ? 1.5 : 1))
                } else {
                    Spacer()
                }

                if voice.isRecording {
                    Button(action: { _ = voice.stop() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundColor(.cgTextMuted)
                            .padding(8)
                    }
                    Button(action: primaryAIButtonTap) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title3)
                            .foregroundColor(.green)
                            .padding(8)
                    }
                } else {
                    // Mic always available — destination depends on current mode.
                    Button(action: { Task { await voice.start() } }) {
                        Image(systemName: "mic.fill")
                            .font(.title3)
                            .foregroundColor(.cgAccent)
                            .padding(8)
                    }
                    // Toggle between AI and search modes.
                    Button(action: { withAnimation { aiMode.toggle() } }) {
                        Image(systemName: aiMode ? "magnifyingglass" : "sparkles")
                            .font(.title3)
                            .foregroundColor(aiMode ? .cgTextMuted : .cgAccent)
                            .padding(8)
                    }
                }
            }

            // Bottom toolbar: settings + chat-history toggle + clear (in chat with history)
            HStack {
                Button(action: { showSettings = true }) {
                    Image(systemName: "gearshape")
                        .font(.title3)
                        .foregroundColor(.cgTextMuted)
                        .padding(8)
                }
                if !aiHistory.isEmpty {
                    Button(action: { withAnimation { showAIResults.toggle() } }) {
                        Image(systemName: showAIResults ? "bubble.left.fill" : "bubble.left")
                            .font(.title3)
                            .foregroundColor(showAIResults ? .cgAccent : .cgTextMuted)
                            .padding(8)
                    }
                }
                Spacer()
                if showAIResults && !aiHistory.isEmpty {
                    Button(action: { withAnimation {
                        aiHistory.removeAll()
                        aiError = nil
                        showAIResults = false
                        aiSessionId = UUID().uuidString
                    } }) {
                        Image(systemName: "trash")
                            .font(.title3)
                            .foregroundColor(.cgTextMuted)
                            .padding(8)
                    }
                }
            }
        }
    }

    /// When the user types a search, jump to whichever tab has the most matches.
    /// Stays put if the current tab has the most (or if there are no matches anywhere).
    private func autoSwitchForSearch() {
        let q = searchText.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }

        let foodCount: Int = {
            guard let menu = store.menu else { return 0 }
            var n = menu.allDishes.filter { matches(dish: $0, query: q) }.count
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

    func toggleAIMode() {
        withAnimation {
            aiMode.toggle()
            if !aiMode {
                aiInput = ""
                aiError = nil
            }
        }
    }

    private var primaryAIButtonIcon: String {
        if voice.isRecording { return "arrow.up.circle.fill" }
        return "sparkles"
    }

    /// Parse markdown so **bold**, *italic*, lists, etc. render properly.
    /// Falls back to plain text if parsing fails.
    private func renderMarkdown(_ source: String) -> AttributedString {
        if let attr = try? AttributedString(
            markdown: source,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace
            )
        ) {
            return attr
        }
        return AttributedString(source)
    }

    private func primaryAIButtonTap() {
        if voice.isRecording {
            let q = voice.stop().trimmingCharacters(in: .whitespacesAndNewlines)
            guard !q.isEmpty else { return }
            if aiMode {
                askAI(question: q)
            } else {
                searchText = q
            }
        } else {
            Task { await voice.start() }
        }
    }

    func askAI() {
        let q = aiInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        askAI(question: q)
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

    @MainActor
    private func askAnything(question: String, history: [ChatTurn]) async throws -> ChatTurn {
        let engine = ChatEngine(menuStore: store, bottleStore: bottleStore, restockStore: restockStore, cocktailStore: cocktailStore, surface: "ios")
        return try await engine.ask(question: question, history: history, sessionId: aiSessionId) { activity in
            self.aiActivity = activity
        }
    }


    @ViewBuilder
    var aiResultsView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                aiResultsContent
                Color.clear.frame(height: 1).id("bottomAnchor")
            }
            .scrollDismissesKeyboard(.immediately)
            .onAppear { proxy.scrollTo("bottomAnchor", anchor: .bottom) }
            .onChange(of: aiHistory.count) { _ in
                withAnimation { proxy.scrollTo("bottomAnchor", anchor: .bottom) }
            }
            .onChange(of: pendingQuestion) { _ in
                withAnimation { proxy.scrollTo("bottomAnchor", anchor: .bottom) }
            }
        }
    }

    /// A single chat message in its own bordered card — used for both the user
    /// prompt and the AI response so each is separated the same way exchanges are.
    @ViewBuilder
    func chatBubble<Content: View>(icon: String,
                                   iconColor: Color,
                                   iconAlignment: VerticalAlignment = .top,
                                   @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: iconAlignment, spacing: 6) {
            Image(systemName: icon)
                .foregroundColor(iconColor)
                .font(.callout)
            content()
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.cgCard)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.cgBorder, lineWidth: 1))
    }

    @ViewBuilder
    var aiResultsContent: some View {
            VStack(alignment: .leading, spacing: 12) {
                if aiHistory.isEmpty && aiError == nil && pendingQuestion == nil {
                    VStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.title)
                            .foregroundColor(.cgAccent.opacity(0.5))
                        Text("Ask anything")
                            .font(.callout)
                            .foregroundColor(.cgTextMuted)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
                }
                ForEach(aiHistory) { ex in
                    chatBubble(icon: "person.crop.circle.fill", iconColor: .cgTextMuted) {
                        Text(ex.question)
                            .font(.callout)
                            .fontWeight(.semibold)
                            .foregroundColor(.cgText)
                    }
                    chatBubble(icon: "sparkles", iconColor: .cgAccent) {
                        Text(renderMarkdown(ex.answer))
                            .font(.callout)
                            .foregroundColor(.cgText)
                            .textSelection(.enabled)
                    }
                }
                if let pending = pendingQuestion {
                    chatBubble(icon: "person.crop.circle.fill", iconColor: .cgTextMuted) {
                        Text(pending)
                            .font(.callout)
                            .fontWeight(.semibold)
                            .foregroundColor(.cgText)
                    }
                    chatBubble(icon: "sparkles", iconColor: .cgAccent, iconAlignment: .center) {
                        ProgressView().progressViewStyle(.circular).scaleEffect(0.7)
                    }
                }
                // Tool-use / activity indicator — at the BOTTOM so it's the most recent
                // thing visible in a long conversation (auto-scrolled into view).
                if aiBusy, let activity = aiActivity {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "wrench.and.screwdriver.fill")
                            .foregroundColor(.cgAccent.opacity(0.7))
                            .font(.caption)
                        Text(activity)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.cgTextMuted)
                            .textSelection(.enabled)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.cgCard.opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.cgBorder.opacity(0.6), lineWidth: 1))
                }
                if let err = aiError {
                    Text(err)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.red.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
    }

    @ViewBuilder
    var menuListView: some View {
        ScrollView { menuListContent }
            .scrollDismissesKeyboard(.immediately)
    }

    @ViewBuilder
    var menuListContent: some View {
        Group {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if let menu = store.menu {
                        ForEach(menu.groups) { group in
                            let dishes = filteredDishes(menu.dishes(in: group))
                            if !dishes.isEmpty {
                                MenuGroupView(
                                    title: group.title,
                                    dishes: dishes,
                                    sectionOrder: group.sections,
                                    defaultExpanded: group.id == menu.groups.first?.id || !searchText.isEmpty,
                                    forceExpandSections: !searchText.isEmpty,
                                    onTapDish: { dish in selectedDish = dish }
                                )
                                .id("\(group.id)-\(searchText)")
                            }
                        }
                        ForEach(menu.seasonal_programs, id: \.meta.title) { program in
                            SeasonalProgramView(
                                program: program,
                                menu: menu,
                                query: searchText,
                                defaultExpanded: !searchText.isEmpty,
                                onTapDish: { selectedDish = $0 },
                                onTapWine: { selectedSeasonalWine = $0 }
                            )
                            .id("seasonal-\(program.meta.title)-\(searchText)")
                        }
                    } else {
                        ProgressView().padding(40)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
        }
    }

    // Filter logic
    func filteredDishes(_ dishes: [Dish]) -> [Dish] {
        let q = searchText.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return dishes }
        return dishes.filter { matches(dish: $0, query: q) }
    }

    func matches(dish: Dish, query q: String) -> Bool {
        if dish.name.lowercased().contains(q) { return true }
        if let d = dish.description?.lowercased(), d.contains(q) { return true }
        if let mn = dish.menu_name?.lowercased(), mn.contains(q) { return true }
        if let sp = dish.serving_piece?.lowercased(), sp.contains(q) { return true }
        if let st = dish.station?.lowercased(), st.contains(q) { return true }
        if let portion = dish.portion {
            for p in portion {
                if let ing = p.ingredient?.lowercased(), ing.contains(q) { return true }
                if let am = p.amount?.lowercased(), am.contains(q) { return true }
                if let pr = p.prep?.lowercased(), pr.contains(q) { return true }
            }
        }
        if let garnish = dish.garnish {
            for g in garnish {
                if let ing = g.ingredient?.lowercased(), ing.contains(q) { return true }
            }
        }
        if let tp = dish.talking_points {
            for p in tp where p.lowercased().contains(q) { return true }
        }
        if let notes = dish.notes {
            for n in notes where n.lowercased().contains(q) { return true }
        }
        return false
    }
}

// MARK: - Menu Group (top-level: Dinner, Lunch, etc.)

struct MenuGroupView: View {
    let title: String
    let dishes: [Dish]
    let sectionOrder: [String]
    let defaultExpanded: Bool
    let forceExpandSections: Bool
    let onTapDish: (Dish) -> Void
    @State private var isExpanded: Bool

    init(title: String, dishes: [Dish], sectionOrder: [String], defaultExpanded: Bool, forceExpandSections: Bool, onTapDish: @escaping (Dish) -> Void) {
        self.title = title
        self.dishes = dishes
        self.sectionOrder = sectionOrder
        self.defaultExpanded = defaultExpanded
        self.forceExpandSections = forceExpandSections
        self.onTapDish = onTapDish
        _isExpanded = State(initialValue: defaultExpanded)
    }

    var body: some View {
        let sections = dishesBySection(dishes, sectionOrder: sectionOrder)
        VStack(alignment: .leading, spacing: 0) {
            Button(action: { withAnimation { isExpanded.toggle() } }) {
                HStack {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundColor(.cgAccent.opacity(0.7))
                    Text(title.uppercased())
                        .font(.system(.title3, design: .serif))
                        .tracking(3)
                        .foregroundColor(.cgAccent)
                    Spacer()
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    Divider().background(Color.cgBorder.opacity(0.6))
                    if sections.count == 1 {
                        ForEach(sections[0].1) { dish in
                            DishRow(dish: dish, onTap: { onTapDish(dish) })
                            if dish.id != sections[0].1.last?.id {
                                Divider().background(Color.cgBorder.opacity(0.3))
                                    .padding(.leading, 70)
                            }
                        }
                    } else {
                        ForEach(sections, id: \.0) { section, items in
                            SectionView(title: section, dishes: items, defaultExpanded: forceExpandSections, onTapDish: onTapDish)
                        }
                    }
                }
                .padding(.bottom, 8)
            }
        }
        .background(Color.cgCard)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.cgBorder, lineWidth: 1)
        )
    }
}

// MARK: - Section View

struct SectionView: View {
    let title: String
    let dishes: [Dish]
    let defaultExpanded: Bool
    let onTapDish: (Dish) -> Void
    @State private var isExpanded: Bool

    init(title: String, dishes: [Dish], defaultExpanded: Bool, onTapDish: @escaping (Dish) -> Void) {
        self.title = title
        self.dishes = dishes
        self.defaultExpanded = defaultExpanded
        self.onTapDish = onTapDish
        _isExpanded = State(initialValue: defaultExpanded)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: { withAnimation { isExpanded.toggle() } }) {
                HStack {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10))
                        .foregroundColor(.cgTextMuted)
                    Text(title.uppercased())
                        .font(.system(.subheadline, design: .serif))
                        .fontWeight(.semibold)
                        .tracking(1)
                        .foregroundColor(.cgText)
                    Text("(\(dishes.count))")
                        .font(.caption)
                        .foregroundColor(.cgTextMuted)
                    Spacer()
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 18)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(dishes) { dish in
                        DishRow(dish: dish, onTap: { onTapDish(dish) })
                        if dish.id != dishes.last?.id {
                            Divider().background(Color.cgBorder.opacity(0.3))
                                .padding(.leading, 70)
                        }
                    }
                }
                .padding(.bottom, 4)
            }
            Divider().background(Color.cgBorder.opacity(0.4))
        }
    }
}

// MARK: - Dish Row

struct DishRow: View {
    let dish: Dish
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // No photo → no thumbnail (and no reserved space).
                DishPhoto(dish.image) { ui in
                    Image(uiImage: ui)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.cgBorder.opacity(0.6), lineWidth: 1))
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(dish.name)
                        .font(.system(.body, design: .serif))
                        .foregroundColor(.cgText)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                    HStack(spacing: 6) {
                        if let price = dish.price {
                            Text("$\(price)")
                                .font(.caption.bold())
                                .foregroundColor(.cgAccent)
                        }
                        if let cal = dish.calories {
                            if dish.price != nil {
                                Text("·").foregroundColor(.cgTextMuted).font(.caption)
                            }
                            Text("\(cal) cal")
                                .font(.caption)
                                .foregroundColor(.cgTextMuted)
                        }
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundColor(.cgTextMuted)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Seasonal program card (the current limited-time menu)

struct SeasonalProgramView: View {
    let program: SeasonalProgram
    let dishIndex: [String: Dish]
    let query: String
    let defaultExpanded: Bool
    let onTapDish: (Dish) -> Void
    let onTapWine: (SeasonalWine) -> Void
    @State private var isExpanded: Bool

    init(program: SeasonalProgram, menu: MenuData, query: String, defaultExpanded: Bool,
         onTapDish: @escaping (Dish) -> Void,
         onTapWine: @escaping (SeasonalWine) -> Void) {
        self.program = program
        self.dishIndex = fullMenuDishIndex(menu)
        self.query = query
        self.defaultExpanded = defaultExpanded
        self.onTapDish = onTapDish
        self.onTapWine = onTapWine
        _isExpanded = State(initialValue: defaultExpanded)
    }

    private func resolved(_ dish: Dish) -> Dish { resolveSeasonalDish(dish, using: dishIndex) }

    private var q: String { query.lowercased().trimmingCharacters(in: .whitespaces) }

    private var filteredWines: [SeasonalWine] {
        q.isEmpty ? program.wines : program.wines.filter { seasonalWineMatches($0, query: q) }
    }

    private var filteredSections: [SeasonalSection] {
        program.sections.compactMap { section in
            let resolvedDishes = section.dishes.map { resolved($0) }
            let shown = q.isEmpty ? resolvedDishes : resolvedDishes.filter { seasonalDishMatches($0, query: q) }
            return shown.isEmpty ? nil
                : SeasonalSection(title: section.title, paired_wines: section.paired_wines, dishes: shown)
        }
    }

    private var hasContent: Bool { !filteredWines.isEmpty || !filteredSections.isEmpty }

    var body: some View {
        // When searching with no matches here, render nothing (no empty card).
        if !q.isEmpty && !hasContent {
            EmptyView()
        } else {
            card
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: { withAnimation { isExpanded.toggle() } }) {
                HStack {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundColor(.cgAccent.opacity(0.7))
                    Text(program.meta.title.uppercased())
                        .font(.system(.title3, design: .serif))
                        .tracking(3)
                        .foregroundColor(.cgAccent)
                    Spacer()
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    Divider().background(Color.cgBorder.opacity(0.6))
                    metaBlock
                    ForEach(filteredSections, id: \.title) { section in
                        sectionView(section)
                    }
                    if !filteredWines.isEmpty {
                        winesSection
                    }
                }
                .padding(.bottom, 8)
            }
        }
        .background(Color.cgCard)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.cgBorder, lineWidth: 1)
        )
    }

    private var metaBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(program.meta.dates_active.uppercased())
                .font(.caption2)
                .tracking(1)
                .foregroundColor(.cgTextMuted)
            ForEach(program.meta.notes ?? [], id: \.self) { note in
                Text(note)
                    .font(.caption)
                    .foregroundColor(.cgTextMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func sectionView(_ section: SeasonalSection) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(section.title.uppercased())
                    .font(.system(.subheadline, design: .serif))
                    .fontWeight(.semibold)
                    .tracking(1)
                    .foregroundColor(.cgText)
                if !section.paired_wines.isEmpty {
                    Text(section.paired_wines.joined(separator: " · "))
                        .font(.caption)
                        .italic()
                        .foregroundColor(.cgTextMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.top, 10)
            .padding(.bottom, 4)

            ForEach(section.dishes) { dish in
                DishRow(dish: dish, onTap: { onTapDish(dish) })
                if dish.id != section.dishes.last?.id {
                    Divider().background(Color.cgBorder.opacity(0.3))
                        .padding(.leading, 70)
                }
            }
            Divider().background(Color.cgBorder.opacity(0.4))
        }
    }

    private var winesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("WINES")
                .font(.system(.subheadline, design: .serif))
                .fontWeight(.semibold)
                .tracking(1)
                .foregroundColor(.cgText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18)
                .padding(.top, 10)
                .padding(.bottom, 4)
            ForEach(filteredWines) { wine in
                wineRow(wine)
                if wine.id != filteredWines.last?.id {
                    Divider().background(Color.cgBorder.opacity(0.3))
                        .padding(.leading, 70)
                }
            }
        }
    }

    /// Bottle-style row matching the regular wine list — thumbnail + name +
    /// producer/region/varietal, tappable into the full wine detail.
    private func wineRow(_ wine: SeasonalWine) -> some View {
        Button { onTapWine(wine) } label: {
            HStack(spacing: 12) {
                WineThumbnail(urlString: wine.image_url, size: 56)
                VStack(alignment: .leading, spacing: 3) {
                    Text(wine.name)
                        .font(.system(.body, design: .serif))
                        .foregroundColor(.cgText)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                    if let sub = seasonalWineSubtitle(wine) {
                        Text(sub)
                            .font(.footnote)
                            .foregroundColor(.cgTextMuted)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundColor(.cgTextMuted)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

func seasonalWineSubtitle(_ wine: SeasonalWine) -> String? {
    let parts = [wine.producer, wine.region, wine.varietal]
        .compactMap { $0 }
        .filter { !$0.isEmpty }
    return parts.isEmpty ? nil : parts.joined(separator: " · ")
}

// MARK: - Seasonal wine detail

struct SeasonalWineDetailView: View {
    let wine: SeasonalWine

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ZStack {
                    Color.white
                    RemoteImage(urlString: wine.image_url)
                        .frame(maxHeight: 360)
                }
                .frame(height: 360)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.cgBorder, lineWidth: 1))

                Text(wine.name)
                    .font(.system(.title2, design: .serif))
                    .foregroundColor(.cgText)

                if let sub = seasonalWineSubtitle(wine) {
                    Text(sub)
                        .font(.system(.body, design: .serif))
                        .foregroundColor(.cgTextMuted)
                }

                if let desc = wine.description, !desc.isEmpty {
                    infoBlock(title: "About", body: desc)
                }
                if let notes = wine.tasting_notes, !notes.isEmpty {
                    infoBlock(title: "Tasting Notes", body: notes)
                }
                if let pairing = wine.suggested_pairing, !pairing.isEmpty {
                    infoBlock(title: "Suggested Pairing", body: pairing)
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 24)
        }
        .background(Color.cgBackground.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func infoBlock(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption.bold())
                .tracking(2)
                .foregroundColor(.cgAccent)
            Text(body)
                .font(.system(.body, design: .serif))
                .foregroundColor(.cgText)
                .textSelection(.enabled)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.cgCard)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.cgBorder, lineWidth: 1))
    }
}
