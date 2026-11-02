import SwiftUI

struct LiquorListView: View {
    @ObservedObject var bottleStore: BottleStore
    @Binding var expanded: Set<String>
    var searchText: String = ""
    let onTapBottle: (Bottle) -> Void

    @State private var selectedViewId: String?

    /// The default "Type" view renders a nested type → style → bottle tree (Whiskey →
    /// Bourbon, Rye…). Every other view (Producer, Company, Location) stays a flat list.
    private var isTypeView: Bool { currentView.group_by == "varietal" }

    /// Flat groups for non-Type views, filtered to bottles matching the search.
    private func filteredGroups() -> [BottleCategory] {
        let cats = bottleStore.groups(for: currentView)
        let q = searchText.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return cats }
        return cats.compactMap { cat in
            let matched = cat.bottles.filter { bottleMatches($0, query: q) }
            return matched.isEmpty ? nil : BottleCategory(name: cat.name, bottles: matched)
        }
    }

    /// Nested type groups for the Type view, filtered to bottles matching the search.
    /// Styles with no match drop out, then types with no surviving styles drop out.
    private func filteredTypeGroups() -> [BottleTypeGroup] {
        let groups = bottleStore.liquorTypeGroups()
        let q = searchText.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return groups }
        return groups.compactMap { g in
            let styles = g.styles.compactMap { cat -> BottleCategory? in
                let matched = cat.bottles.filter { bottleMatches($0, query: q) }
                return matched.isEmpty ? nil : BottleCategory(name: cat.name, bottles: matched)
            }
            return styles.isEmpty ? nil : BottleTypeGroup(name: g.name, nested: g.nested, styles: styles)
        }
    }

    private var currentView: BottleSectionView {
        let views = bottleStore.views(for: "liquor")
        return views.first(where: { $0.id == selectedViewId })
            ?? views.first(where: { $0.is_default })
            ?? views[0]
    }

    var body: some View {
        Group {
            let searching = !searchText.trimmingCharacters(in: .whitespaces).isEmpty
            let isEmpty = isTypeView ? filteredTypeGroups().isEmpty : filteredGroups().isEmpty
            if isEmpty {
                Text(searching ? "No liquor matches." : "—")
                    .font(.title3)
                    .foregroundColor(.cgTextMuted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        viewPicker
                        if isTypeView {
                            ForEach(filteredTypeGroups()) { group in
                                LiquorTypeSection(
                                    bottleStore: bottleStore,
                                    group: group,
                                    expanded: $expanded,
                                    searching: searching,
                                    onTap: onTapBottle
                                )
                            }
                        } else {
                            ForEach(filteredGroups()) { cat in
                                LiquorCategorySection(
                                    category: cat,
                                    description: bottleStore.description(dimension: currentView.group_by, value: cat.name, section: "liquor"),
                                    isExpanded: expanded.contains(cat.name) || searching,
                                    onToggle: { toggle(cat.name) },
                                    onTap: onTapBottle
                                )
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                }
            }
        }
        .background(Color.cgBackground)
        .onAppear {
            if selectedViewId == nil {
                selectedViewId = (bottleStore.views(for: "liquor").first(where: { $0.is_default })
                                  ?? bottleStore.views(for: "liquor").first)?.id
            }
        }
    }

    private func toggle(_ key: String) {
        withAnimation {
            if expanded.contains(key) { expanded.remove(key) } else { expanded.insert(key) }
        }
    }

    /// View-mode toggle, only shown when the backend defines more than one liquor view.
    @ViewBuilder private var viewPicker: some View {
        let views = bottleStore.views(for: "liquor")
        if views.count > 1 {
            Picker("View", selection: Binding(
                get: { currentView.id },
                set: { selectedViewId = $0 }
            )) {
                ForEach(views) { v in
                    Text(v.label).tag(v.id)
                }
            }
            .pickerStyle(.segmented)
            .padding(.top, 4)
        }
    }
}

/// Top-level spirit-type card in the Type view. For a multi-style type (Whiskey, Brandy)
/// it shows the type's umbrella description and a nested, collapsible style level below.
/// For a single-style type (Vodka, Tequila…) it opens straight to bottles.
private struct LiquorTypeSection: View {
    @ObservedObject var bottleStore: BottleStore
    let group: BottleTypeGroup
    @Binding var expanded: Set<String>
    let searching: Bool
    let onTap: (Bottle) -> Void

    private var typeKey: String { "type:\(group.name)" }
    private var isExpanded: Bool { expanded.contains(typeKey) || searching }

    /// Umbrella blurb for the type — a dedicated "type" row (e.g. Whiskey) if one exists,
    /// otherwise the varietal blurb of the same name (Brandy, Vodka, Tequila… reuse theirs).
    private var typeDescription: String? {
        bottleStore.description(dimension: "type", value: group.name, section: "liquor")
            ?? bottleStore.description(dimension: "varietal", value: group.name, section: "liquor")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: { toggle(typeKey) }) {
                HStack {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundColor(.cgAccent.opacity(0.7))
                    Text(group.name.uppercased())
                        .font(.system(.title3, design: .serif))
                        .tracking(3)
                        .foregroundColor(.cgAccent)
                    Spacer()
                    Text("\(group.allBottles.count)")
                        .font(.caption)
                        .foregroundColor(.cgTextMuted)
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    Divider().background(Color.cgBorder.opacity(0.6))
                    if let description = typeDescription, !description.isEmpty {
                        Text(description)
                            .font(.footnote)
                            .foregroundColor(.cgTextMuted)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                    }
                    if group.nested {
                        ForEach(group.styles) { style in
                            LiquorStyleSection(
                                bottleStore: bottleStore,
                                typeName: group.name,
                                style: style,
                                expanded: $expanded,
                                searching: searching,
                                onTap: onTap
                            )
                        }
                    } else {
                        let bottles = group.styles.first?.bottles ?? []
                        ForEach(bottles) { row in
                            LiquorRowView(row: row, onTap: { onTap(row) })
                            if row.id != bottles.last?.id {
                                Divider().background(Color.cgBorder.opacity(0.3))
                                    .padding(.leading, 18)
                            }
                        }
                    }
                }
                .padding(.bottom, 8)
            }
        }
        .background(Color.cgCard)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.cgBorder, lineWidth: 1))
    }

    private func toggle(_ key: String) {
        withAnimation {
            if expanded.contains(key) { expanded.remove(key) } else { expanded.insert(key) }
        }
    }
}

