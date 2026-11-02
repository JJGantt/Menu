import SwiftUI

struct WineDetailView: View {
    let wine: Bottle
    @ObservedObject var store: BottleStore
    @Environment(\.closeDetail) private var closeDetail

    /// Always read the freshest copy from the store so locations updated by the AI
    /// reflect immediately without re-presenting the view.
    private var current: Bottle { store.bottles[wine.id] ?? wine }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ZStack {
                    Color.white
                    RemoteImage(urlString: current.image_url)
                        .frame(maxHeight: 360)
                }
                .frame(height: 360)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.cgBorder, lineWidth: 1))

                HStack(alignment: .firstTextBaseline) {
                    Text(current.displayName)
                        .font(.system(.title2, design: .serif))
                        .foregroundColor(.cgText)
                    Spacer()
                    if let price = current.price {
                        VStack(alignment: .trailing, spacing: 1) {
                            Text("$\(price, specifier: price.truncatingRemainder(dividingBy: 1) == 0 ? "%.0f" : "%.1f")")
                                .font(.system(.title3, design: .serif).weight(.semibold))
                                .foregroundColor(.cgAccent)
                            if let bottlePrice = current.bottle_price {
                                Text("$\(bottlePrice, specifier: bottlePrice.truncatingRemainder(dividingBy: 1) == 0 ? "%.0f" : "%.1f") btl")
                                    .font(.caption)
                                    .foregroundColor(.cgTextMuted)
                            }
                        }
                    }
                }

                attributesCard

                LocationCard(title: "Primary", location: current.primary)
                LocationCard(title: "Backup",  location: current.backup)

                if let gd = current.grape_detail, !gd.isEmpty {
                    infoBlock(title: "Grapes", body: gd)
                }
                if let notes = current.tasting_notes, !notes.isEmpty {
                    infoBlock(title: current.kind == "wine" ? "Flavor" : "Tasting Notes", body: notes)
                }
                if let tp = current.talking_points, !tp.isEmpty {
                    infoBlock(title: "Talking Points", body: tp)
                }
                foodPairingsCard
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 24)
        }
        .background(Color.cgBackground.ignoresSafeArea())
        .toolbar { ToolbarItem(placement: .topBarTrailing) { CloseDetailButton(action: closeDetail) } }
    }

    /// Surfaces every backend-defined view's value for this bottle (Type / Producer /
    /// Company / Location …) plus ABV — so you see all its attributes no matter which
    /// view you tapped in from. Driven by the same `section_views`, so new views appear
    /// here automatically.
    @ViewBuilder private var attributesCard: some View {
        let section = current.kind ?? "wine"
        let views = store.views(for: section)
        VStack(alignment: .leading, spacing: 10) {
            ForEach(views) { v in
                if let val = store.viewValue(current, for: v), !val.isEmpty {
                    NavigationLink(destination: GroupScreen(store: store, section: section,
                                                            dimension: v.group_by, value: val)) {
                        attrRow(label: v.label, value: val, tappable: true)
                    }
                    .buttonStyle(.plain)
                }
            }
            if let abv = current.abv, !abv.isEmpty {
                attrRow(label: "ABV", value: abv, tappable: false)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.cgCard)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.cgBorder, lineWidth: 1))
    }

    @ViewBuilder private func attrRow(label: String, value: String, tappable: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label.uppercased())
                .font(.caption2.bold())
                .tracking(1.5)
                .foregroundColor(.cgTextMuted)
                .frame(width: 88, alignment: .leading)
            Text(value)
                .font(.system(.callout, design: .serif))
                .foregroundColor(.cgText)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
            if tappable {
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundColor(.cgAccent.opacity(0.6))
            }
        }
    }

    @ViewBuilder
    private func infoBlock(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption.bold())
                .tracking(2)
                .foregroundColor(.cgAccent)
            GlossaryText(body, store: store)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.cgCard)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.cgBorder, lineWidth: 1))
    }

    /// The dishes this wine pairs with, grouped by the tier its style earned, best
    /// tier first. Dishes this exact bottle is the standout for get a ★ and the reason.
    /// Hidden for liquors and wines without a pairing style.
    @ViewBuilder private var foodPairingsCard: some View {
        let pairings = store.dishPairings(forWine: current)
        if !pairings.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("FOOD PAIRINGS")
                    .font(.caption.bold())
                    .tracking(2)
                    .foregroundColor(.cgAccent)
                ForEach(["Perfect", "Great", "Good"], id: \.self) { tier in
                    let group = pairings.filter { $0.tier == tier }
                    if !group.isEmpty {
                        TierPill(tier: tier)
                        ForEach(group) { wd in
                            NavigationLink(destination: DishDetailView(dish: wd.dish, store: store)) {
                                PairingItemRow(title: wd.dish.name,
                                               isStandout: wd.isStandout,
                                               reason: wd.standoutReason,
                                               store: store)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.cgCard)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.cgBorder, lineWidth: 1))
        }
    }
}

/// The color for a pairing strength tier — Perfect is the boldest.
func pairingTierColor(_ tier: String) -> Color {
    switch tier {
    case "Perfect": return .cgAccent
    case "Great":   return Color(red: 0.55, green: 0.42, blue: 0.20)
    default:        return .cgTextMuted          // Good
    }
}

/// A small tier label pill (Perfect / Great / Good).
struct TierPill: View {
    let tier: String
    var body: some View {
        Text(tier.uppercased())
            .font(.caption2.bold())
            .tracking(1)
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(pairingTierColor(tier))
            .clipShape(Capsule())
    }
}

