import SwiftUI

/// The assistant conversation shown over the tabs: each question and answer,
/// the question being worked on, the tool currently running, and any error.
struct AssistantChatView: View {
    let history: [ContentView.QAExchange]
    let pendingQuestion: String?
    let busy: Bool
    let activity: String?
    let error: String?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                content
                Color.clear.frame(height: 1).id("bottomAnchor")
            }
            .scrollDismissesKeyboard(.immediately)
            .onAppear { proxy.scrollTo("bottomAnchor", anchor: .bottom) }
            .onChange(of: history.count) { _ in
                withAnimation { proxy.scrollTo("bottomAnchor", anchor: .bottom) }
            }
            .onChange(of: pendingQuestion) { _ in
                withAnimation { proxy.scrollTo("bottomAnchor", anchor: .bottom) }
            }
        }
    }

    /// Parse markdown so **bold**, *italic*, lists, etc. render properly.
    /// Falls back to plain text if parsing fails.
    private func renderMarkdown(_ source: String) -> AttributedString {
        if let attr = try? AttributedString(
            markdown: source,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace
            )
        ) {
            return attr
        }
        return AttributedString(source)
    }

    /// A single chat message in its own bordered card — used for both the user
    /// prompt and the AI response so each is separated the same way exchanges are.
    @ViewBuilder
    private func chatBubble<Content: View>(icon: String,
                                           iconColor: Color,
                                           iconAlignment: VerticalAlignment = .top,
                                           @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: iconAlignment, spacing: 6) {
            Image(systemName: icon)
                .foregroundColor(iconColor)
                .font(.callout)
            content()
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.cgCard)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.cgBorder, lineWidth: 1))
    }

    @ViewBuilder
    private var content: some View {
            VStack(alignment: .leading, spacing: 12) {
                if history.isEmpty && error == nil && pendingQuestion == nil {
                    VStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.title)
                            .foregroundColor(.cgAccent.opacity(0.5))
                        Text("Ask anything")
                            .font(.callout)
                            .foregroundColor(.cgTextMuted)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
                }
                ForEach(history) { ex in
                    chatBubble(icon: "person.crop.circle.fill", iconColor: .cgTextMuted) {
                        Text(ex.question)
                            .font(.callout)
                            .fontWeight(.semibold)
                            .foregroundColor(.cgText)
                    }
                    chatBubble(icon: "sparkles", iconColor: .cgAccent) {
                        Text(renderMarkdown(ex.answer))
                            .font(.callout)
                            .foregroundColor(.cgText)
                            .textSelection(.enabled)
                    }
                }
                if let pending = pendingQuestion {
                    chatBubble(icon: "person.crop.circle.fill", iconColor: .cgTextMuted) {
                        Text(pending)
                            .font(.callout)
                            .fontWeight(.semibold)
                            .foregroundColor(.cgText)
                    }
                    chatBubble(icon: "sparkles", iconColor: .cgAccent, iconAlignment: .center) {
                        ProgressView().progressViewStyle(.circular).scaleEffect(0.7)
                    }
                }
                // Tool-use / activity indicator — at the BOTTOM so it's the most recent
                // thing visible in a long conversation (auto-scrolled into view).
                if busy, let activity {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "wrench.and.screwdriver.fill")
                            .foregroundColor(.cgAccent.opacity(0.7))
                            .font(.caption)
                        Text(activity)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.cgTextMuted)
                            .textSelection(.enabled)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.cgCard.opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.cgBorder.opacity(0.6), lineWidth: 1))
                }
                if let err = error {
                    Text(err)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.red.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
    }
}
