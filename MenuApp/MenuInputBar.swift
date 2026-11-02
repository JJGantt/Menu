import SwiftUI

/// The bar under every tab: the assistant's question field or the search
/// field, the mic, the AI/search toggle, and below them settings and the chat
/// controls.
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
        VStack(spacing: 6) {
        HStack(alignment: .top, spacing: 8) {
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
                } else if aiMode || section != .restock {
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
                } else {
                    Spacer()
                }

                if voice.isRecording {
                    Button(action: { _ = voice.stop() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundColor(.cgTextMuted)
                            .padding(8)
                    }
                    Button(action: primaryAIButtonTap) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title3)
                            .foregroundColor(.green)
                            .padding(8)
                    }
                } else {
                    // Mic always available — destination depends on current mode.
                    Button(action: { Task { await voice.start() } }) {
                        Image(systemName: "mic.fill")
                            .font(.title3)
                            .foregroundColor(.cgAccent)
                            .padding(8)
                    }
                    // Toggle between AI and search modes.
                    Button(action: { withAnimation { aiMode.toggle() } }) {
                        Image(systemName: aiMode ? "magnifyingglass" : "sparkles")
                            .font(.title3)
                            .foregroundColor(aiMode ? .cgTextMuted : .cgAccent)
                            .padding(8)
                    }
                }
            }

            // Bottom toolbar: settings + chat-history toggle + clear (in chat with history)
            HStack {
                Button(action: onShowSettings) {
                    Image(systemName: "gearshape")
                        .font(.title3)
                        .foregroundColor(.cgTextMuted)
                        .padding(8)
                }
                if hasChat {
                    Button(action: { withAnimation { showAIResults.toggle() } }) {
                        Image(systemName: showAIResults ? "bubble.left.fill" : "bubble.left")
                            .font(.title3)
                            .foregroundColor(showAIResults ? .cgAccent : .cgTextMuted)
                            .padding(8)
                    }
                }
                Spacer()
                if showAIResults && hasChat {
                    Button(action: { withAnimation { onClearChat() } }) {
                        Image(systemName: "trash")
                            .font(.title3)
                            .foregroundColor(.cgTextMuted)
                            .padding(8)
                    }
                }
            }
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
