import SwiftUI

// MARK: - Cocktails list

struct CocktailsListView: View {
    let cocktails: [Cocktail]
    let searchText: String
    let onTap: (Cocktail) -> Void

    private var filtered: [Cocktail] {
        let q = searchText.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return cocktails }
        return cocktails.filter { cocktailMatches($0, query: q) }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(filtered) { cocktail in
                    Button { onTap(cocktail) } label: {
                        CocktailRow(cocktail: cocktail)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .scrollDismissesKeyboard(.immediately)
    }
}

struct CocktailRow: View {
    let cocktail: Cocktail

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(cocktail.name)
                    .font(.system(.body, design: .serif))
                    .foregroundColor(.cgText)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                if let glass = cocktail.glass {
                    Text(glass)
                        .font(.caption)
                        .foregroundColor(.cgTextMuted)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundColor(.cgTextMuted)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.cgCard)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.cgBorder, lineWidth: 1))
    }
}

// MARK: - Cocktail detail

struct CocktailDetailView: View {
    let cocktail: Cocktail

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(cocktail.name)
                    .font(.system(.title2, design: .serif))
                    .foregroundColor(.cgText)

                // Glass / Service / Garnish meta
                VStack(alignment: .leading, spacing: 4) {
                    if let glass = cocktail.glass { metaLine(label: "Glass", value: glass) }
                    if let service = cocktail.service { metaLine(label: "Service", value: service) }
                    if let garnish = cocktail.garnish { metaLine(label: "Garnish", value: garnish) }
                }

                if !cocktail.ingredients.isEmpty {
                    sectionHeader("Ingredients")
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(cocktail.ingredients, id: \.name) { ing in
                            HStack(alignment: .firstTextBaseline) {
                                Text(ing.name)
                                    .font(.callout)
                                    .foregroundColor(.cgText)
                                Spacer(minLength: 8)
                                if let amount = ing.amount {
                                    Text(amount)
                                        .font(.callout.weight(.medium))
                                        .foregroundColor(.cgAccent)
                                        .multilineTextAlignment(.trailing)
                                }
                            }
                        }
                    }
                }

                if !cocktail.prep.isEmpty {
                    sectionHeader("Prep")
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(cocktail.prep.enumerated()), id: \.offset) { idx, step in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("\(idx + 1).")
                                    .font(.callout.weight(.semibold))
                                    .foregroundColor(.cgAccent)
                                    .frame(width: 22, alignment: .trailing)
                                Text(step)
                                    .font(.callout)
                                    .foregroundColor(.cgText)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.cgBackground.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(.subheadline, design: .serif))
            .fontWeight(.semibold)
            .tracking(2)
            .foregroundColor(.cgAccent)
    }

    private func metaLine(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundColor(.cgTextMuted)
                .frame(width: 64, alignment: .leading)
            Text(value)
                .font(.callout)
                .foregroundColor(.cgText)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
