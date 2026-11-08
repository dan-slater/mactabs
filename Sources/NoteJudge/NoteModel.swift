import AVFoundation
import CoreML
import Foundation

/// Basic Pitch (Spotify, ICASSP 2022, Apache-2.0; `Model/LICENSE-basic-pitch`) run as a stream.
///
/// The model reads 2 s of audio at 22.05 kHz and gives, per 11.6 ms frame and per semitone A0…C8,
/// an onset posterior (a note starts here) and a note posterior (a note sounds here). Live, the
/// window always ends "now", so a frame's onset posterior is only trustworthy once a few frames of
/// audio follow it (it peaks when 4–5 frames, ~50 ms, have been heard; measured on GuitarSet).
/// Every `stride` frames the newest window is run (about 3 ms on Apple silicon) and its newest
/// `keep` frames are kept; `heard` answers from them.
public final class NoteModel {
    public static let rate = 22050.0
    public static let window = 22050 * 2 - 256
    public static let frameHop = 256

    public struct Config {
        public var stride = 2          // frames between model runs (23 ms)
        public var keep = 16           // newest frames kept per run
        public var age = 5             // a frame counts once this many frames (58 ms) follow it
        public var onset: Float = 0.4  // onset posterior for "a new pluck of this pitch"
        public var note: Float = 0.25  // note posterior for "this pitch sounds" (tuned on GuitarSet with Hearing)
        public var slack = -0.03       // a frame counts for a step this long after (or before) it was armed
        public var cpuOnly = false     // true: CPU only (about 14 ms a run, ~0.6 of a core live); default lets CoreML pick (GPU/ANE, ~3 ms)
        public init() {}
    }

    public let config: Config
    let model: MLModel
    let inputName: String
    let input: MLMultiArray
    let fs: Double
    let converter: AVAudioConverter?
    let inFormat: AVAudioFormat, outFormat: AVAudioFormat
    var ring: [Float]
    var ringPos = 0
    var sinceRun = 0
    /// Samples (22.05 kHz) consumed so far; the newest window ends here.
    public private(set) var end = 0
    /// Window end of the newest run, seconds of input.
    public private(set) var runEnd: Double = -1
    /// Newest run: `keep` frames × 88 pitches.
    public private(set) var onset: [Float]
    public private(set) var note: [Float]

    private static let lock = NSLock()
    nonisolated(unsafe) private static var cached: MLModel?
    nonisolated(unsafe) private static var loading = false

    /// The model is loaded and warmed (see `prepare`).
    public static var isReady: Bool { lock.withLock { cached != nil } }

    static func load(cpuOnly: Bool) -> MLModel? {
        guard let url = Bundle.module.url(forResource: "nmp", withExtension: "mlmodelc") else { return nil }
        let c = MLModelConfiguration()
        if cpuOnly { c.computeUnits = .cpuOnly }
        return try? MLModel(contentsOf: url, configuration: c)
    }

