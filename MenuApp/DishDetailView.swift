import SwiftUI

struct DishDetailView: View {
    let dish: Dish
    @ObservedObject var store: BottleStore
    @Environment(\.closeDetail) private var closeDetail

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Hero image
                DishPhoto(dish.image) { img in
                    Image(uiImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .background(Color.cgBorder.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.cgBorder, lineWidth: 1))
                }

                // Full dish name — the nav-bar title truncates long names, so always
                // show the complete name here under the image.
                Text(dish.name)
                    .font(.system(.title2, design: .serif))
                    .foregroundColor(.cgText)
                    .fixedSize(horizontal: false, vertical: true)

                // Price / calories
                HStack(spacing: 10) {
                    if let price = dish.price {
                        Label("$\(price)", systemImage: "dollarsign.circle.fill")
                            .font(.headline)
                            .foregroundColor(.cgAccent)
                    }
                    if let cal = dish.calories {
                        Text("\(cal) cal")
                            .font(.subheadline)
                            .foregroundColor(.cgTextMuted)
                    }
                    Spacer()
                }

                // Menu name / serves / sizes meta
                VStack(alignment: .leading, spacing: 4) {
                    if let menuName = dish.menu_name, menuName != dish.name {
                        metaLine(label: "Menu name", value: menuName)
                    }
                    if let serves = dish.serves {
                        metaLine(label: "Serves", value: "\(serves)")
                    }
                    if let sizes = dish.sizes, !sizes.isEmpty {
                        let str = sizes.map { "\($0.key): \($0.value)" }.joined(separator: " / ")
                        metaLine(label: "Sizes", value: str)
                    }
                }

                // Description
                if let desc = dish.description, !desc.isEmpty {
                    Text(desc)
                        .font(.system(.body, design: .serif))
                        .italic()
                        .foregroundColor(.cgText)
                }

                // Notes (italicized warnings)
                if let notes = dish.notes {
                    ForEach(notes, id: \.self) { note in
                        Text(note)
                            .font(.subheadline)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(red: 1.0, green: 0.97, blue: 0.91))
                            .overlay(
                                Rectangle()
                                    .frame(width: 3)
                                    .foregroundColor(.cgAccent.opacity(0.7)),
                                alignment: .leading
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }

                // Talking points
                if let tp = dish.talking_points, !tp.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(tp, id: \.self) { point in
                            HStack(alignment: .top, spacing: 8) {
                                Text("•").foregroundColor(.cgAccent)
                                Text(point).font(.footnote)
                            }
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.cgAccent.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                }

                // Fields
                VStack(alignment: .leading, spacing: 12) {
                    // Composed ingredients (rub / crust / finishing / components), e.g. a
                    // steak rub listed as its own dish.
                    if let ing = dish.ingredients {
                        if let rub = ing.rub, !rub.isEmpty {
                            FieldListView(label: "Rub", items: rub)
                        }
                        if let crust = ing.crust, !crust.isEmpty {
                            FieldListView(label: "Crust", items: crust)
                        }
                        if let finishing = ing.finishing, !finishing.isEmpty {
                            FieldListView(label: "Finishing", items: finishing)
                        }
                        if let components = ing.components, !components.isEmpty {
                            FieldListView(label: "Components", items: components)
                        }
                        if let note = ing.note, !note.isEmpty {
                            FieldStringView(label: "Note", value: note)
                        }
                    }
                    if let sp = dish.serving_piece, !sp.isEmpty {
                        FieldStringView(label: "Serving Piece", value: sp)
                    }
                    if let portion = dish.portion, !portion.isEmpty {
                        FieldIngredientsView(label: "Portion", items: portion)
                    }
                    if let garnish = dish.garnish, !garnish.isEmpty {
                        FieldIngredientsView(label: "Garnish", items: garnish)
                    }
                    if let to = dish.to_bring, !to.isEmpty {
                        FieldListView(label: "To Bring", items: to)
                    }
                    if let q = dish.questions_to_ask, !q.isEmpty {
                        FieldListView(label: "Questions", items: q)
                    }
                    if let pt = dish.production_time, !pt.isEmpty {
                        FieldStringView(label: "Production", value: pt)
                    }
                    if let st = dish.station, !st.isEmpty {
                        FieldStringView(label: "Station", value: st)
                    }
                    if let tn = dish.tasting_notes, !tn.isEmpty {
                        FieldStringView(label: "Tasting Notes", value: tn)
                    }
                }

                // Variants
                if let variants = dish.variants, !variants.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("VARIANTS").font(.caption.bold()).foregroundColor(.cgTextMuted).tracking(1)
                        ForEach(Array(variants.keys.sorted()), id: \.self) { key in
                            HStack(alignment: .top, spacing: 6) {
                                Text("\(key):").font(.caption.bold()).foregroundColor(.cgText)
                                Text(variants[key] ?? "").font(.caption).foregroundColor(.cgText)
                            }
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.cgBackground)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.cgBorder, style: StrokeStyle(lineWidth: 1, dash: [3])))
                }

                winePairingsCard
            }
            .padding(16)
        }
        .background(Color.cgBackground.ignoresSafeArea())
        .navigationTitle(dish.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { CloseDetailButton(action: closeDetail) } }
    }

    /// Wine pairings for this dish: one block per wine STYLE that pairs, best tier
    /// first, each with the mechanism justification, the ★ standout bottle (when one
    /// earns it), and every bottle in the style. Closes with the "not listed & why".
    @ViewBuilder private var winePairingsCard: some View {
        let pairings = store.stylePairings(forDishName: dish.name)
        if !pairings.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("WINE PAIRINGS")
                    .font(.caption.bold())
                    .tracking(2)
                    .foregroundColor(.cgAccent)
                ForEach(pairings) { sp in
                    StylePairingBlock(pairing: sp, store: store)
                }
                if let lo = pairings.compactMap({ $0.leaves_out }).first(where: { !$0.isEmpty }) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("NOT LISTED")
                            .font(.caption2.bold()).tracking(1.5).foregroundColor(.cgTextMuted)
                        GlossaryText(lo, store: store, font: .footnote, color: .cgTextMuted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 2)
                }
            }
        }
    }

    @ViewBuilder
    func metaLine(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(label + ":").font(.caption).foregroundColor(.cgTextMuted)
            Text(value).font(.caption).foregroundColor(.cgText)
        }
    }
}

