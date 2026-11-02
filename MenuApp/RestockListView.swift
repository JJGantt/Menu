import SwiftUI

struct RestockListView: View {
    @ObservedObject var restockStore: RestockStore
    @ObservedObject var bottleStore: BottleStore
    @State private var confirmClear = false

    /// Restock items grouped by the backup-location area of their catalog bottle.
    /// Items with no matching bottle or no backup area fall into "Other".
    private var groups: [(area: String, items: [RestockItem])] {
        var buckets: [String: [RestockItem]] = [:]
        for item in restockStore.items {
            let area = bottleStore.bottles[item.product_id]?.backup_area ?? "Other"
            buckets[area, default: []].append(item)
        }
        // Sort area names alphabetically, "Other" always last.
        let sortedAreas = buckets.keys.sorted { a, b in
            if a == "Other" { return false }
            if b == "Other" { return true }
            return a < b
        }
        return sortedAreas.map { ($0, buckets[$0]!.sorted { ($0.name ?? $0.product_id) < ($1.name ?? $1.product_id) }) }
    }

    var body: some View {
        Group {
            if restockStore.items.isEmpty {
                Text("—")
                    .font(.title3)
                    .foregroundColor(.cgTextMuted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(groups, id: \.area) { group in
                            Text(group.area.uppercased())
                                .font(.system(.subheadline, design: .serif))
                                .tracking(2)
                                .foregroundColor(.cgAccent)
                                .padding(.horizontal, 14)
                                .padding(.top, 18)
                                .padding(.bottom, 6)

                            ForEach(group.items) { item in
                                RestockRow(item: item, bottleStore: bottleStore,
                                    onChangeQty: { newQty in
                                        Task {
                                            try? await restockStore.apply([[
                                                "product_id": item.product_id,
                                                "product_kind": item.product_kind,
                                                "quantity": newQty
                                            ]])
                                        }
                                    },
                                    onRemove: {
                                        Task { try? await restockStore.remove(item.product_id) }
                                    })
                                if item.id != group.items.last?.id {
                                    Divider().background(Color.cgBorder.opacity(0.3))
                                        .padding(.leading, 76)
                                }
                            }
                        }

                        Button(role: .destructive) {
                            confirmClear = true
                        } label: {
                            Text("Clear all")
                                .font(.callout)
                                .foregroundColor(.red)
                                .padding(.vertical, 14)
                                .frame(maxWidth: .infinity)
                        }
                        .padding(.top, 8)
                    }
                }
                .scrollDismissesKeyboard(.immediately)
            }
        }
        .background(Color.cgBackground)
        .task { await restockStore.refresh() }
        .confirmationDialog("Clear the entire list?",
                            isPresented: $confirmClear,
                            titleVisibility: .visible) {
            Button("Clear all", role: .destructive) {
                Task { try? await restockStore.clearAll() }
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

private struct RestockRow: View {
    let item: RestockItem
    @ObservedObject var bottleStore: BottleStore
    let onChangeQty: (Int) -> Void
    let onRemove: () -> Void

    private var wine: Bottle? { bottleStore.bottles[item.product_id] }

    var body: some View {
        HStack(spacing: 12) {
            if let wine {
                WineThumbnail(urlString: wine.image_url, size: 56)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(wine?.displayName ?? item.name ?? item.product_id)
                    .font(.system(.body, design: .serif))
                    .foregroundColor(.cgText)
                    .lineLimit(2)
                if let wine {
                    Text(wine.primary.displayString ?? "—")
                        .font(.footnote)
                        .foregroundColor(.cgTextMuted)
                    Text(wine.backup.displayString ?? "—")
                        .font(.footnote)
                        .foregroundColor(.cgTextMuted)
                }
            }
            Spacer()
            HStack(spacing: 8) {
                Button(action: { onChangeQty(item.quantity - 1) }) {
                    Image(systemName: "minus.circle.fill")
                        .font(.title3)
                        .foregroundColor(.cgTextMuted)
                }
                .buttonStyle(.plain)

                Text("\(item.quantity)")
                    .font(.system(.title3, design: .serif))
                    .foregroundColor(.cgAccent)
                    .frame(minWidth: 22)

                Button(action: { onChangeQty(item.quantity + 1) }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundColor(.cgAccent)
                }
                .buttonStyle(.plain)
            }
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.footnote)
                    .foregroundColor(.cgTextMuted.opacity(0.6))
                    .padding(.leading, 4)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
    }
}
