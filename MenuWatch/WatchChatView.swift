import SwiftUI
import WatchKit

struct WatchChatView: View {
    @ObservedObject private var history = WatchChatHistory.shared
    @StateObject private var menuStore = MenuStore()
    @StateObject private var cocktailStore = CocktailStore()
    @EnvironmentObject private var bottleStore: BottleStore
    @EnvironmentObject private var restockStore: RestockStore
    @State private var chatState: ChatState = .idle
    @State private var lastPrompt = ""
    /// What the hub heard, shown the moment the transcript is back and until the answer lands, so a
    /// wrong transcription can be cancelled before the model has answered it.
    @State private var pending: String?
    /// The tool calls made so far for `pending`, oldest first, drawn under it as StatusHub's watch draws
    /// a running turn's steps (`ActivityLines` there): one small violet monospace line each.
    @State private var toolCalls: [String] = []
    private static let toolInk = Color(red: 0xb3 / 255, green: 0x9d / 255, blue: 0xdb / 255)
    private let pendingAnchor = "pending-anchor"
    @State private var errorMsg: String?
    @State private var currentTask: Task<Void, Never>?
    /// A recording the hub could not be reached to transcribe (no network, the upload timed out), kept so
    /// "Tap to retry" sends it again rather than the question being lost. Gone with the next recording.
    @State private var failedClip: (clip: Recorder.Clip, id: UUID)?
    @ObservedObject private var capture = VoiceCapture.shared
    /// The `app_logs` interaction the recording under way belongs to (`VoiceLog`).
    @State private var voiceId = UUID()
    @Environment(\.scenePhase) private var phase
    /// The orders page binds double tap too; only the page showing takes it.
    @Environment(\.onScreen) private var onScreen

    enum ChatState { case idle, thinking }

