import SwiftUI

/// The order list on the phone: the same open orders the watch takes (`OrderStore`), newest first. The
/// check on a row marks it done; pull to refresh.
struct OrdersListView: View {
    @ObservedObject var store: OrderStore
    @State private var confirmClear = false

    var body: some View {
        Group {
            if store.orders.isEmpty {
                Text("—")
                    .font(.title3)
                    .foregroundColor(.cgTextMuted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(store.orders) { order in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(order.qty > 1 ? "\(order.qty)× \(order.name)" : order.name)
                                    .font(.system(.body, design: .serif))
                                    .foregroundColor(order.standardized ? .cgText : .cgTextMuted)
                                if let note = order.note, !note.isEmpty {
                                    Text(note)
                                        .font(.footnote)
                                        .foregroundColor(.cgTextMuted)
                                }
                            }
                            Spacer()
                            Button { Task { await store.done(order.id) } } label: {
                                Image(systemName: "checkmark.circle")
                                    .font(.title2)
                                    .foregroundColor(.cgAccent)
                            }
                            .buttonStyle(.plain)
                        }
                        .listRowBackground(Color.cgCard)
                    }
                    Button(role: .destructive) { confirmClear = true } label: {
                        Text("Clear all")
                            .font(.callout)
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity)
                    }
                    .listRowBackground(Color.clear)
                }
                .scrollContentBackground(.hidden)
            }
        }
        .background(Color.cgBackground)
        .refreshable { await store.refresh() }
        .task { await store.refresh() }
        .confirmationDialog("Clear all", isPresented: $confirmClear, titleVisibility: .hidden) {
            Button("Clear all", role: .destructive) { Task { await store.clearAll() } }
            Button("Cancel", role: .cancel) {}
        }
    }
}