/// One wine-style pairing on a dish's detail: the style name + tier, the mechanism
/// justification, then every bottle in the style (the ★ standout, if any, pinned first
/// with its specific reason). Tapping a bottle pushes its full detail.
struct StylePairingBlock: View {
    let pairing: StylePairing
    @ObservedObject var store: BottleStore

    var body: some View {
        let wines = store.wines(inStyle: pairing.style, standoutId: pairing.standout_wine_id)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(pairing.style)
                    .font(.system(.callout, design: .serif).weight(.semibold))
                    .foregroundColor(.cgText)
                Spacer(minLength: 8)
                TierPill(tier: pairing.tier)
            }
            GlossaryText(pairing.justification, store: store, font: .footnote, color: .cgTextMuted)
            VStack(spacing: 0) {
                ForEach(wines) { w in
                    let isS = w.id == pairing.standout_wine_id
                    NavigationLink(destination: WineDetailView(wine: w, store: store)) {
                        PairingItemRow(title: w.displayName,
                                       isStandout: isS,
                                       reason: isS ? pairing.standout_reason : nil,
                                       store: store)
                    }
                    .buttonStyle(.plain)
                    if w.id != wines.last?.id {
                        Divider().background(Color.cgBorder.opacity(0.25))
                    }
                }
            }
            .padding(.top, 2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.cgCard)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8)
            .stroke(pairing.tier == "Perfect" ? Color.cgAccent.opacity(0.5) : Color.cgBorder, lineWidth: 1))
    }
}

// MARK: - Field views

struct FieldStringView: View {
    let label: String
    let value: String
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label.uppercased())
                .font(.caption2.bold())
                .tracking(1)
                .foregroundColor(.cgTextMuted)
                .frame(width: 92, alignment: .leading)
            Text(value)
                .font(.callout)
                .foregroundColor(.cgText)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct FieldListView: View {
    let label: String
    let items: [String]
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label.uppercased())
                .font(.caption2.bold())
                .tracking(1)
                .foregroundColor(.cgTextMuted)
                .frame(width: 92, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                ForEach(items, id: \.self) { item in
                    Text(item).font(.callout).foregroundColor(.cgText)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct FieldIngredientsView: View {
    let label: String
    let items: [Ingredient]
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label.uppercased())
                .font(.caption2.bold())
                .tracking(1)
                .foregroundColor(.cgTextMuted)
                .frame(width: 92, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(item.ingredient ?? "")
                            .font(.callout)
                            .foregroundColor(.cgText)
                        if let amount = item.amount {
                            Text("— ").foregroundColor(.cgTextMuted) +
                            Text(amount).font(.callout).foregroundColor(.cgAccent).fontWeight(.medium)
                        }
                        if let prep = item.prep {
                            Text(prep)
                                .font(.caption2)
                                .italic()
                                .foregroundColor(.cgTextMuted)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