/// The nested second level inside a multi-style type — one collapsible style (Bourbon,
/// Scotch, Cognac…) with its own varietal blurb and bottles. Lighter/indented vs. the type.
private struct LiquorStyleSection: View {
    @ObservedObject var bottleStore: BottleStore
    let typeName: String
    let style: BottleCategory
    @Binding var expanded: Set<String>
    let searching: Bool
    let onTap: (Bottle) -> Void

    private var styleKey: String { "style:\(typeName)|\(style.name)" }
    private var isExpanded: Bool { expanded.contains(styleKey) || searching }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: { toggle() }) {
                HStack(spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .foregroundColor(.cgAccent.opacity(0.6))
                    Text(style.name.uppercased())
                        .font(.system(.subheadline, design: .serif))
                        .tracking(2)
                        .foregroundColor(.cgAccent.opacity(0.85))
                    Spacer()
                    Text("\(style.bottles.count)")
                        .font(.caption2)
                        .foregroundColor(.cgTextMuted)
                }
                .padding(.vertical, 11)
                .padding(.leading, 22)
                .padding(.trailing, 16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                if let description = bottleStore.description(dimension: "varietal", value: style.name, section: "liquor"),
                   !description.isEmpty {
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.cgTextMuted)
                        .padding(.leading, 22)
                        .padding(.trailing, 16)
                        .padding(.bottom, 8)
                }
                ForEach(style.bottles) { row in
                    LiquorRowView(row: row, onTap: { onTap(row) })
                    if row.id != style.bottles.last?.id {
                        Divider().background(Color.cgBorder.opacity(0.3))
                            .padding(.leading, 18)
                    }
                }
            }
            Divider().background(Color.cgBorder.opacity(0.25))
        }
        .background(Color.cgCard)
    }

    private func toggle() {
        withAnimation {
            if expanded.contains(styleKey) { expanded.remove(styleKey) } else { expanded.insert(styleKey) }
        }
    }
}

private struct LiquorCategorySection: View {
    let category: BottleCategory
    var description: String? = nil
    let isExpanded: Bool
    let onToggle: () -> Void
    let onTap: (Bottle) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onToggle) {
                HStack {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundColor(.cgAccent.opacity(0.7))
                    Text(category.name.uppercased())
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
                    if let description, !description.isEmpty {
                        Text(description)
                            .font(.footnote)
                            .foregroundColor(.cgTextMuted)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                    }
                    ForEach(category.bottles) { row in
                        LiquorRowView(row: row, onTap: { onTap(row) })
                        if row.id != category.bottles.last?.id {
                            Divider().background(Color.cgBorder.opacity(0.3))
                                .padding(.leading, 18)
                        }
                    }
                }
                .padding(.bottom, 8)
            }
        }
        .background(Color.cgCard)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.cgBorder, lineWidth: 1))
    }
}

private struct LiquorRowView: View {
    let row: Bottle
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                WineThumbnail(urlString: row.image_url, size: 56)
                VStack(alignment: .leading, spacing: 3) {
                    Text(row.displayName)
                        .font(.system(.body, design: .serif))
                        .foregroundColor(.cgText)
                        .lineLimit(2)
                    Text(row.primary.displayString ?? "—")
                        .font(.footnote)
                        .foregroundColor(.cgTextMuted)
                    if let s = row.backup.displayString {
                        Text(s)
                            .font(.footnote)
                            .foregroundColor(.cgTextMuted.opacity(0.75))
                    }
                }
                Spacer()
                if let price = row.price {
                    Text("$\(price, specifier: price.truncatingRemainder(dividingBy: 1) == 0 ? "%.0f" : "%.1f")")
                        .font(.system(.subheadline, design: .serif))
                        .foregroundColor(.cgAccent)
                }
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundColor(.cgTextMuted)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
