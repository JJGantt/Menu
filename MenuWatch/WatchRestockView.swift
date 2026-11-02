import SwiftUI
import WatchKit

struct WatchRestockView: View {
    @EnvironmentObject private var store: RestockStore
    @EnvironmentObject private var bottleStore: BottleStore
    @State private var armedID: String?
    /// The clear-all button has been pressed once and is waiting for the confirming press.
    @State private var clearArmed = false

    /// Where the first row sits, in points from the top of the glass: low enough that a full-width
    /// line clears the 46mm display's rounded corner (StatusHub's watch measured the same, `Landing`).
    private static let top: CGFloat = 32

    var body: some View {
        Group {
            if !store.loaded && store.loadError == nil {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if store.items.isEmpty && store.loadError == nil {
                Text("Restock list empty")
                    .foregroundColor(.gray)
                    .font(.system(size: 12))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = store.loadError {
                Text(err)
                    .foregroundColor(.red)
                    .font(.system(size: 11))
                    .padding(8)
            } else {
                // A plain stack rather than a List: a watch List pads every row to a tall minimum,
                // which spread a short list over several screens.
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(store.items) { item in
                            rowButton(for: item)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(armedID == item.product_id ? Color.red.opacity(0.35) : Color.clear)
                                )
                        }
                        clearAllButton
                            .padding(.top, 10)
                    }
                    .padding(.top, Self.top)
                    .padding(.horizontal, 4)
                    .padding(.bottom, 12)
                }
                .scrollIndicators(.never)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .ignoresSafeArea(edges: .top)
        // Names and backup spots come from the catalog the chat page loads; this page fetches only
        // the list, each time it is turned to.
        .onAppear { Task { await store.refresh() } }
    }

    @ViewBuilder
    private func rowButton(for item: RestockItem) -> some View {
        Button(action: { handleTap(on: item) }) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(displayName(for: item))
                        .font(.system(size: 13))
                        .foregroundColor(.white)
                    if let backup = backupLocation(for: item) {
                        Text(backup)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                if armedID == item.product_id {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.white)
                } else {
                    Text("×\(item.quantity)")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    /// Empties the whole list: the first press arms it (red), the second clears. Left unconfirmed it
    /// disarms after 3s, the same as a row's delete.
    private var clearAllButton: some View {
        Button {
            if clearArmed {
                clearArmed = false
                WKInterfaceDevice.current().play(.click)
                Task { try? await store.clearAll() }
            } else {
                clearArmed = true
                Task {
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    clearArmed = false
                }
            }
        } label: {
            Text(clearArmed ? "Confirm" : "Clear all")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(clearArmed ? VoiceBorder.red : .white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func handleTap(on item: RestockItem) {
        if armedID == item.product_id {
            // Confirmed — remove.
            let id = item.product_id
            armedID = nil
            Task {
                try? await store.remove(id)
            }
        } else {
            // Arm this row; auto-disarm after 3s if not confirmed.
            armedID = item.product_id
            let armed = item.product_id
            Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                if armedID == armed { armedID = nil }
            }
        }
    }

    private func displayName(for item: RestockItem) -> String {
        if let b = bottleStore.bottles[item.product_id] { return b.displayName }
        if let n = item.name, !n.isEmpty { return n }
        return item.product_id
    }

    private func backupLocation(for item: RestockItem) -> String? {
        guard let b = bottleStore.bottles[item.product_id] else { return nil }
        return b.backup.displayString
    }
}