/// One tappable name row (a dish on the wine side, a bottle on the dish side), with an
/// optional ★ standout flag + its specific reason.
struct PairingItemRow: View {
    let title: String
    var subtitle: String? = nil
    var isStandout: Bool = false
    var reason: String? = nil
    var store: BottleStore? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if isStandout {
                Image(systemName: "star.fill").font(.caption2).foregroundColor(.cgAccent).padding(.top, 3)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.callout, design: .serif))
                    .foregroundColor(.cgText)
                    .multilineTextAlignment(.leading)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle).font(.caption).foregroundColor(.cgTextMuted)
                }
                if isStandout, let reason, !reason.isEmpty {
                    if let store {
                        GlossaryText(reason, store: store, font: .footnote, color: .cgTextMuted)
                    } else {
                        Text(reason)
                            .font(.footnote)
                            .foregroundColor(.cgTextMuted)
                            .multilineTextAlignment(.leading)
                    }
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption2).foregroundColor(.cgAccent.opacity(0.6)).padding(.top, 3)
        }
        .padding(.vertical, 7)
        .padding(.leading, isStandout ? 0 : 2)
        .contentShape(Rectangle())
    }
}

/// Pushed when you tap a value (Type/Producer/Company/Location) on a bottle's detail.
/// Shows that group's learner description, then every bottle in the group — each of
/// which pushes its own detail, so you can keep drilling, with a back arrow at every
/// level (NavigationStack handles the stack automatically).
struct GroupScreen: View {
    @ObservedObject var store: BottleStore
    let section: String
    let dimension: String
    let value: String
    @Environment(\.closeDetail) private var closeDetail

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let desc = store.description(dimension: dimension, value: value, section: section) {
                    GlossaryText(desc, store: store, font: .system(.callout, design: .serif))
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.cgCard)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.cgBorder, lineWidth: 1))
                }
                ForEach(store.bottles(section: section, field: dimension, equals: value)) { b in
                    NavigationLink(destination: WineDetailView(wine: b, store: store)) {
                        HStack(spacing: 12) {
                            WineThumbnail(urlString: b.image_url, size: 48)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(b.displayName)
                                    .font(.system(.body, design: .serif))
                                    .foregroundColor(.cgText)
                                    .multilineTextAlignment(.leading)
                                // Type subtitle disambiguates wines from liquors in a
                                // cross-section company/producer list.
                                if let v = b.varietal, !v.isEmpty {
                                    Text(v)
                                        .font(.caption)
                                        .foregroundColor(.cgTextMuted)
                                }
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(.caption2).foregroundColor(.cgTextMuted)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.cgCard)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.cgBorder, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 16)
        }
        .background(Color.cgBackground.ignoresSafeArea())
        .navigationTitle(value)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { CloseDetailButton(action: closeDetail) } }
    }
}

/// The trailing "✕" that dismisses an entire detail stack back to the main list,
/// shown at every level so you never have to tap Back repeatedly.
struct CloseDetailButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.body.weight(.semibold))
                .foregroundColor(.cgAccent)
        }
    }
}

// MARK: - Glossary (tappable term definitions)

/// Body text with glossary terms made tappable (bold + accent). Tapping one opens its
/// definition in a bottom sheet — installed once per screen via `.glossaryHost`.
struct GlossaryText: View {
    @ObservedObject var store: BottleStore
    let text: String
    var font: Font = .system(.body, design: .serif)
    var color: Color = .cgText

    init(_ text: String, store: BottleStore,
         font: Font = .system(.body, design: .serif), color: Color = .cgText) {
        self.store = store; self.text = text; self.font = font; self.color = color
    }

    var body: some View {
        Text(store.glossaryAttributed(text))
            .font(font)
            .foregroundColor(color)
            .tint(.cgAccent)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Installs glossary-link interception + the definition bottom sheet for a subtree.
/// Apply once per presentation context (each fullScreenCover, and the main list).
struct GlossaryHostModifier: ViewModifier {
    @ObservedObject var store: BottleStore
    @State private var selected: GlossaryHit?

    func body(content: Content) -> some View {
        content
            .environment(\.openURL, OpenURLAction { url in
                guard url.scheme == "glossary" else { return .systemAction }
                let key = String(url.absoluteString.dropFirst("glossary:".count)).removingPercentEncoding ?? ""
                if let hit = store.glossaryHit(key) { selected = hit }
                return .handled
            })
            .sheet(item: $selected) { hit in
                GlossarySheet(hit: hit)
                    .presentationDetents([.fraction(0.33), .medium])
                    .presentationDragIndicator(.visible)
            }
    }
}

extension View {
    func glossaryHost(_ store: BottleStore) -> some View { modifier(GlossaryHostModifier(store: store)) }
}

/// The tap-up definition card.
struct GlossarySheet: View {
    let hit: GlossaryHit
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(hit.term)
                    .font(.system(.title2, design: .serif))
                    .foregroundColor(.cgAccent)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill").font(.title2).foregroundColor(.cgTextMuted)
                }
            }
            Text(hit.definition)
                .font(.system(.body, design: .serif))
                .foregroundColor(.cgText)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.cgBackground.ignoresSafeArea())
    }
}

private struct LocationCard: View {
    let title: String
    let location: BottleLocation

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "mappin.circle.fill")
                .font(.title3)
                .foregroundColor(.cgAccent)
            VStack(alignment: .leading, spacing: 2) {
                Text(title.uppercased())
                    .font(.caption2.bold())
                    .tracking(1.5)
                    .foregroundColor(.cgTextMuted)
                if let s = location.displayString {
                    Text(s)
                        .font(.system(.callout, design: .serif))
                        .foregroundColor(.cgText)
                } else {
                    Text("Not set")
                        .font(.system(.callout, design: .serif))
                        .foregroundColor(.cgTextMuted)
                        .italic()
                }
            }
            Spacer()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.cgCard)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.cgBorder, lineWidth: 1))
    }
}
