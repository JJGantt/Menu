import SwiftUI

struct WineListView: View {
    @ObservedObject var store: BottleStore
    let searchText: String
    let onTapWine: (Bottle) -> Void

    @State private var selectedViewId: String?

    /// The currently selected backend-defined view (falls back to the default, then first).
    private var currentView: BottleSectionView {
        let views = store.views(for: "wine")
        return views.first(where: { $0.id == selectedViewId })
            ?? views.first(where: { $0.is_default })
            ?? views[0]
    }

    var body: some View {
        ScrollView {
            content
        }
        .scrollDismissesKeyboard(.immediately)
        .onAppear {
            if selectedViewId == nil {
                selectedViewId = (store.views(for: "wine").first(where: { $0.is_default })
                                  ?? store.views(for: "wine").first)?.id
            }
        }
    }

    private var content: some View {
        LazyVStack(alignment: .leading, spacing: 12) {
            if store.bottles.isEmpty {
                if let err = store.loadError {
                    Text(err).foregroundColor(.red).padding()
                } else {
                    ProgressView().padding(40)
                }
            } else {
                viewPicker
                ForEach(filteredCategories()) { cat in
                    WineCategorySection(
                        category: cat,
                        description: store.description(dimension: currentView.group_by, value: cat.name, section: "wine"),
                        forceExpand: !searchText.trimmingCharacters(in: .whitespaces).isEmpty,
                        onTapWine: onTapWine)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }

    /// View-mode toggle, only shown when the backend defines more than one wine view.
    @ViewBuilder private var viewPicker: some View {
        let views = store.views(for: "wine")
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

    private func filteredCategories() -> [BottleCategory] {
        let groups = store.groups(for: currentView)
        let q = searchText.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return groups }
        return groups.compactMap { cat in
            let matched = cat.bottles.filter { bottleMatches($0, query: q) }
            return matched.isEmpty ? nil : BottleCategory(name: cat.name, bottles: matched)
        }
    }
}

private struct WineCategorySection: View {
    let category: BottleCategory
    var description: String? = nil
    /// Forces the group open regardless of the user's toggle — used during search so
    /// matching bottles stay visible even though groups are collapsed by default.
    var forceExpand: Bool = false
    let onTapWine: (Bottle) -> Void
    @State private var expanded = false

    private var isOpen: Bool { expanded || forceExpand }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: { withAnimation { expanded.toggle() } }) {
                HStack {
                    Image(systemName: isOpen ? "chevron.down" : "chevron.right")
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

            if isOpen {
                VStack(alignment: .leading, spacing: 0) {
                    Divider().background(Color.cgBorder.opacity(0.6))
                    if let description, !description.isEmpty {
                        Text(description)
                            .font(.footnote)
                            .foregroundColor(.cgTextMuted)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                    }
                    ForEach(category.bottles) { wine in
                        WineRowView(wine: wine, onTap: { onTapWine(wine) })
                        if wine.id != category.bottles.last?.id {
                            Divider().background(Color.cgBorder.opacity(0.3))
                                .padding(.leading, 70)
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

private struct WineRowView: View {
    let wine: Bottle
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                WineThumbnail(urlString: wine.image_url, size: 56)
                VStack(alignment: .leading, spacing: 3) {
                    Text(wine.displayName)
                        .font(.system(.body, design: .serif))
                        .foregroundColor(.cgText)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                    Text(wine.primary.displayString ?? "—")
                        .font(.footnote)
                        .foregroundColor(.cgTextMuted)
                    if let s = wine.backup.displayString {
                        Text(s)
                            .font(.footnote)
                            .foregroundColor(.cgTextMuted.opacity(0.75))
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

struct WineThumbnail: View {
    let urlString: String?
    let size: CGFloat

    var body: some View {
        RemoteImage(urlString: urlString)
            .frame(width: size, height: size)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.cgBorder.opacity(0.6), lineWidth: 1))
    }
}
