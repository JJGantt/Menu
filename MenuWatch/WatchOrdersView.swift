import SwiftUI
import WatchKit

/// **The order list.** Double tap, or a tap on the page away from a row, starts a recording of a guest ordering, the next press sends it: the
/// hub transcribes it, `OrderTaker` writes the items down as heard (they land at the top of the list,
/// with a tap), then renames each to its menu name a few seconds later. A row still as heard is drawn
/// dimmer. The clip is deleted once it is on the list; only the text is kept.
///
/// **A bad connection loses nothing.** A recording that cannot be transcribed is kept (`OrderOutbox`) and
/// shown at the top as an unsent row, and goes again by itself when the network comes back
/// (`Connectivity`), when the app comes to the front, and after any order lands. Rows the menu pass
/// never reached (it timed out) are matched again on those same moments. None of this is a timer.
///
/// Rows work like the restock list's: a tap arms one (red), a second tap marks it done and it leaves the
/// list. The same two taps on an unsent row throw the recording away. Clear all at the bottom takes two presses.
///
/// Owner only (`WatchContentView`): the list sits behind the hub's owner-gated route.
struct WatchOrdersView: View {
    @EnvironmentObject private var store: OrderStore
    @EnvironmentObject private var bottleStore: BottleStore
    @StateObject private var menuStore = MenuStore()
    @StateObject private var cocktailStore = CocktailStore()
    @ObservedObject private var capture = VoiceCapture.shared
    @ObservedObject private var connectivity = Connectivity.shared
    @StateObject private var outbox = OrderOutbox()
    @Environment(\.onScreen) private var onScreen
    @Environment(\.scenePhase) private var phase

    @State private var working = false
    @State private var task: Task<Void, Never>?
    /// Unsent recordings going again, or the menu pass catching up, in the background: a new
    /// recording can still be taken meanwhile.
    @State private var catchingUp = false
    @State private var armedUnsent: UUID?
    @State private var armedID: String?
    @State private var clearArmed = false
    @State private var errorMsg: String?
    /// The `app_logs` interaction the recording under way belongs to (`VoiceLog`).
    @State private var voiceId = UUID()
    private let sessionId = "orders"