    /// Load the model and run it once off the caller's thread: the first prediction specialises it
    /// for the GPU / Neural Engine and takes 1–2 s, which must not land on the listening queue.
    public static func prepare() {
        guard lock.withLock({ if loading || cached != nil { return false }; loading = true; return true }) else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            let m = load(cpuOnly: false)
            if let m, let name = m.modelDescription.inputDescriptionsByName.keys.first,
               let arr = try? MLMultiArray(shape: [1, NSNumber(value: window), 1], dataType: .float32),
               let fp = try? MLDictionaryFeatureProvider(dictionary: [name: arr]) {
                autoreleasepool { _ = try? m.prediction(from: fp) }
            }
            lock.withLock { cached = m; loading = false }
        }
    }

    /// Nil when the model cannot be loaded (then the game uses NoteJudge alone). Uses the warmed
    /// model from `prepare` when there is one, else loads (and the first run is slow).
    public init?(sampleRate: Double, config: Config = Config()) {
        let warm = config.cpuOnly ? nil : Self.lock.withLock { Self.cached }
        guard let m = warm ?? Self.load(cpuOnly: config.cpuOnly),
              let name = m.modelDescription.inputDescriptionsByName.keys.first,
              let arr = try? MLMultiArray(shape: [1, NSNumber(value: Self.window), 1], dataType: .float32)
        else { return nil }
        model = m; inputName = name; input = arr
        self.config = config
        fs = sampleRate
        inFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)!
        outFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Self.rate, channels: 1, interleaved: false)!
        converter = sampleRate == Self.rate ? nil : AVAudioConverter(from: inFormat, to: outFormat)
        ring = [Float](repeating: 0, count: Self.window)
        onset = [Float](repeating: 0, count: config.keep * 88)
        note = onset
    }

    /// Feed mono samples at the rate given to `init`.
    public func process(_ x: [Float]) {
        guard let converter else { push(x); return }
        guard let inBuf = AVAudioPCMBuffer(pcmFormat: inFormat, frameCapacity: AVAudioFrameCount(x.count)) else { return }
        inBuf.frameLength = AVAudioFrameCount(x.count)
        x.withUnsafeBufferPointer { inBuf.floatChannelData![0].update(from: $0.baseAddress!, count: x.count) }
        let cap = AVAudioFrameCount(Double(x.count) * Self.rate / fs) + 64
        guard let outBuf = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: cap) else { return }
        var given = false
        converter.convert(to: outBuf, error: nil) { _, status in
            if given { status.pointee = .noDataNow; return nil }
            given = true; status.pointee = .haveData; return inBuf
        }
        push(Array(UnsafeBufferPointer(start: outBuf.floatChannelData![0], count: Int(outBuf.frameLength))))
    }

    private func push(_ y: [Float]) {
        let step = config.stride * Self.frameHop
        for v in y {
            ring[ringPos] = v
            ringPos = (ringPos + 1) % Self.window
            end += 1; sinceRun += 1
            // Each prediction hands back autoreleased, IOSurface-backed outputs: drain them every run,
            // or a long stream on one thread runs out of surfaces.
            if sinceRun >= step { sinceRun = 0; autoreleasepool { run() } }
        }
    }

    private func run() {
        let p = input.dataPointer.bindMemory(to: Float.self, capacity: Self.window)
        let tail = Self.window - ringPos
        ring.withUnsafeBufferPointer { r in
            (p).update(from: r.baseAddress! + ringPos, count: tail)
            (p + tail).update(from: r.baseAddress!, count: ringPos)
        }
        guard let fp = try? MLDictionaryFeatureProvider(dictionary: [inputName: input]),
              let out = try? model.prediction(from: fp),
              let on = out.featureValue(for: "Identity_2")?.multiArrayValue,
              let nt = out.featureValue(for: "Identity_1")?.multiArrayValue else { return }
        copyTail(on, into: &onset)
        copyTail(nt, into: &note)
        runEnd = Double(end) / Self.rate
    }

    private func copyTail(_ a: MLMultiArray, into dst: inout [Float]) {
        let frames = a.shape[1].intValue, s1 = a.strides[1].intValue, s2 = a.strides[2].intValue
        let k = config.keep
        if a.dataType == .float32 {
            let p = a.dataPointer.bindMemory(to: Float.self, capacity: a.count)
            for f in 0..<k { for q in 0..<88 { dst[f * 88 + q] = p[(frames - k + f) * s1 + q * s2] } }
        } else {
            for f in 0..<k { for q in 0..<88 { dst[f * 88 + q] = a[[0, NSNumber(value: frames - k + f), NSNumber(value: q)]].floatValue } }
        }
    }

    /// Time (seconds of input) of kept frame `f` of the newest run (calibrated on GuitarSet onsets).
    public func frameTime(_ f: Int) -> Double { runEnd - Double((config.keep - f + 1) * Self.frameHop) / Self.rate }

    /// In the newest run, does a frame old enough and later than `after` (seconds of input) reach
    /// `on` onset and `note` note posteriors for this pitch?
    public func heard(_ midi: Int, after: Double, on: Float? = nil, note noteMin: Float? = nil) -> Bool {
        let q = midi - 21
        guard (0..<88).contains(q), runEnd >= 0 else { return false }
        let o = on ?? config.onset, n = noteMin ?? config.note
        for f in 0..<max(0, config.keep - config.age) where frameTime(f) > after + config.slack {
            if onset[f * 88 + q] >= o && note[f * 88 + q] >= n { return true }
        }
        return false
    }
}
