import SwiftUI

struct SettingsView: View {
    @ObservedObject var bottleStore: BottleStore
    @Environment(\.dismiss) var dismiss
    @State private var model: AIModel = AIModel.current
    @State private var newAreaName: String = ""
    @State private var renameTarget: BottleArea?
    @State private var renameValue: String = ""
    @State private var busy: Bool = false
    @State private var errorMsg: String?
    @State private var apiKeyDraft: String = ""
    @State private var apiKeyMasked: String = ""
    @State private var showKeyEditor: Bool = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Anthropic API key") {
                    if showKeyEditor {
                        SecureField("sk-ant-…", text: $apiKeyDraft)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        HStack {
                            Button("Cancel") {
                                apiKeyDraft = ""
                                showKeyEditor = false
                            }
                            .foregroundColor(.secondary)
                            Spacer()
                            Button("Save") {
                                saveKey()
                            }
                            .disabled(!APIKeyStore.looksValid(apiKeyDraft))
                        }
                    } else {
                        HStack {
                            Text(apiKeyMasked.isEmpty ? "Not set" : apiKeyMasked)
                                .foregroundColor(apiKeyMasked.isEmpty ? .red : .primary)
                                .font(.system(.body, design: .monospaced))
                            Spacer()
                            Button(apiKeyMasked.isEmpty ? "Add" : "Change") {
                                apiKeyDraft = ""
                                showKeyEditor = true
                            }
                        }
                        if !apiKeyMasked.isEmpty {
                            Button(role: .destructive) {
                                APIKeyStore.clear()
                                refreshKeyDisplay()
                                pushKeyToWatch()
                            } label: {
                                Text("Remove key")
                            }
                        }
                    }
                }

                Section("Model") {
                    GatedPicker(options: AIModel.allCases,
                                selection: $model,
                                isAllowed: { AppGate.allowedModels.contains($0.key) },
                                label: { $0.label })
                        .onChange(of: model) { new in AIModel.current = new }
                }

                if AppGate.isOwnerDevice {
                    Section("Areas") {
                    if !bottleStore.areas.isEmpty {
                        ForEach(bottleStore.areas) { area in
                            HStack {
                                Text(area.name)
                                Spacer()
                                Button {
                                    renameTarget = area
                                    renameValue = area.name
                                } label: {
                                    Image(systemName: "pencil")
                                }
                                .buttonStyle(.plain)
                                .foregroundColor(.blue)
                                Button(role: .destructive) {
                                    Task { await remove(area: area.name) }
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.plain)
                                .foregroundColor(.red)
                                .padding(.leading, 12)
                            }
                        }
                    }
                    HStack {
                        TextField("New area", text: $newAreaName)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.words)
                            .onSubmit { Task { await add() } }
                        Button(action: { Task { await add() } }) {
                            Image(systemName: "plus.circle.fill")
                                .font(.title3)
                                .foregroundColor(.accentColor)
                        }
                        .buttonStyle(.plain)
                        .disabled(newAreaName.trimmingCharacters(in: .whitespaces).isEmpty || busy)
                    }
                    }
                }

                if let err = errorMsg {
                    Section { Text(err).foregroundColor(.red).font(.caption) }
                }

                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Build")
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                refreshKeyDisplay()
                await bottleStore.refreshFromSupabase()
            }
            .alert("Rename area", isPresented: Binding(
                get: { renameTarget != nil },
                set: { if !$0 { renameTarget = nil } })) {
                TextField("Name", text: $renameValue)
                Button("Cancel", role: .cancel) { renameTarget = nil }
                Button("Save") { Task { await rename() } }
            }
        }
    }

    private func add() async {
        let name = newAreaName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        busy = true; errorMsg = nil
        do { try await bottleStore.addArea(name); newAreaName = "" }
        catch { errorMsg = error.localizedDescription }
        busy = false
    }

    private func rename() async {
        guard let target = renameTarget else { return }
        let new = renameValue.trimmingCharacters(in: .whitespaces)
        guard !new.isEmpty, new != target.name else { renameTarget = nil; return }
        busy = true; errorMsg = nil
        do { try await bottleStore.renameArea(target.name, to: new) }
        catch { errorMsg = error.localizedDescription }
        renameTarget = nil
        busy = false
    }

    private func refreshKeyDisplay() {
        if let key = APIKeyStore.current, !key.isEmpty {
            let tail = String(key.suffix(4))
            apiKeyMasked = "sk-ant-…\(tail)"
        } else {
            apiKeyMasked = ""
        }
    }

    private func saveKey() {
        let trimmed = apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard APIKeyStore.looksValid(trimmed) else { return }
        _ = APIKeyStore.set(trimmed)
        AppGate.apply()
        apiKeyDraft = ""
        showKeyEditor = false
        refreshKeyDisplay()
        pushKeyToWatch()
    }

    private func pushKeyToWatch() {
        WatchKeySync.shared.pushAPIKey(APIKeyStore.current)
    }

    private func remove(area: String) async {
        busy = true; errorMsg = nil
        do { try await bottleStore.removeArea(area) }
        catch { errorMsg = error.localizedDescription }
        busy = false
    }
}

/// Segmented-style selector that shows every option but grays out and disables
/// the ones the current device isn't permitted to use.
struct GatedPicker<T: Hashable>: View {
    let options: [T]
    @Binding var selection: T
    let isAllowed: (T) -> Bool
    let label: (T) -> String

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.self) { opt in
                let selected = selection == opt
                let allowed = isAllowed(opt)
                Button { selection = opt } label: {
                    Text(label(opt))
                        .font(.subheadline.weight(selected ? .semibold : .regular))
                        .foregroundColor(selected ? .accentColor : .primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(selected ? Color(.systemBackground) : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 6))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!allowed)
                .opacity(allowed ? 1 : 0.35)
            }
        }
        .padding(3)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
    }
}
