import AVFoundation
import Speech

/// On-device speech commands: "faster", "slower", "stop", "go", "top".
@MainActor
final class Voice: ObservableObject {
    @Published var listening = false
    @Published var heard = ""

    private let player: Player
    private let engine = AVAudioEngine()
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var handled = 0
    private var restart: Timer?

    init(player: Player) { self.player = player }

    func toggle() { listening ? stop() : start() }

    func start() {
        SFSpeechRecognizer.requestAuthorization { [weak self] auth in
            Task { @MainActor in
                guard auth == .authorized else { self?.player.flash("speech not authorised (System Settings → Privacy)"); return }
                AVCaptureDevice.requestAccess(for: .audio) { ok in
                    Task { @MainActor in ok ? self?.begin() : self?.player.flash("mic not authorised") }
                }
            }
        }
    }

    private func begin() {
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        guard let recognizer, recognizer.isAvailable else { player.flash("speech recogniser unavailable"); return }
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        req.contextualStrings = ["faster", "slower", "stop", "go", "top"]
        request = req
        handled = 0

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in req.append(buffer) }
        do { engine.prepare(); try engine.start() } catch { player.flash("mic failed: \(error.localizedDescription)"); return }

        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let result { self.consume(result.bestTranscription) }
                if error != nil || result?.isFinal == true, self.listening { self.restartSoon() }
            }
        }
        listening = true
        player.flash("listening")
        // Recognition sessions are capped at about a minute; roll over before that.
        restart = Timer.scheduledTimer(withTimeInterval: 50, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.restartSoon() }
        }
    }

    private func restartSoon() {
        teardown()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            if let self, self.listening { self.begin() }
        }
    }

    /// Apply one spoken command word. Shared by the recogniser and the test hook.
    func apply(_ word: String) {
        heard = word
        switch word.lowercased() {
        case "faster", "quicker", "speed": player.faster()
        case "slower", "slow": player.slower()
        case "stop", "pause", "wait": if player.running { player.toggle() }
        case "go", "start", "play", "scroll": if !player.running { player.toggle() }
        case "top", "restart": player.top()
        default: break
        }
    }

    private func consume(_ t: SFTranscription) {
        let words = t.segments.map { $0.substring }
        guard words.count > handled else { return }
        for w in words[handled...] { apply(w) }
        handled = words.count
    }

    func stop() {
        listening = false
        teardown()
        player.flash("voice off")
    }

    private func teardown() {
        restart?.invalidate()
        task?.cancel(); task = nil
        request?.endAudio(); request = nil
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }
}
