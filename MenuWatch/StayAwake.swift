import AVFoundation

/// **Keeps the app running, wrist down, until the answer is in.** Once a voice prompt's recording ends,
/// the app still has to transcribe it and wait on the model, and with the wrist down watchOS suspends it
/// in the middle of that: the answer's tap never comes, and the screen still says it is thinking when he
/// looks. So while the chat is thinking (or an order is being taken) this HOLDS THE MICROPHONE and throws
/// away what it hears, and lets go the moment it is not.
///
/// Playing silence does NOT do this, though it looks like it should: a watch app that only plays is frozen
/// the instant the wrist drops, with its engine still reporting running (measured on StatusHub's watch,
/// and here: an order's transcript came back from the hub in 1.6s and the watch only saw it 30s later). A
/// watch app that records is kept running.
///
/// It does not make a dimmed screen redraw faster (watchOS caps that at about once a second); it keeps
/// the app working so the answer lands, and the wrist is tapped, on time.
@MainActor
final class StayAwake {
    static let shared = StayAwake()

    private let engine = AVAudioEngine()
    private var holding = false
    /// The most it holds for in one go, his number: past this an answer that has not come is not worth
    /// the battery to wait on awake, and the app goes back to being suspended as usual.
    private static let longest: TimeInterval = 60
    /// Counts each hold, so the cut-off for an earlier one cannot end a later one.
    private var hold = 0
    /// The minute ran out on this wait: nothing restarts the hold until the chat stops thinking.
    private var spent = false

    /// Told when the minute runs out with the chat still thinking, so the log shows the app was let go.
    var onExpired: (() -> Void)?

    private init() {}

    /// Holds while `on`, lets go when not. Called whenever the chat's thinking state changes.
    func set(_ on: Bool) {
        if !on { spent = false; stop() } else if !spent { start() }
    }

    private func start() {
        if holding && engine.isRunning { return }
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else {
                try? session.setActive(false, options: .notifyOthersOnDeactivation)
                throw NSError(domain: "StayAwake", code: 1, userInfo: [NSLocalizedDescriptionKey: "no microphone format"])
            }
            if !holding { input.installTap(onBus: 0, bufferSize: 4096, format: format) { _, _ in } }
            if !engine.isRunning { try engine.start() }
            if !holding {
                hold += 1
                let this = hold
                Task { [weak self] in
                    try? await Task.sleep(for: .seconds(Self.longest))
                    guard let self, self.holding, self.hold == this else { return }
                    self.spent = true
                    self.stop()
                    self.onExpired?()
                }
            }
            holding = true
        } catch {
            engine.inputNode.removeTap(onBus: 0)
            VoiceLog.record("voice_stay_awake_failed", id: UUID(), sessionId: "",
                            error: String(describing: error), ends: true)
        }
    }

    private func stop() {
        guard holding else { return }
        holding = false
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