    private let responseAnchor = "response-anchor"

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()
            mainContent
            if let err = errorMsg, failedClip != nil || !lastPrompt.isEmpty {
                VStack {
                    Spacer()
                    Button(action: retry) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(err)
                                .foregroundColor(.red)
                                .font(.system(size: 11))
                                .lineLimit(2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text("Tap to retry")
                                .foregroundColor(.white)
                                .font(.system(size: 11, weight: .medium))
                        }
                        .padding(8)
                        .background(Color.red.opacity(0.18), in: RoundedRectangle(cornerRadius: 8))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(8)
                }
            } else if let err = errorMsg {
                VStack {
                    Spacer()
                    Text(err)
                        .foregroundColor(.red)
                        .font(.system(size: 11))
                        .lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
            }
        }
        .overlay {
            ZStack {
                // Double tap is the press: start, then send (`press`). It needs a control to bind to,
                // and there is none on screen, so this is one: a point of nothing.
                Button(action: press) { Color.clear.frame(width: 1, height: 1) }
                    .buttonStyle(.plain)
                    .handGestureShortcut(.primaryAction)
                    .disabled(chatState == .thinking || !onScreen)
                    .accessibilityHidden(true)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                // While recording, the whole glass is the press.
                if capture.recording {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture(perform: press)
                        .ignoresSafeArea()
                }
                // The x at the bottom throws away whatever is under way: the recording, or the
                // question being transcribed and answered.
                if capture.recording || chatState == .thinking {
                    VStack {
                        Spacer()
                        Button(action: capture.recording ? cancelRecording : cancel) {
                            // Bare on the black, in the recording border's red.
                            Image(systemName: "xmark")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundColor(VoiceBorder.red)
                                .frame(width: 72, height: 52)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.bottom, 4)
                    .ignoresSafeArea(edges: .bottom)
                }
                VoiceBorder(state: borderState)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        // Cleared from Settings: a failed question's retry belongs to the conversation that went.
        .onChange(of: history.pairs.isEmpty) { _, empty in
            if empty { lastPrompt = ""; errorMsg = nil; dropFailedClip() }
        }
        .onAppear(perform: startIfAsked)
        .onChange(of: phase) { _, now in
            // Wrist down and up mid-question, in the log: a slow answer can then be told apart from
            // one that sat suspended.
            if chatState == .thinking {
                VoiceLog.record("voice_phase", id: voiceId, sessionId: history.sessionId, output: "\(now)")
            }
            startIfAsked()
        }
        // Kept running wrist-down while the answer is on its way (StayAwake), and let go when it lands.
        .onChange(of: chatState) { _, now in
            StayAwake.shared.onExpired = { [voiceId, sessionId = history.sessionId] in
                VoiceLog.record("voice_stay_awake_expired", id: voiceId, sessionId: sessionId)
            }
            StayAwake.shared.set(now == .thinking)
        }
        .onChange(of: capture.recordRequested) { _, _ in startIfAsked() }
        .task {
            if menuStore.menu == nil { menuStore.load() }
            if cocktailStore.cocktails.isEmpty { cocktailStore.load() }
            // The restock list is tiny; it does not wait behind the catalog.
            async let restock: Void = restockStore.refresh()
            await bottleStore.refreshFromSupabase()
            await restock
        }
    }

    /// The page never changes while a question is worked on: the edge of the glass is the only sign
    /// (`VoiceBorder`), as on StatusHub's watch.
    @ViewBuilder
    private var mainContent: some View {
        if history.pairs.isEmpty && pending == nil {
            Button(action: press) {
                VStack {
                    HStack {
                        Text(">")
                            .foregroundColor(.gray)
                            .font(.system(size: 20, weight: .regular, design: .monospaced))
                        Spacer()
                    }
                    Spacer()
                }
                .padding(.leading, 6)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(Array(history.pairs.enumerated()), id: \.offset) { idx, pair in
                            let isLatest = idx == history.pairs.count - 1
                            VStack(alignment: .leading, spacing: 4) {
                                Text(pair.question)
                                    .foregroundColor(.gray)
                                    .font(.system(size: 12, weight: .medium))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text(pair.answer)
                                    .foregroundColor(.white)
                                    .font(.system(size: 13))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .id(isLatest ? responseAnchor : "pair-\(idx)")
                            }
                        }
                        if let pending {
                            Text(pending)
                                .foregroundColor(.gray)
                                .font(.system(size: 12, weight: .medium))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(pendingAnchor)
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(Array(toolCalls.enumerated()), id: \.offset) { _, call in
                                    Text(call)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundColor(Self.toolInk)
                                        .lineLimit(2)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                }
                .scrollIndicators(.never)
                .onTapGesture(coordinateSpace: .global) { at in
                    if at.y > WKInterfaceDevice.current().screenBounds.height / 2 { press() }
                }
                // Reserve a 32pt strip at the top so the newest response
                // settles below the clock row when we scroll to the
                // responseAnchor.
                .safeAreaInset(edge: .top) {
                    Color.clear.frame(height: 32)
                }
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        withAnimation(.none) { proxy.scrollTo(responseAnchor, anchor: .top) }
                    }
                }
                .onChange(of: pending) { _, now in
                    guard now != nil else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(pendingAnchor, anchor: .top) }
                    }
                }
                .onChange(of: history.pairs.count) { _, _ in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(responseAnchor, anchor: .top) }
                    }
                }
            }
            // History scrolls up under the clock row; the idle prompt above
            // keeps the top safe area so the screen's corner doesn't clip it.
            .ignoresSafeArea(edges: .top)
        }
    }

    private var borderState: VoiceBorder.State {
        if capture.recording { return .recording }
        return chatState == .thinking ? .working : .idle
    }

    /// **The one press**: the first starts a recording, the next sends it. Only a press ends it.
    private func press() {
        guard chatState != .thinking else { return }
        if capture.recording {
            stopRecording()
        } else {
            errorMsg = nil
            dropFailedClip()
            voiceId = UUID()
            let id = voiceId
            capture.start(onTaken: stopRecording) { error in
                errorMsg = error.localizedDescription
                VoiceLog.record("voice_mic_failed", id: id, sessionId: history.sessionId,
                                error: String(describing: error), ends: true)
            }
        }
    }

    /// Starts the recording the complication asked for, once the app is active — the same press as a
    /// tap, so the same haptic and chirp. Nothing starts while a question is still being answered.
    private func startIfAsked() {
        guard capture.recordRequested, capture.requestedFor == .chat, phase == .active else { return }
        capture.recordRequested = false
        guard capture.requestIsFresh, !capture.recording, chatState != .thinking else { return }
        press()
    }

    private func cancelRecording() {
        guard capture.recording else { return }
        capture.cancel()
        VoiceLog.record("voice_cancelled", id: voiceId, sessionId: history.sessionId, ends: true)
        WKInterfaceDevice.current().play(.failure)
    }

    /// Ends the recording, has the hub transcribe it, and asks the question.
    private func stopRecording() {
        guard let clip = capture.stop() else { return }
        WKInterfaceDevice.current().play(.stop)
        let id = voiceId
        let session = history.sessionId
        let bytes = (try? FileManager.default.attributesOfItem(atPath: clip.url.path)[.size] as? Int) ?? nil
        VoiceLog.record("voice_recorded", id: id, sessionId: session, output: bytes.map { "\($0) bytes" },
                        latencyMs: Int(clip.duration * 1000))
        transcribe(clip, id: id)
    }

    /// Has the hub transcribe the clip and asks the question. A clip that never became words (no network,
    /// the upload timed out, the hub failing) is kept for "Tap to retry"; any other ending deletes it.
    private func transcribe(_ clip: Recorder.Clip, id: UUID) {
        let session = history.sessionId
        chatState = .thinking
        errorMsg = nil
        currentTask = Task {
            let sent = Date()
            func elapsed() -> Int { Int(Date().timeIntervalSince(sent) * 1000) }
            do {
                let words = try await Transcriber.transcribe(clip, interactionId: id) { attempt, error in
                    VoiceLog.record("voice_transcribe_retry", id: id, sessionId: session, output: "try \(attempt)",
                                    error: String(describing: error), latencyMs: elapsed())
                }
                try? FileManager.default.removeItem(at: clip.url)
                if Task.isCancelled {
                    VoiceLog.record("voice_cancelled", id: id, sessionId: session, output: words,
                                    latencyMs: elapsed(), ends: true)
                    return
                }
                guard !words.isEmpty else {
                    VoiceLog.record("voice_empty", id: id, sessionId: session, latencyMs: elapsed(), ends: true)
                    chatState = .idle
                    currentTask = nil
                    WKInterfaceDevice.current().play(.failure)
                    return
                }
                VoiceLog.record("voice_transcribed", id: id, sessionId: session, output: words, latencyMs: elapsed())
                currentTask = nil
                send(prompt: words, interactionId: id)
            } catch {
                VoiceLog.record("voice_transcribe_failed", id: id, sessionId: session,
                                error: String(describing: error), latencyMs: elapsed(), ends: true)
                if Task.isCancelled {
                    try? FileManager.default.removeItem(at: clip.url)
                } else {
                    failedClip = (clip, id)
                    errorMsg = error.localizedDescription
                    WKInterfaceDevice.current().play(.failure)
                }
                chatState = .idle
                currentTask = nil
            }
        }
    }

    private func dropFailedClip() {
        if let failedClip { try? FileManager.default.removeItem(at: failedClip.clip.url) }
        failedClip = nil
    }

    private func cancel() {
        currentTask?.cancel()
        currentTask = nil
        pending = nil
        chatState = .idle
        WKInterfaceDevice.current().play(.failure)
    }

    private func retry() {
        if let failed = failedClip {
            failedClip = nil
            transcribe(failed.clip, id: failed.id)
            return
        }
        guard !lastPrompt.isEmpty else { return }
        send(prompt: lastPrompt)
    }

    private func send(prompt: String, interactionId: UUID = UUID()) {
        chatState = .thinking
        errorMsg = nil
        lastPrompt = prompt
        pending = prompt
        toolCalls = []
        currentTask = Task {
            do {
                let turn = try await WatchAIClient.send(
                    prompt: prompt,
                    history: history.pairs,
                    sessionId: history.sessionId,
                    menuStore: menuStore,
                    cocktailStore: cocktailStore,
                    bottleStore: bottleStore,
                    restockStore: restockStore,
                    interactionId: interactionId,
                    onActivity: { activity in
                        // `name({…})` with the input pretty-printed; one line on the wrist.
                        guard let activity else { return }
                        toolCalls.append(activity.split(whereSeparator: \.isWhitespace).joined(separator: " "))
                    }
                )
                if Task.isCancelled { return }
                pending = nil
                history.append(turn)
                // Strong two-pulse haptic when the answer lands.
                WKInterfaceDevice.current().play(.notification)
            } catch is CancellationError {
                // user cancelled — silent
            } catch {
                if !Task.isCancelled {
                    pending = nil
                    errorMsg = error.localizedDescription
                }
            }
            if chatState == .thinking { chatState = .idle }
            currentTask = nil
        }
    }
}
