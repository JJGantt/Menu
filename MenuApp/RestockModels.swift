import Foundation
import SwiftUI

struct RestockItem: Codable, Identifiable, Hashable {
    let product_id: String
    let product_kind: String
    let quantity: Int
    let name: String?
    let added_at: String?

    var id: String { product_id }
}

@MainActor
final class RestockStore: ObservableObject {
    @Published var items: [RestockItem] = []
    @Published var loadError: String?
    /// The first fetch has landed: before it, an empty `items` means "not known yet", not an empty list.
    @Published private(set) var loaded = false

    func refresh() async {
        do {
            let rows: [RestockItem] = try await SupabaseClient.shared.get(path: "restock_items?select=*&order=added_at.asc")
            self.items = rows
            self.loadError = nil
            self.loaded = true
        } catch is CancellationError {
            // View was torn down mid-fetch (tab switch, etc.) — not a real error.
            return
        } catch {
            let ns = error as NSError
            if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled { return }
            self.loadError = "Restock fetch failed: \(error.localizedDescription)"
        }
    }

    /// Upsert items; quantity == 0 deletes the row.
    /// Optimistic: mutates local state synchronously, then writes to Supabase async.
    /// On failure, refreshes from Supabase to restore truth.
    func apply(_ updates: [[String: Any]]) async throws {
        // Synchronous local mutation — SwiftUI picks this up immediately.
        for u in updates {
            guard let pid = u["product_id"] as? String,
                  let qty = u["quantity"] as? Int else { continue }
            if qty <= 0 {
                items.removeAll { $0.product_id == pid }
            } else if let idx = items.firstIndex(where: { $0.product_id == pid }) {
                let existing = items[idx]
                items[idx] = RestockItem(
                    product_id: existing.product_id,
                    product_kind: existing.product_kind,
                    quantity: qty,
                    name: (u["name"] as? String) ?? existing.name,
                    added_at: existing.added_at
                )
            } else {
                items.append(RestockItem(
                    product_id: pid,
                    product_kind: (u["product_kind"] as? String) ?? "liquor",
                    quantity: qty,
                    name: u["name"] as? String,
                    added_at: nil
                ))
            }
        }

        // Background network writes.
        do {
            for u in updates {
                guard let pid = u["product_id"] as? String,
                      let qty = u["quantity"] as? Int else { continue }
                if qty <= 0 {
                    try await SupabaseClient.shared.delete(path: "restock_items?product_id=eq.\(pid)")
                } else {
                    let kind = (u["product_kind"] as? String) ?? "liquor"
                    var row: [String: Any] = ["product_id": pid, "product_kind": kind, "quantity": qty]
                    if let name = u["name"] as? String, !name.isEmpty {
                        row["name"] = name
                    }
                    try await SupabaseClient.shared.upsert(
                        path: "restock_items",
                        body: [row],
                        onConflict: "product_id"
                    )
                }
            }
        } catch {
            // Network failed — re-sync to truth so the UI stops lying.
            await refresh()
            throw error
        }
    }

    func remove(_ productId: String) async throws {
        items.removeAll { $0.product_id == productId }
        do {
            try await SupabaseClient.shared.delete(path: "restock_items?product_id=eq.\(productId)")
        } catch {
            await refresh()
            throw error
        }
    }

    func clearAll() async throws {
        items.removeAll()
        do {
            try await SupabaseClient.shared.delete(path: "restock_items?product_id=neq.__none__")
        } catch {
            await refresh()
            throw error
        }
    }
}
