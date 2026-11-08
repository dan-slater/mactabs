import AVFoundation
import Foundation
import NoteJudge

/// Feeds audio (the mic, or a file for tests) into a NoteJudge and reports when the notes it
/// is waiting for are struck. All judging happens on one serial queue; results come back on
/// the main queue.
final class Listener {
    struct Hit {
        let step: Int
        /// Pluck to registered, seconds: analysis delay + buffer transit + the device's input latency.
        let latency: Double?
    }

    /// Called on the main queue.
    var onHit: ((Hit) -> Void)?
    /// What the judge hears right now (main queue, ~15 Hz): loudest pitched note and input level.
    var onMeter: ((Int?, Float, Float?) -> Void)?
    /// Every pluck the judge picks out while waiting (main queue), for the session log.
    var onStruck: (([Int], Int, Float, [Int]) -> Void)?

    private let q = DispatchQueue(label: "mactabs.listener", qos: .userInteractive)
    private var judge: NoteJudge?
    private var engine: AVAudioEngine?
    private var feeder: Thread?
    private var feedStop = false

    // Judging state, touched only on `q`.
    private var step = -1
    private var expected: Set<Int> = []
    private var got: Set<Int> = []
    private var since = 0
    private var lastMeter = 0.0
    private var lastPluckHop = -1000
    /// Maps judge sample index to host time for the newest buffer.
    private var bufStartSample = 0
    private var bufStartHost: Double = 0
    private var bufFrames = 0
    private var inputLatency: Double = 0
    private var mono: [Float] = []

    var micRunning: Bool { engine?.isRunning == true }

    /// Wait for these pitches (one step). All must be struck after this call.
    func expect(step: Int, pitches: Set<Int>) {
        q.async { [self] in
            self.step = step
            expected = pitches
            got = []
            since = judge?.hop ?? 0
        }
    }

    // MARK: sources

    func startMic() -> String? {
        stop()
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let fmt = input.outputFormat(forBus: 0)
        guard fmt.sampleRate > 0 else { return "no microphone input" }
        let latency = input.presentationLatency
        q.sync { reset(rate: fmt.sampleRate); inputLatency = latency }
        input.installTap(onBus: 0, bufferSize: 512, format: fmt) { [weak self] buf, when in
            guard let self, let ch = buf.floatChannelData else { return }
            let n = Int(buf.frameLength), chans = Int(fmt.channelCount)
            var x = [Float](repeating: 0, count: n)
            for c in 0..<chans { let p = ch[c]; for i in 0..<n { x[i] += p[i] } }
            if chans > 1 { for i in 0..<n { x[i] /= Float(chans) } }
            let host = when.isHostTimeValid ? AVAudioTime.seconds(forHostTime: when.hostTime) : Self.now()
            self.q.async { self.feed(x, host: host) }
        }
        do { engine.prepare(); try engine.start() } catch { return "mic failed: \(error.localizedDescription)" }
        self.engine = engine
        return nil
    }

    /// Play a file into the judge in real time (tests: no microphone needed).
    func startFile(_ url: URL) -> String? {
        stop()
        guard let file = try? AVAudioFile(forReading: url) else { return "cannot read \(url.lastPathComponent)" }
        let fmt = file.processingFormat
        q.sync { reset(rate: fmt.sampleRate); inputLatency = 0 }
        feedStop = false
        let t = Thread { [weak self] in
            let chunk: AVAudioFrameCount = 512
            guard let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: chunk) else { return }
            let start = Self.now()
            var done = 0
            while let self, !self.feedStop, (try? file.read(into: buf, frameCount: chunk)) != nil, buf.frameLength > 0 {
                let n = Int(buf.frameLength), chans = Int(fmt.channelCount)
                var x = [Float](repeating: 0, count: n)
                for c in 0..<chans { let p = buf.floatChannelData![c]; for i in 0..<n { x[i] += p[i] / Float(chans) } }
                // Pace like a live input: this buffer's last sample "arrives" now.
                let due = start + Double(done + n) / fmt.sampleRate
                let wait = due - Self.now()
                if wait > 0 { Thread.sleep(forTimeInterval: wait) }
                let host = start + Double(done) / fmt.sampleRate
                self.q.async { self.feed(x, host: host) }
                done += n
            }
        }
        feeder = t
        t.start()
        return nil
    }

    func stop() {
        feedStop = true
        feeder = nil
        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        engine = nil
    }

    // MARK: judging (on q)

    private func reset(rate: Double) {
        let j = NoteJudge(sampleRate: rate)
        j.onHop = { [weak self] h in self?.hop(h) }
        judge = j
        since = 0
        got = []
    }

    private func feed(_ x: [Float], host: Double) {
        guard let judge else { return }
        bufStartSample = judge.samples
        bufStartHost = host
        bufFrames = x.count
        judge.process(x)
    }

    private func hop(_ h: Int) {
        guard let judge else { return }
        let now = Self.now()
        if now - lastMeter > 0.066 {
            lastMeter = now
            let heard = judge.loudest(), level = judge.rmsDB, cents = heard.flatMap { judge.cents($0) }
            DispatchQueue.main.async { [weak self] in self?.onMeter?(heard, level, cents) }
        }
        // Log plucks (any pitched onset) so the session can count tries per note.
        let struck = judge.struckNotes(since: since)
        if !struck.isEmpty && h - lastPluckHop > Int(0.09 * judge.fs) / judge.hopSize {
            lastPluckHop = h
            let s = step, rms = judge.rmsDB, cents = struck.map { m -> Int in
                let c = judge.cents(m) ?? 0
                return c.isFinite ? Int(c.rounded()) : 0
            }
            DispatchQueue.main.async { [weak self] in self?.onStruck?(struck, s, rms, cents) }
        }
        guard step >= 0, !expected.isEmpty else { return }
        for p in expected.subtracting(got) where judge.struck(p, since: since, allowing: expected) { got.insert(p) }
        guard got == expected else { return }
        // Latency: from the hop where the note's level first jumped to now, plus transit + device.
        let onsetHop = expected.map { judge.onsetHop($0, before: h, since: since) }.max() ?? h
        let onsetSample = onsetHop * judge.hopSize - judge.windowSize / 4
        let onsetHost = bufStartHost + Double(onsetSample - bufStartSample) / judge.fs
        let latency = max(0, now - onsetHost) + inputLatency
        let hit = Hit(step: step, latency: latency)
        step = -1
        expected = []
        since = h
        DispatchQueue.main.async { [weak self] in self?.onHit?(hit) }
    }

    /// Record the default input to a file for `seconds` (room tests: score it with pitchbench).
    static func record(to url: URL, seconds: Double, done: @escaping (String) -> Void) {
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let fmt = input.outputFormat(forBus: 0)
        guard let file = try? AVAudioFile(forWriting: url, settings: fmt.settings) else { done("cannot write"); return }
        let latency = input.presentationLatency
        input.installTap(onBus: 0, bufferSize: 1024, format: fmt) { buf, _ in try? file.write(from: buf) }
        do { engine.prepare(); try engine.start() } catch { done("mic failed: \(error.localizedDescription)"); return }
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            input.removeTap(onBus: 0); engine.stop()
            done(String(format: "recorded %.0f Hz, input latency %.1f ms", fmt.sampleRate, latency * 1000))
            _ = file
        }
    }

    static func now() -> Double { AVAudioTime.seconds(forHostTime: mach_absolute_time()) }
}
