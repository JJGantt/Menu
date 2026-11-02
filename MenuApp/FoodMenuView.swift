import SwiftUI

// MARK: - Food tab

/// The Food tab: every menu group, then the seasonal program cards, filtered
/// by the search text.
struct FoodMenuView: View {
    let menu: MenuData?
    let searchText: String
    let onTapDish: (Dish) -> Void
    let onTapSeasonalWine: (SeasonalWine) -> Void

    var body: some View {
        ScrollView { content }
            .scrollDismissesKeyboard(.immediately)
    }

    private var content: some View {
        LazyVStack(alignment: .leading, spacing: 12) {
            if let menu {
                ForEach(menu.groups) { group in
                    let dishes = filteredDishes(menu.dishes(in: group))
                    if !dishes.isEmpty {
                        MenuGroupView(
                            title: group.title,
                            dishes: dishes,
                            sectionOrder: group.sections,
                            defaultExpanded: group.id == menu.groups.first?.id || !searchText.isEmpty,
                            forceExpandSections: !searchText.isEmpty,
                            onTapDish: onTapDish
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
                        onTapDish: onTapDish,
                        onTapWine: onTapSeasonalWine
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

    private func filteredDishes(_ dishes: [Dish]) -> [Dish] {
        let q = searchText.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return dishes }
        return dishes.filter { dishMatches($0, query: q) }
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
