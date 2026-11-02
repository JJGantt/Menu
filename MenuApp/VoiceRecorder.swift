import Foundation
import Speech
import AVFoundation

@MainActor
final class VoiceRecorder: ObservableObject {
    @Published var transcript: String = ""
    @Published var isRecording: Bool = false
    @Published var error: String?

    private let recognizer = SFSpeechRecognizer()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    /// Start recording. Requests permissions on first call.
    /// On any failure, sets `error` and leaves `isRecording = false`.
    func start() async {
        error = nil
        transcript = ""

        // Speech recognition authorization
        let speechAuth: SFSpeechRecognizerAuthorizationStatus = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0) }
        }
        guard speechAuth == .authorized else {
            error = "Speech recognition not authorized. Enable in Settings."
            return
        }

        // Mic permission
        let micGranted: Bool = await withCheckedContinuation { cont in
            AVAudioSession.sharedInstance().requestRecordPermission { cont.resume(returning: $0) }
        }
        guard micGranted else {
            error = "Microphone not authorized. Enable in Settings."
            return
        }

        guard let recognizer, recognizer.isAvailable else {
            error = "Speech recognizer unavailable."
            return
        }

        // Audio session
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            self.error = "Audio session error: \(error.localizedDescription)"
            return
        }

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        self.request = req

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.request?.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            self.error = "Audio engine error: \(error.localizedDescription)"
            cleanup()
            return
        }

        isRecording = true

        task = recognizer.recognitionTask(with: req) { [weak self] result, err in
            guard let self else { return }
            Task { @MainActor in
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                }
                if err != nil || (result?.isFinal == true) {
                    self.cleanup()
                }
            }
        }
    }

    /// Stop recording and return the final transcript (may be empty).
    @discardableResult
    func stop() -> String {
        let final = transcript
        cleanup()
        return final
    }

    private func cleanup() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        isRecording = false
    }
}
