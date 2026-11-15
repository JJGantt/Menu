import SwiftUI

/// The bar under every tab, one row: settings and the chat toggle, the
/// assistant's question field or the search field, then clear-chat, the mic and
/// the AI/search toggle.
struct MenuInputBar: View {
    @ObservedObject var voice: VoiceRecorder
    let section: TopSection
    @Binding var aiMode: Bool
    @Binding var aiInput: String
    @Binding var searchText: String
    @Binding var showAIResults: Bool
    let busy: Bool
    /// Whether there is a conversation to show or clear.
    let hasChat: Bool
    let onAsk: (String) -> Void
    let onShowSettings: () -> Void
    let onClearChat: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
                if !voice.isRecording {
                    iconButton("gearshape", color: .cgTextMuted, action: onShowSettings)
                    if hasChat {
                        iconButton(showAIResults ? "bubble.left.fill" : "bubble.left",
                                   color: showAIResults ? .cgAccent : .cgTextMuted) {
                            withAnimation { showAIResults.toggle() }
                        }
                    }
                }
                if voice.isRecording {
                    HStack(alignment: .top, spacing: 8) {
                        PulsingMic()
                            .padding(.top, 2)
                        Text(voice.transcript.isEmpty ? "Listening…" : voice.transcript)
                            .font(.body)
                            .foregroundColor(.cgText)
                            .lineLimit(6, reservesSpace: false)
                            .truncationMode(.head)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color.cgCard)
                    .clipShape(RoundedRectangle(cornerRadius: 22))
                    .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.green.opacity(0.7), lineWidth: 1.5))
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: aiMode ? "sparkles" : "magnifyingglass")
                            .foregroundColor(aiMode ? .cgAccent : .cgTextMuted)
                        if aiMode {
                            TextField("Ask the menu…", text: $aiInput)
                                .submitLabel(.send)
                                .onSubmit(submit)
                                .disabled(busy)
                        } else {
                            TextField(section == .wine ? "Search wines…" : "Search dishes, ingredients…", text: $searchText)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .submitLabel(.search)
                        }
                        if aiMode {
                            if busy {
                                ProgressView().progressViewStyle(.circular).scaleEffect(0.8)
                            } else {
                                Button(action: submit) {
                                    Image(systemName: "arrow.up.circle.fill")
                                        .font(.title2)
                                        .foregroundColor(aiInput.trimmingCharacters(in: .whitespaces).isEmpty ? .cgBorder : .cgAccent)
                                }
                                .disabled(aiInput.trimmingCharacters(in: .whitespaces).isEmpty)
                            }
                        } else if !searchText.isEmpty {
                            Button(action: { searchText = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.cgTextMuted)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color.cgCard)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(aiMode ? Color.cgAccent : Color.cgBorder, lineWidth: aiMode ? 1.5 : 1))
                }

                if voice.isRecording {
                    iconButton("xmark.circle.fill", color: .cgTextMuted) { _ = voice.stop() }
                    iconButton("arrow.up.circle.fill", color: .green, action: primaryAIButtonTap)
                } else {
                    if showAIResults && hasChat {
                        iconButton("trash", color: .cgTextMuted) { withAnimation { onClearChat() } }
                    }
                    // Mic always available — destination depends on current mode.
                    iconButton("mic.fill", color: .cgAccent) { Task { await voice.start() } }
                    // Toggle between AI and search modes.
                    iconButton(aiMode ? "magnifyingglass" : "sparkles",
                               color: aiMode ? .cgTextMuted : .cgAccent) { withAnimation { aiMode.toggle() } }
                }
        }
    }

    private func iconButton(_ symbol: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundColor(color)
                .padding(.vertical, 8)
                .padding(.horizontal, 4)
        }
    }

    private func submit() {
        let q = aiInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        onAsk(q)
    }

    private func primaryAIButtonTap() {
        if voice.isRecording {
            let q = voice.stop().trimmingCharacters(in: .whitespacesAndNewlines)
            guard !q.isEmpty else { return }
            if aiMode {
                onAsk(q)
            } else {
                searchText = q
            }
        } else {
            Task { await voice.start() }
        }
    }
}

// MARK: - Pulsing mic indicator

struct PulsingMic: View {
    @State private var pulse = false
    var body: some View {
        Image(systemName: "mic.fill")
            .foregroundColor(.green)
            .scaleEffect(pulse ? 1.15 : 0.95)
            .opacity(pulse ? 1.0 : 0.6)
            .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: pulse)
            .onAppear { pulse = true }
    }
}