    private static let top: CGFloat = 32

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Orders")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.gray)
                        .padding(.horizontal, 8)
                        .padding(.bottom, 4)
                    ForEach(outbox.items) { item in
                        unsentRow(item)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(RoundedRectangle(cornerRadius: 8)
                                .fill(armedUnsent == item.id ? Color.red.opacity(0.35) : Color.clear))
                    }
                    ForEach(store.orders) { order in
                        row(order)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(RoundedRectangle(cornerRadius: 8)
                                .fill(armedID == order.id ? Color.red.opacity(0.35) : Color.clear))
                    }
                    if !store.orders.isEmpty {
                        clearAllButton.padding(.top, 10)
                    }
                    if let err = errorMsg ?? store.loadError {
                        Text(err)
                            .foregroundColor(.red)
                            .font(.system(size: 11))
                            .lineLimit(3)
                            .padding(8)
                    }
                }
                .padding(.top, Self.top)
                .padding(.horizontal, 4)
                .padding(.bottom, 60)
                // A tap anywhere that is not a row or Clear all is the press, as a double tap is. The
                // rows' own buttons win over this, so arming and marking done are unchanged. Filling the
                // glass makes the space below a short list tappable too.
                .frame(maxWidth: .infinity, minHeight: WKInterfaceDevice.current().screenBounds.height,
                       alignment: .topLeading)
                .contentShape(Rectangle())
                .onTapGesture(perform: press)
            }
            .scrollIndicators(.never)
            .ignoresSafeArea(edges: .top)
        }
        .overlay {
            ZStack {
                // Double tap is the press: start, then send. Bound only while this page is showing, since
                // the chat page binds it too.
                Button(action: press) { Color.clear.frame(width: 1, height: 1) }
                    .buttonStyle(.plain)
                    .handGestureShortcut(.primaryAction)
                    .disabled(!onScreen || working)
                    .accessibilityHidden(true)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                if capture.recording {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture(perform: press)
                        .ignoresSafeArea()
                }
                if capture.recording || working {
                    VStack {
                        Spacer()
                        Button(action: capture.recording ? cancelRecording : cancel) {
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
                VoiceBorder(state: capture.recording ? .recording : working ? .working : .idle)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: working || catchingUp) { _, now in StayAwake.shared.set(now) }
        .onChange(of: phase) { _, now in
            if now == .active && onScreen { Task { await store.refresh() } }
            if now == .active { catchUp() }
            startIfAsked()
        }
        .onChange(of: connectivity.cameBack) { _, _ in catchUp() }
        .onChange(of: onScreen) { _, now in
            if now { Task { await store.refresh() } }
            startIfAsked()
        }
        .onChange(of: capture.recordRequested) { _, _ in startIfAsked() }
        .onAppear(perform: startIfAsked)
        .task {
            if menuStore.menu == nil { menuStore.load() }
            if cocktailStore.cocktails.isEmpty { cocktailStore.load() }
            // The chat page loads the catalog on launch; an order taken before that lands needs it too,
            // or every bottle id is refused.
            if bottleStore.bottles.isEmpty { await bottleStore.refreshFromSupabase() }
            await store.refresh()
            catchUp()
        }
    }

    @ViewBuilder
    private func row(_ order: Order) -> some View {
        Button { tap(order) } label: {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(order.qty > 1 ? "\(order.qty)× \(order.name)" : order.name)
                        .font(.system(size: 14))
                        .foregroundColor(order.standardized ? .white : Color(white: 0.6))
                    if let note = order.note, !note.isEmpty {
                        Text(note)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                Spacer(minLength: 4)
                if armedID == order.id {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.white)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// A recording not yet on the list: a mark and how long it is.
    private func unsentRow(_ item: OrderOutbox.Item) -> some View {
        Button { tapUnsent(item) } label: {
            HStack {
                Image(systemName: "icloud.slash")
                    .font(.system(size: 13))
                    .foregroundColor(VoiceBorder.red)
                Text(Duration.seconds(item.duration).formatted(.time(pattern: .minuteSecond)))
                    .font(.system(size: 14).monospacedDigit())
                    .foregroundColor(Color(white: 0.6))
                Spacer(minLength: 4)
                if armedUnsent == item.id {
                    Image(systemName: "trash.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.white)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func tapUnsent(_ item: OrderOutbox.Item) {
        if armedUnsent == item.id {
            armedUnsent = nil
            WKInterfaceDevice.current().play(.click)
            outbox.remove(item.id)
            VoiceLog.record("orders_unsent_discarded", id: item.id, sessionId: sessionId, ends: true)
        } else {
            armedUnsent = item.id
            let armed = item.id
            Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                if armedUnsent == armed { armedUnsent = nil }
            }
        }
    }

    private var clearAllButton: some View {
        Button {
            if clearArmed {
                clearArmed = false
                WKInterfaceDevice.current().play(.click)
                Task { await store.clearAll() }
            } else {
                clearArmed = true
                Task {
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    clearArmed = false
                }
            }
        } label: {
            Text(clearArmed ? "Confirm" : "Clear all")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(clearArmed ? VoiceBorder.red : .white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func tap(_ order: Order) {
        if armedID == order.id {
            armedID = nil
            WKInterfaceDevice.current().play(.click)
            Task { await store.done(order.id) }
        } else {
            armedID = order.id
            let armed = order.id
            Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                if armedID == armed { armedID = nil }
            }
        }
    }

    // MARK: recording

    private func press() {
        guard !working else { return }
        if capture.recording {
            send()
        } else {
            errorMsg = nil
            voiceId = UUID()
            let id = voiceId
            capture.start(onTaken: send) { error in
                errorMsg = error.localizedDescription
                VoiceLog.record("voice_mic_failed", id: id, sessionId: sessionId, error: String(describing: error), ends: true)
            }
        }
    }

    /// Starts the recording the order complication asked for (`menuapp://order`), once the app is
    /// active and this page is showing — the same press as a double tap, so the same haptic and chirp. A
    /// request older than `VoiceCapture.requestWindow` lapses rather than firing on a later wrist raise.
    private func startIfAsked() {
        guard capture.recordRequested, capture.requestedFor == .orders, phase == .active, onScreen else { return }
        capture.recordRequested = false
        guard capture.requestIsFresh, !capture.recording, !working else { return }
        press()
    }

    private func cancelRecording() {
        guard capture.recording else { return }
        capture.cancel()
        VoiceLog.record("voice_cancelled", id: voiceId, sessionId: sessionId, ends: true)
        WKInterfaceDevice.current().play(.failure)
    }

    private func cancel() {
        task?.cancel()
        task = nil
        working = false
        WKInterfaceDevice.current().play(.failure)
    }

    /// Ends the recording and sends it. One that cannot be sent is kept, with the failure buzz.
    private func send() {
        guard let clip = capture.stop() else { return }
        WKInterfaceDevice.current().play(.stop)
        let id = voiceId
        let bytes = (try? FileManager.default.attributesOfItem(atPath: clip.url.path)[.size] as? Int) ?? nil
        VoiceLog.record("voice_recorded", id: id, sessionId: sessionId, output: bytes.map { "\($0) bytes" },
                        latencyMs: Int(clip.duration * 1000))
        working = true
        errorMsg = nil
        task = Task {
            let outcome = await take(clip, id: id)
            switch outcome {
            case .listed:
                break
            case .unsent:
                outbox.keep(clip, id: id)
                VoiceLog.record("orders_kept_unsent", id: id, sessionId: sessionId, ends: true)
            case .cancelled, .empty:
                try? FileManager.default.removeItem(at: clip.url)
            }
            guard !Task.isCancelled else { return }
            working = false
            task = nil
            if outcome != .listed { WKInterfaceDevice.current().play(.failure) }
            if outcome == .listed { catchUp() }
        }
    }

    enum Outcome { case listed, empty, unsent, cancelled }

    /// **The whole path for one recording**: the hub transcribes it, the first pass lists what was
    /// ordered (the success tap), the second matches it to the menu. Used for a fresh recording and for
    /// an unsent one going again, under its original id. Leaves the clip where it is; the caller deletes
    /// or keeps it by the outcome. `.unsent` means it never became text, so it is worth sending again.
    private func take(_ clip: Recorder.Clip, id: UUID) async -> Outcome {
        let sent = Date()
        func elapsed() -> Int { Int(Date().timeIntervalSince(sent) * 1000) }
        let words: String
        do {
            words = try await Transcriber.transcribe(clip, interactionId: id) { attempt, error in
                VoiceLog.record("voice_transcribe_retry", id: id, sessionId: sessionId, output: "try \(attempt)",
                                error: String(describing: error), latencyMs: elapsed())
            }
            try Task.checkCancellation()
        } catch {
            if Task.isCancelled {
                VoiceLog.record("voice_cancelled", id: id, sessionId: sessionId, latencyMs: elapsed(), ends: true)
                return .cancelled
            }
            VoiceLog.record("voice_transcribe_failed", id: id, sessionId: sessionId, error: String(describing: error),
                            latencyMs: elapsed())
            return .unsent
        }
        guard !words.isEmpty else {
            VoiceLog.record("voice_empty", id: id, sessionId: sessionId, latencyMs: elapsed(), ends: true)
            return .empty
        }
        VoiceLog.record("voice_transcribed", id: id, sessionId: sessionId, output: words, latencyMs: elapsed())

        let rows: [Order]
        do {
            rows = try await OrderTaker.write(words, store: store, interactionId: id, sessionId: sessionId)
            VoiceLog.record("orders_added", id: id, sessionId: sessionId, output: "\(rows.count)", latencyMs: elapsed())
        } catch {
            if Task.isCancelled {
                VoiceLog.record("voice_cancelled", id: id, sessionId: sessionId, latencyMs: elapsed(), ends: true)
                return .cancelled
            }
            VoiceLog.record("orders_failed", id: id, sessionId: sessionId, error: String(describing: error),
                            latencyMs: elapsed())
            // The first pass failed after the words came back: they go on the list whole, as one row, so
            // the order is still there to read. The hub returns the rows already written under this id
            // instead, if the pass's own write landed and only its answer was lost. If even that write
            // fails, the clip is kept and the whole path runs again later.
            guard (try? await store.add([["name": words, "qty": 1]], heard: words, interactionId: id)) != nil else {
                return .unsent
            }
            VoiceLog.record("orders_kept_as_heard", id: id, sessionId: sessionId, latencyMs: elapsed(), ends: true)
            WKInterfaceDevice.current().play(.success)
            return .listed
        }
        // The items are on the list as heard: that is the moment to tell the wrist. Matching them to the
        // menu carries on with the app still held awake.
        WKInterfaceDevice.current().play(rows.isEmpty ? .retry : .success)
        if !rows.isEmpty { await standardize(rows, id: id, elapsed: elapsed) }
        VoiceLog.record("orders_done", id: id, sessionId: sessionId, latencyMs: elapsed(), ends: true)
        return .listed
    }

    /// The second pass. Its failure is not the order's: the rows are listed as heard, drawn dimmer, and
    /// `catchUp` matches them again later, so there is no failure buzz for it.
    private func standardize(_ rows: [Order], id: UUID, elapsed: () -> Int) async {
        do {
            try await OrderTaker.standardize(rows, store: store, menu: menuStore.menu,
                                             bottles: Array(bottleStore.bottles.values),
                                             cocktails: cocktailStore.cocktails,
                                             interactionId: id, sessionId: sessionId)
            VoiceLog.record("orders_standardized", id: id, sessionId: sessionId, latencyMs: elapsed())
        } catch {
            VoiceLog.record("orders_standardize_failed", id: id, sessionId: sessionId,
                            error: String(describing: error), latencyMs: elapsed())
        }
    }

    /// Sends the unsent recordings again, oldest first, then has the menu pass look at any row it never
    /// reached. Runs on the moments a send could newly work (the network back, the app in front, an order
    /// just landed), never on a timer; it stops at the first recording that still cannot go, and waits for
    /// the next of those moments.
    private func catchUp() {
        guard !catchingUp, phase == .active else { return }
        catchingUp = true
        Task {
            defer { catchingUp = false }
            while let item = outbox.items.first {
                let outcome = await take(outbox.clip(of: item), id: item.id)
                if outcome == .unsent {
                    await AppLogger.shared.flush(item.id)
                    break
                }
                outbox.remove(item.id)
            }
            // Not while a fresh recording is in its own passes: its rows are about to be matched.
            guard !working, menuStore.menu != nil, !bottleStore.bottles.isEmpty else { return }
            let stale = store.orders.filter { !$0.standardized }
            guard !stale.isEmpty else { return }
            let id = UUID()
            let sent = Date()
            await standardize(stale, id: id) { Int(Date().timeIntervalSince(sent) * 1000) }
            await AppLogger.shared.flush(id)
        }
    }
}

extension EnvironmentValues {
    /// Whether this page is the one showing. Every page is alive side by side in the TabView, so a page
    /// that binds double tap asks this first.
    @Entry var onScreen: Bool = true
}
