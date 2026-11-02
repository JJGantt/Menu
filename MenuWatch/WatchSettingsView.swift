import SwiftUI
import WatchKit

struct WatchSettingsView: View {
    @State private var model = AIModel.current
    @State private var hasKey = APIKeyStore.current != nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Button {
                    WatchChatHistory.shared.clear()
                    WKInterfaceDevice.current().play(.click)
                } label: {
                    Text("Clear context")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                section(title: "API key") {
                    Text(hasKey ? "Set (from iPhone)" : "Not set — open Settings on iPhone")
                        .font(.system(size: 12))
                        .foregroundColor(hasKey ? .white : .red)
                }

                section(title: "Model") {
                    ForEach(AIModel.allCases) { m in
                        radioRow(label: m.label, selected: model == m,
                                 allowed: AppGate.allowedModels.contains(m.key)) {
                            model = m
                            AIModel.current = m
                        }
                    }
                }

                section(title: "About") {
                    infoRow(label: "Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                    infoRow(label: "Build", value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—")
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    @ViewBuilder
    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            VStack(spacing: 2) {
                content()
            }
        }
    }

    @ViewBuilder
    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 14))
                .foregroundColor(.white)
            Spacer()
            Text(value)
                .font(.system(size: 14))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func radioRow(label: String, selected: Bool, allowed: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 16))
                    .foregroundColor(selected ? .accentColor : .secondary)
                Text(label)
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                Spacer()
            }
            .contentShape(Rectangle())
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .disabled(!allowed)
        .opacity(allowed ? 1 : 0.35)
    }
}
