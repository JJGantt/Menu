import SwiftUI

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
