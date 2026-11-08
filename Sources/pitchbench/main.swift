import AVFoundation
import Foundation
import NoteJudge

// pitchbench — score NoteJudge offline against a chart whose times match the audio.
//
//   pitchbench eval <audio> <chart.json> [key=value …]   right-note rate, latency, false accepts
//   pitchbench synth <chart.json> <out.wav> [rate] [offset] plucked-string render of a chart (test audio)
//   pitchbench suite <manifest.tsv> [key=value …] [--json out]  wait-mode replay of many takes (GuitarSet bench)
//
// key=value overrides NoteJudge.Config fields: rise contrast gate odd partial window.

func readMono(_ url: URL) throws -> ([Float], Double) {
    let file = try AVAudioFile(forReading: url)
    let fmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: file.processingFormat.sampleRate,
                            channels: file.processingFormat.channelCount, interleaved: false)!
    let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(file.length))!
    try file.read(into: buf)
    let n = Int(buf.frameLength), ch = Int(fmt.channelCount)
    var out = [Float](repeating: 0, count: n)
    for c in 0..<ch { let p = buf.floatChannelData![c]; for i in 0..<n { out[i] += p[i] / Float(ch) } }
    return (out, fmt.sampleRate)
}

/// For --live: NoteJudge.Config.hybrid with any key=value overrides (nil = the app's own choice).
nonisolated(unsafe) var liveConfig: NoteJudge.Config? = nil

func config(_ args: ArraySlice<String>, base: NoteJudge.Config = NoteJudge.Config()) -> NoteJudge.Config {
    var c = base
    for a in args {
        let kv = a.split(separator: "="); guard kv.count == 2, let v = Double(kv[1]) else { continue }
        switch kv[0] {
        case "rise": c.riseDB = Float(v)
        case "contrast": c.contrastDB = Float(v)
        case "gate": c.gateDB = Float(v)
        case "odd": c.oddDB = Float(v)
        case "unique": c.uniqueDB = Float(v)
        case "lowerrise": c.lowerRiseDB = Float(v)
        case "noiseover": c.noiseOver = Float(v)
        case "chordcontrast": c.chordContrastDB = Float(v)
        case "chordlow": c.chordLowDB = Float(v)
        case "window": c.windowSec = v
        case "risesec": c.riseSec = v
        case "low": c.lowDB = Float(v)
        case "difflag": c.diffLagSec = v
        case "share": c.shareDB = Float(v)
        case "repluck": c.repluckDB = Float(v)
        case "minrms": c.minRMSDB = Float(v)
        case "diffcontrast": c.diffContrastDB = Float(v)
        case "buried": c.buriedDB = Float(v)
        case "noiserise": c.noiseRiseDBps = Float(v)
        case "harmonics": c.harmonics = Int(v)
        case "hop": c.hopSec = v
        case "lowest": c.lowestNote = Int(v)
        case "repluckrise": c.repluckRiseDB = Float(v)
        case "chordrepluck": c.chordRepluckDB = Float(v)
        case "chordnotes": c.chordNotes = Int(v)
        case "skipmade": c.skipMade = v != 0
        case "chordvetooff": c.chordVetoOff = Int(v)
        default: break
        }
    }
    return c
}

func pct(_ a: Int, _ b: Int) -> String { b == 0 ? "-" : String(format: "%.1f%% (%d/%d)", 100 * Double(a) / Double(b), a, b) }
func median(_ x: [Double]) -> Double { x.isEmpty ? .nan : x.sorted()[x.count / 2] }
func p90(_ x: [Double]) -> Double { x.isEmpty ? .nan : x.sorted()[min(x.count - 1, Int(Double(x.count) * 0.9))] }

/// Lag (seconds) of `rec` behind `src`, from 10 ms energy-rise envelopes, searched over 0…maxLag.
func lag(_ rec: [Float], _ fr: Double, _ src: [Float], _ fs: Double, maxLag: Double = 5) -> Double {
    func env(_ x: [Float], _ r: Double) -> [Float] {
        let h = Int(r * 0.01); var e: [Float] = []; var prev: Float = 0
        for i in stride(from: 0, to: x.count - h, by: h) {
            var s: Float = 0; for j in i..<(i + h) { s += x[j] * x[j] }
            let l = log10(s / Float(h) + 1e-9); e.append(max(0, l - prev)); prev = l
        }
        return e
    }
    let a = env(rec, fr), b = env(src, fs)
    var best = (0, -Float.infinity)
    for L in 0..<min(Int(maxLag * 100), a.count) {
        var s: Float = 0
        for i in 0..<min(b.count, a.count - L) { s += a[i + L] * b[i] }
        if s > best.1 { best = (L, s) }
    }
    return Double(best.0) * 0.01
}

func eval(_ audio: URL, _ chartURL: URL, _ cfg: NoteJudge.Config, verbose: Bool) throws {
    var (x, fs) = try readMono(audio)
    var chart = try Chart(url: chartURL)
    // hum=<dB re the take's peak>: add 100 Hz mains hum with harmonics + hiss (a room like Daniel's).
    if let h = CommandLine.arguments.first(where: { $0.hasPrefix("hum=") }), let db = Double(h.dropFirst(4)) {
        let peak = x.map(abs).max() ?? 1, amp = Float(pow(10, db / 20)) * peak
        var rng = Seeded(seed: 3)
        for i in x.indices {
            let t = Double(i) / fs
            var v: Float = 0
            for (k, w) in [(1, 1.0), (2, 0.7), (3, 0.4), (4, 0.5), (6, 0.2)] { v += Float(w * sin(2 * .pi * 100 * Double(k) * t)) }
            x[i] += amp * v + amp * 0.3 * (Float(rng.next() % 2000) / 1000 - 1)
        }
    }
    if let i = CommandLine.arguments.firstIndex(of: "--align"), i + 1 < CommandLine.arguments.count {
        let (src, sr) = try readMono(URL(fileURLWithPath: CommandLine.arguments[i + 1]))
        let d = lag(x, fs, src, sr)
        print(String(format: "aligned: recording lags the source by %.2f s", d))
        for k in chart.steps.indices { chart.steps[k].time += d }
    }
    let judge = NoteJudge(sampleRate: fs, config: cfg)
    let steps = chart.steps
    let allPitches = Set(steps.flatMap { $0.pitches })
    let hopT = Double(judge.hopSize) / fs
    // Record, per hop, which of the queried notes are struck.
    var queried = allPitches
    for s in steps { for p in s.pitches { for d in [-2, -1, 1, 2, 12, 19, 24] { queried.insert(p + d) } } }
    var struckAt: [Int: [Int]] = [:]          // hop -> notes struck (since = 0 style: plain rise)
    var feats: [Int: [Int: [String: Float]]] = [:]   // hop -> note -> features (chart pitches only)
    judge.onHop = { h in
        if verbose { var f: [Int: [String: Float]] = [:]; for m in allPitches { f[m] = judge.features(m) }; feats[h] = f }
        if CommandLine.arguments.contains("-o") {
            for s in steps where abs(judge.time(ofHop: h) - s.time - 0.05) < 0.12 {
                for p in s.pitches { for d in [12, 19, 24] where !s.pitches.contains(p + d) && judge.struck(p + d) {
                    let v = judge.vetoInfo(p + d)[d] ?? []
                    print(String(format: "%6.2f  %@ played, %@ (+%d) fired; lower: own-now %.0f rise %.0f contrast %.0f", judge.time(ofHop: h),
                                 NoteJudge.name(p), NoteJudge.name(p + d), d, v[0], v[1], v[2]))
                } }
            }
        }
        var hits: [Int] = []
        for m in queried where judge.struck(m) { hits.append(m) }
        // Chord notes are judged with their chord, as the app does.
        for s in steps where s.pitches.count >= 3 && abs(judge.time(ofHop: h) - s.time - 0.1) < 0.2 {
            for m in s.required where !hits.contains(m) && judge.struck(m, allowing: s.pitches) { hits.append(m) }
        }
        if !hits.isEmpty { struckAt[h] = hits }
    }
    judge.process(x)

    func hops(_ a: Double, _ b: Double) -> [Int] {
        let lo = max(0, Int((a / hopT).rounded(.up))), hi = Int(b / hopT)
        return lo <= hi ? Array(lo...hi) : []
    }
    var wrongBy: [Int: Int] = [:], nearAdj = 0, part = 0, partN = 0
    var hit = 0, lat: [Double] = [], prem = 0, premN = 0, wrong = 0, wrongN = 0, near = 0, nearN = 0
    for (i, s) in steps.enumerated() {
        let end = min(s.time + 0.35, i + 1 < steps.count ? steps[i + 1].time - 0.02 : s.time + 0.35)
        var need = s.required, last: Int? = nil   // as the app judges: a big chord passes on its lowest + highest
        for h in hops(s.time - 0.06, end) {
            guard let got = struckAt[h] else { continue }
            for p in need where got.contains(p) { need.remove(p); last = h }
            if need.isEmpty { break }
        }
        let ok = need.isEmpty
        if ok { hit += 1; lat.append(judge.time(ofHop: last!) - s.time) }
        // Premature: while waiting for step i (after step i-1 sounded), does step i fire early?
        if i > 0 {
            premN += 1
            let early = hops(steps[i - 1].time + 0.03, s.time - 0.12)   // the chart's own timing is ±0.1 s
            if let h = early.first(where: { h in struckAt[h].map { !Set($0).isDisjoint(with: s.pitches) } ?? false }) {
                prem += 1
                if verbose { print(String(format: "        premature: %@ fired at %.2f (step at %.2f)", s.pitches.map(NoteJudge.name).joined(separator: "+"), judge.time(ofHop: h), s.time)) }
            }
        }
        let nearby = Set(steps.filter { abs($0.time - s.time) < 0.8 }.flatMap { $0.pitches })
        // Wrong notes: chart pitches not in this step (ignoring octaves of it), and ±1/±2 semitones.
        let win = hops(s.time - 0.06, end)
        let fired = Set(win.flatMap { struckAt[$0] ?? [] })
        // Only pitches not sounding nearby in the chart (so a ringing arpeggio note is not "wrong").
        for p in allPitches where !nearby.contains(p) && !s.pitches.contains(where: { abs($0 - p) % 12 == 0 }) {
            wrongN += 1; if fired.contains(p) { wrong += 1; wrongBy[(p - s.notes.map(\.midi).max()!), default: 0] += 1 }
        }
        // Upper partials: the octave, twelfth and two octaves above this step's notes.
        for p in s.pitches { for d in [12, 19, 24] where !s.pitches.contains(p + d) && !nearby.contains(p + d) {
            partN += 1; if fired.contains(p + d) { part += 1 }
        } }
        let adjacent = Set((max(0, i - 1)...min(steps.count - 1, i + 1)).flatMap { steps[$0].pitches })
        for p in s.pitches { for d in [-2, -1, 1, 2] where !s.pitches.contains(p + d) {
            nearN += 1
            if fired.contains(p + d) { near += 1; if adjacent.contains(p + d) { nearAdj += 1 } }
        } }
        if verbose {
            let names = s.notes.map { "\(NoteJudge.name($0.midi))(s\($0.string)f\($0.fret))" }.joined(separator: "+")
            let heard = Set(win.flatMap { struckAt[$0] ?? [] }).sorted().map(NoteJudge.name).joined(separator: " ")
            print(String(format: "%6.2f %@ %@  heard: %@", s.time, ok ? "✓" : "✗", names, heard))
            if !ok {
                // Best hop for each missing note (largest rise) and its features.
                for p in need {
                    let best = win.max { (feats[$0]?[p]?["rise"] ?? -99) < (feats[$1]?[p]?["rise"] ?? -99) }
                    if let b = best, let f = feats[b]?[p] {
                        print(String(format: "        %@ @%.2f gate %.0f rise %.0f contrast %.0f low %.0f odd %.0f", NoteJudge.name(p), judge.time(ofHop: b),
                                     f["gate"]!, f["rise"]!, f["contrast"]!, f["low"]!, f["odd"]!))
                    }
                }
            }
        }
    }
    if CommandLine.arguments.contains("-q") {
        print(String(format: "hit %.1f%%  lat %.0f/%.0f ms  premature %.1f%%  wrong %.1f%%  near %.1f%% (%d of %d adj)  overtone %.1f%%", 100 * Double(hit) / Double(steps.count),
                     median(lat) * 1000, p90(lat) * 1000, 100 * Double(prem) / Double(max(1, premN)), 100 * Double(wrong) / Double(max(1, wrongN)), 100 * Double(near) / Double(max(1, nearN)), nearAdj, near, 100 * Double(part) / Double(max(1, partN))))
        return
    }
    print("audio \(audio.lastPathComponent)  \(String(format: "%.0f", fs)) Hz  window \(judge.windowSize)  hop \(String(format: "%.1f", hopT * 1000)) ms")
    print("steps \(steps.count)")
    print("right note heard      \(pct(hit, steps.count))")
    print(String(format: "latency after onset   median %.0f ms, p90 %.0f ms (analysis only; add the audio buffer)", median(lat) * 1000, p90(lat) * 1000))
    print("premature accept      \(pct(prem, premN))   (waiting for the next step, it fired before it was played)")
    print("wrong chart note      \(pct(wrong, wrongN))   (another chart pitch fired during this step)")
    print("  by interval to the step's top note: " + wrongBy.sorted { $0.value > $1.value }.prefix(8).map { "\($0.key > 0 ? "+" : "")\($0.key):\($0.value)" }.joined(separator: " "))
    print("±1–2 semitones        \(pct(near, nearN))")
}

// MARK: suite — the app's wait-mode judging, replayed over many takes

/// What the wait-mode replay listens with: the DSP judge, or a model's streamed posteriors.
protocol Ear: AnyObject {
    var onHop: ((Int) -> Void)? { get set }
    func time(ofHop h: Int) -> Double
    func struck(_ midi: Int, since: Int, allowing: Set<Int>) -> Bool
    /// How far the note got through the judge's tests (higher = further); nil when not a NoteJudge.
    func reached(_ midi: Int, since: Int, allowing: Set<Int>) -> Int?
    func run()
}

final class JudgeEar: Ear {
    let judge: NoteJudge, x: [Float]
    init(_ x: [Float], _ fs: Double, _ cfg: NoteJudge.Config) { judge = NoteJudge(sampleRate: fs, config: cfg); self.x = x }
    var onHop: ((Int) -> Void)? { get { judge.onHop } set { judge.onHop = newValue } }
    func time(ofHop h: Int) -> Double { judge.time(ofHop: h) }
    func struck(_ midi: Int, since: Int, allowing: Set<Int>) -> Bool { judge.struck(midi, since: since, allowing: allowing) }
    func reached(_ midi: Int, since: Int, allowing: Set<Int>) -> Int? { judge.verdict(midi, since: since, allowing: allowing).rawValue }
    func run() { judge.process(x) }
}

/// Basic Pitch run as a stream (tools/basicpitch-bench.py): every `stride` samples at 22.05 kHz
/// the model saw the last 2 s and we kept its newest `k` frames of onset and note posteriors.
/// A note is struck when, in the newest window, a frame after the step was armed (and at least
/// `age` frames old) has an onset
/// posterior ≥ `on` and a note posterior ≥ `note`. File: int32 n, k, 88, stride; n×int32 window
/// end (samples); then n×k×88 float16 onset, the same for note.
final class PosteriorEar: Ear {
    let n: Int, k: Int, ends: [Int32], onset: [Float16], note: [Float16]
    let on: Float16, noteMin: Float16, age: Int
    var onHop: ((Int) -> Void)?
    static let sr = 22050.0, frameHop = 256
    /// A frame counts for a step only when it is this much later than the moment the step was armed.
    nonisolated(unsafe) static var slack = -0.03
    init(_ url: URL, on: Double, note: Double, age: Int) throws {
        let d = try Data(contentsOf: url)
        let head = d.withUnsafeBytes { Array($0.bindMemory(to: Int32.self).prefix(4)) }
        let n = Int(head[0]), k = Int(head[1])
        self.n = n; self.k = k
        let ne = 16, per = n * k * 88
        ends = d.withUnsafeBytes { Array($0.bindMemory(to: Int32.self)[4..<(4 + n)]) }
        let base = ne + 4 * n
        onset = d.subdata(in: base..<(base + 2 * per)).withUnsafeBytes { Array($0.bindMemory(to: Float16.self)) }
        self.note = d.subdata(in: (base + 2 * per)..<(base + 4 * per)).withUnsafeBytes { Array($0.bindMemory(to: Float16.self)) }
        self.on = Float16(on); noteMin = Float16(note); self.age = age
    }
    func time(ofHop h: Int) -> Double { Double(ends[min(h, n - 1)]) / Self.sr }
    var cur = 0
    func struck(_ midi: Int, since: Int, allowing: Set<Int>) -> Bool {
        heard(midi, row: cur, after: time(ofHop: since), on: on, note: noteMin)
    }
    /// In window `row`, does a frame old enough and later than `after` reach both thresholds?
    func heard(_ midi: Int, row cur: Int, after armed: Double, on: Float16, note noteMin: Float16) -> Bool {
        let p = midi - 21
        guard (0..<88).contains(p), cur >= 0 else { return false }
        // Only frames with `age` frames of audio after them: younger ones have not seen the attack
        // yet and their onset posterior is noise (it peaks once 4-5 frames, ~50 ms, follow).
        for f in 0..<max(0, k - age) {
            // Frame f of the newest k: its time is the window end minus (k - f + 1) frames (calibrated on GuitarSet onsets).
            let ft = time(ofHop: cur) - Double((k - f + 1) * Self.frameHop) / Self.sr
            guard ft > armed + PosteriorEar.slack else { continue }
            let o = (cur * k + f) * 88 + p
            if onset[o] >= on && note[o] >= noteMin { return true }
        }
        return false
    }
    func reached(_ midi: Int, since: Int, allowing: Set<Int>) -> Int? { nil }
    func run() { for h in 0..<n { cur = h; onHop?(h) } }
}


/// NoteJudge and Basic Pitch together, both streamed: Basic Pitch's note posterior says which
/// pitches sound (it rarely mistakes the fret), an onset from either says a new pluck happened.
/// mode 1: BP note ∧ (BP onset ∨ the judge's onset test passed); 2: the judge's verdict ∨ BP alone;
/// 3: BP note ∧ the judge's onset test passed.
final class HybridEar: Ear {
    let dsp: JudgeEar, bp: PosteriorEar, mode: Int, onLow: Float16
    var row = -1
    init(_ dsp: JudgeEar, _ bp: PosteriorEar, mode: Int, onLow: Double) { self.dsp = dsp; self.bp = bp; self.mode = mode; self.onLow = Float16(onLow) }
    var onHop: ((Int) -> Void)?
    func time(ofHop h: Int) -> Double { dsp.time(ofHop: h) }
    func struck(_ midi: Int, since: Int, allowing: Set<Int>) -> Bool {
        let armed = time(ofHop: since)
        switch mode {
        case 2:
            return dsp.struck(midi, since: since, allowing: allowing) || bp.heard(midi, row: row, after: armed, on: bp.on, note: bp.noteMin)
        case 3:
            guard bp.heard(midi, row: row, after: armed, on: 0, note: bp.noteMin) else { return false }
            return dsp.judge.verdict(midi, since: since, allowing: allowing).rawValue > NoteJudge.Verdict.onset.rawValue
        case 4, 5, 6:
            // 4: mode 1, and not an overtone of a lower note just plucked (NoteJudge's veto);
            // 5: the same, the veto only for steps of one note; 6: mode 5 and NoteJudge's level
            // gates (as Hearing: Basic Pitch hallucinates notes in silence).
            guard bp.heard(midi, row: row, after: armed, on: 0, note: bp.noteMin) else { return false }
            let v = dsp.judge.verdict(midi, since: since, allowing: allowing).rawValue
            if mode == 6 && v < NoteJudge.Verdict.onset.rawValue { return false }
            guard bp.heard(midi, row: row, after: armed, on: onLow, note: 0) || v > NoteJudge.Verdict.onset.rawValue else { return false }
            return (mode >= 5 && allowing.count > 1) || !dsp.judge.overtone(midi, since: since, allowing: allowing)
        default:
            guard bp.heard(midi, row: row, after: armed, on: 0, note: bp.noteMin) else { return false }
            return bp.heard(midi, row: row, after: armed, on: onLow, note: 0)
                || dsp.judge.verdict(midi, since: since, allowing: allowing).rawValue > NoteJudge.Verdict.onset.rawValue
        }
    }
    func reached(_ midi: Int, since: Int, allowing: Set<Int>) -> Int? { nil }
    func run() {
        dsp.onHop = { [unowned self] h in
            let t = Int(self.time(ofHop: h) * PosteriorEar.sr)
            while row + 1 < bp.n && Int(bp.ends[row + 1]) <= t { row += 1 }
            onHop?(h)
        }
        dsp.run()
    }
}

/// The app's own `Hearing` (NoteJudge + streamed Basic Pitch in Swift), fed 512-sample buffers like the mic tap.
final class HearingEar: Ear {
    let ears: Hearing, x: [Float]
    init(_ x: [Float], _ fs: Double, _ cfg: NoteJudge.Config?, _ m: NoteModel.Config?) { ears = Hearing(sampleRate: fs, config: cfg, model: m); self.x = x }
    var onHop: ((Int) -> Void)? { get { ears.onHop } set { ears.onHop = newValue } }
    func time(ofHop h: Int) -> Double { ears.time(ofHop: h) }
    func struck(_ midi: Int, since: Int, allowing: Set<Int>) -> Bool { ears.struck(midi, since: since, allowing: allowing) }
    func reached(_ midi: Int, since: Int, allowing: Set<Int>) -> Int? { nil }
    func run() { for i in stride(from: 0, to: x.count, by: 512) { ears.process(Array(x[i..<min(x.count, i + 512)])) } }
}

/// One step of a take as the game would have judged it.
struct StepResult {
    var kind: Int            // 1 single note, 2 dyad, 3 chord of 3+
    var gap: Double          // seconds since the previous step started
    var hit: Bool            // passed before the next step started (or 0.35 s)
    var latency: Double      // judge hop end minus the annotated onset (hits only)
    var premature: Bool      // passed before its own note was played (a ringing note, an overtone, noise)
    var decoys: [Int: Bool]  // shift -> a step transposed by this many semitones would also have passed
    var carried = false      // a required note was also in the step before (re-plucked while ringing)
    var stuck: [Int] = []    // missed steps: per required note not heard, the furthest test it reached (NoteJudge.Verdict)
}

let decoyShifts = [-1, 1, -12, 12]

/// Replay a take through the judge exactly as Listener + Game judge a step in wait mode, with a
/// player who keeps the take's own timing. A step is armed when the last one passed (or was
/// missed); its required notes must each be struck after that, with the step's notes allowed to
/// share harmonics. Passing more than 0.6 s early is ignored (the game's lookahead). A step not
/// passed by the next one's onset (at most 0.35 s after its own) counts as missed and the game
/// moves on. Decoys: the same step shifted by ±1 semitone and ±1 octave, judged alongside; a decoy
/// that passes is a false accept (skipped when the shifted notes are really sounding nearby, or
/// fall outside a standard-tuned guitar's E2…E6, as GuitarSet is).
let diagnose = CommandLine.arguments.contains("--why")
let trace = CommandLine.arguments.contains("--trace")
let holdoff = CommandLine.arguments.first { $0.hasPrefix("holdoff=") }.flatMap { Double($0.dropFirst(8)) } ?? 0

func simulate(_ judge: Ear, _ chart: Chart) -> [StepResult] {
    let steps = chart.steps
    guard !steps.isEmpty else { return [] }
    let tol = 0.03                                     // annotation onsets are good to a few ms; allow the hop
    func deadline(_ i: Int) -> Double {
        let t = steps[i].time
        return i + 1 < steps.count ? max(t + 0.06, min(t + 0.35, steps[i + 1].time)) : t + 0.35
    }
    var out: [StepResult] = []
    var i = 0, since = 0, got = Set<Int>(), far: [Int: Int] = [:]
    var decoy: [(shift: Int, req: Set<Int>, all: Set<Int>, got: Set<Int>, fired: Bool)] = []
    func arm(_ h: Int) {
        since = h; got = []; far = [:]
        decoy = []
        guard i < steps.count else { return }
        let s = steps[i], d = deadline(i)
        let sounding = Set(steps.filter { $0.time > s.time - 1.5 && $0.time < d + 0.1 }.flatMap { $0.pitches })
        for sh in decoyShifts {
            let req = Set(s.required.map { $0 + sh }), all = Set(s.pitches.map { $0 + sh })
            if !req.isDisjoint(with: sounding) || all.contains(where: { $0 < 40 || $0 > 88 }) { continue }   // unplayable in standard tuning
            decoy.append((sh, req, all, [], false))
        }
    }
    func close(hit: Bool, at t: Double) {
        let s = steps[i]
        if trace, hit, t < s.time - 0.1, i > 0, !s.required.isDisjoint(with: steps[i - 1].pitches) {
            print(String(format: "TRACE %@ step %.3f hit %.3f prev %.3f armed %.3f %@", chart.title, s.time, t, steps[i - 1].time,
                         judge.time(ofHop: since), s.pitches.sorted().map(NoteJudge.name).joined(separator: "+")))
        }
        let k = min(3, s.pitches.count)
        var d: [Int: Bool] = [:]
        for e in decoy { d[e.shift] = e.fired }
        out.append(StepResult(kind: k, gap: i > 0 ? s.time - steps[i - 1].time : 9, hit: hit,
                              latency: hit ? t - s.time : .nan, premature: hit && t < s.time - tol, decoys: d,
                              carried: i > 0 && !s.required.isDisjoint(with: steps[i - 1].pitches),
                              stuck: hit ? [] : s.required.subtracting(got).map { far[$0] ?? 0 }))
        i += 1
    }
    arm(0)
    judge.onHop = { h in
        let t = judge.time(ofHop: h)
        while i < steps.count && t > deadline(i) { close(hit: false, at: t); arm(h) }
        guard i < steps.count else { return }
        let s = steps[i]
        if t > s.time - 0.6 {
            for k in decoy.indices where !decoy[k].fired {
                for p in decoy[k].req.subtracting(decoy[k].got) where !(holdoff > 0 && i > 0 && Double(h - since) * judge.time(ofHop: 1) < holdoff && steps[i - 1].pitches.contains(p)) && judge.struck(p, since: since, allowing: decoy[k].all) { decoy[k].got.insert(p) }
                if decoy[k].got.isSuperset(of: decoy[k].req) { decoy[k].fired = true }
            }
        }
        // A pitch the last step had is still in its own attack for one analysis window after that
        // step passed: it cannot count again until then (as the app's Listener does).
        let settling = holdoff > 0 && i > 0 && Double(h - since) * judge.time(ofHop: 1) < holdoff ? steps[i - 1].pitches : []
        for p in s.required.subtracting(got) where !settling.contains(p) {
            if diagnose, t > s.time - 0.03, let r = judge.reached(p, since: since, allowing: s.pitches) {
                far[p] = max(far[p] ?? 0, r)
                if r == NoteJudge.Verdict.struck.rawValue { got.insert(p) }
            } else if judge.struck(p, since: since, allowing: s.pitches) { got.insert(p) }
        }
        guard got.isSuperset(of: s.required) else { return }
        if t < s.time - 0.6 { since = h; got = []; return }   // too early to be this note: the game re-arms
        close(hit: true, at: t)
        arm(h)
    }
    judge.run()
    while i < steps.count { close(hit: false, at: .infinity) }
    return out
}

/// `pitchbench suite <manifest.tsv> [key=value …] [--json out.json]`: every take in the
/// manifest (lines: wav, chart, tag) through `simulate`, in parallel; totals per step kind.
func suite(_ manifest: URL, _ cfg: NoteJudge.Config, json: URL?, post: URL? = nil, postOn: Double = 0.5, postNote: Double = 0.3, postAge: Int = 4, hybrid: Int = 0, hybridOn: Double = 0.3) throws {
    let rows = try String(contentsOf: manifest, encoding: .utf8).split(separator: "\n")
        .map { $0.split(separator: "\t").map(String.init) }.filter { $0.count >= 2 && !$0[0].hasPrefix("#") }
    var results = [[StepResult]](repeating: [], count: rows.count)
    let tags = rows.map { $0.count > 2 ? $0[2] : "" }
    let lock = NSLock()
    // CoreML runs share the GPU/ANE: a few takes at a time, or IOSurface allocation fails.
    let gate = DispatchSemaphore(value: CommandLine.arguments.contains("--live") ? 3 : 64)
    DispatchQueue.concurrentPerform(iterations: rows.count) { n in
        gate.wait(); defer { gate.signal() }
        guard let chart = try? Chart(url: URL(fileURLWithPath: rows[n][1])) else { return }
        let ear: Ear
        if let dir = post {
            let name = URL(fileURLWithPath: rows[n][0]).deletingPathExtension().lastPathComponent
            guard let e = try? PosteriorEar(dir.appendingPathComponent(name + ".bp"), on: postOn, note: postNote, age: postAge) else { return }
            if hybrid > 0 {
                guard let (x, fs) = try? readMono(URL(fileURLWithPath: rows[n][0])) else { return }
                ear = HybridEar(JudgeEar(x, fs, cfg), e, mode: hybrid, onLow: hybridOn)
            } else { ear = e }
        } else {
            guard let (x, fs) = try? readMono(URL(fileURLWithPath: rows[n][0])) else { return }
            if CommandLine.arguments.contains("--live") {
                // The app's defaults (NoteModel.Config, NoteJudge.Config.hybrid) unless overridden here.
                var m = NoteModel.Config()
                let given = { (k: String) in CommandLine.arguments.contains { $0.hasPrefix(k + "=") } }
                if given("on") { m.onset = Float(postOn) }
                if given("note") { m.note = Float(postNote) }
                if given("age") { m.age = postAge }
                if given("slack") { m.slack = PosteriorEar.slack }
                ear = HearingEar(x, fs, liveConfig, m)
            } else { ear = JudgeEar(x, fs, cfg) }
        }
        let r = simulate(ear, chart)
        lock.lock(); results[n] = r; lock.unlock()
    }
    var report: [String: [String: Double]] = [:]
    func line(_ name: String, _ r: [StepResult]) {
        let hits = r.filter(\.hit), lat = hits.map(\.latency).filter { $0.isFinite }
        var m: [String: Double] = ["n": Double(r.count), "hit": frac(hits.count, r.count),
                                   "lat_med": median(lat) * 1000, "lat_p90": p90(lat) * 1000,
                                   "premature": frac(r.filter(\.premature).count, r.count),
                                   // How early: just before the annotated onset (annotation lag) or well before (a real false pass).
                                   "early100": frac(r.filter { $0.hit && $0.latency < -0.1 }.count, r.count)]
        for sh in decoyShifts {
            let d = r.compactMap { $0.decoys[sh] }
            m["decoy\(sh > 0 ? "+" : "")\(sh)"] = frac(d.filter { $0 }.count, d.count)
        }
        report[name] = m
        if diagnose {
            var why = [Int](repeating: 0, count: NoteJudge.Verdict.allCases.count)
            for x in r { for v in x.stuck { why[v] += 1 } }
            let tot = max(1, why.reduce(0, +))
            print("    missed notes stopped at: " + NoteJudge.Verdict.allCases.filter { why[$0.rawValue] > 0 }
                .map { "\($0)(\(100 * why[$0.rawValue] / tot)%)" }.joined(separator: " "))
        }
        print(name.padding(toLength: 12, withPad: " ", startingAt: 0) + String(format: " n %5d  hit %5.1f%%  lat %3.0f/%3.0f ms  premature %4.1f%% (>100 ms %4.1f%%)  false accept −1 %4.1f%% +1 %4.1f%% −12 %4.1f%% +12 %4.1f%%",
                     r.count, 100 * m["hit"]!, m["lat_med"]!, m["lat_p90"]!, 100 * m["premature"]!, 100 * m["early100"]!,
                     100 * m["decoy-1"]!, 100 * m["decoy+1"]!, 100 * m["decoy-12"]!, 100 * m["decoy+12"]!))
    }
    let all = results.flatMap { $0 }
    // Steps right after another (<0.2 s) are a passage played fast; wait mode is played slower.
    let slow = all.filter { $0.gap >= 0.2 }
    line("all", all)
    line("single", slow.filter { $0.kind == 1 })
    line("dyad", slow.filter { $0.kind == 2 })
    line("chord", slow.filter { $0.kind == 3 })
    line("fast(<0.2s)", all.filter { $0.gap < 0.2 })
    if diagnose {
        line("chord fresh", slow.filter { $0.kind == 3 && !$0.carried })
        line("chord again", slow.filter { $0.kind == 3 && $0.carried })
        line("single again", slow.filter { $0.kind == 1 && $0.carried })
    }
    for t in Set(tags).sorted() where !t.isEmpty {
        line(t, zip(tags, results).filter { $0.0 == t }.flatMap { $0.1 }.filter { $0.gap >= 0.2 })
    }
    if let json {
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: json)
    }
}

func frac(_ a: Int, _ b: Int) -> Double { b == 0 ? .nan : Double(a) / Double(b) }

struct Seeded: RandomNumberGenerator {
    var seed: UInt64
    mutating func next() -> UInt64 { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return seed }
}

func synth(_ chartURL: URL, _ out: URL, rate: Double, offset: Double) throws {
    let chart = try Chart(url: chartURL)
    let n = Int((chart.duration + offset + 2) * rate)
    var y = [Float](repeating: 0, count: n)
    var rng = Seeded(seed: 7)   // same pluck noise every run: tests stay deterministic
    for s in chart.steps { for note in s.notes {
        let f = NoteJudge.hz(note.midi); let period = max(2, Int(rate / f))
        var buf = (0..<period).map { _ in Float.random(in: -1...1, using: &rng) }
        let start = Int((s.time + offset) * rate), len = min(n - start, Int(rate * 1.2))
        guard len > 0 else { continue }
        for i in 0..<len {
            let j = i % period
            y[start + i] += buf[j] * 0.3
            buf[j] = 0.996 * 0.5 * (buf[j] + buf[(j + 1) % period])
        }
    } }
    let fmt = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
    let pcm = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(n))!
    pcm.frameLength = AVAudioFrameCount(n)
    let peak = max(0.001, y.map(abs).max()!)
    for i in 0..<n { pcm.floatChannelData![0][i] = y[i] / peak * 0.8 }
    let file = try AVAudioFile(forWriting: out, settings: fmt.settings)
    try file.write(from: pcm)
}

let a = CommandLine.arguments
do {
    switch a.count > 1 ? a[1] : "" {
    case "eval" where a.count >= 4:
        try eval(URL(fileURLWithPath: a[2]), URL(fileURLWithPath: a[3]), config(a[4...]), verbose: a.contains("-v"))
    case "suite" where a.count >= 3:
        let j = a.firstIndex(of: "--json").flatMap { $0 + 1 < a.count ? URL(fileURLWithPath: a[$0 + 1]) : nil }
        // --post <dir> [on=0.5 note=0.3]: judge with Basic Pitch posteriors instead of NoteJudge.
        PosteriorEar.slack = a.first { $0.hasPrefix("slack=") }.flatMap { Double($0.dropFirst(6)) } ?? -0.03
        let post = a.firstIndex(of: "--post").flatMap { $0 + 1 < a.count ? URL(fileURLWithPath: a[$0 + 1]) : nil }
        func kv(_ k: String, _ d: Double) -> Double { a.first { $0.hasPrefix(k + "=") }.flatMap { Double($0.dropFirst(k.count + 1)) } ?? d }
        if a.contains("--live") { let h = config(a[3...], base: .hybrid); liveConfig = h }
        try suite(URL(fileURLWithPath: a[2]), config(a[3...]), json: j, post: post, postOn: kv("on", 0.5), postNote: kv("note", 0.3), postAge: Int(kv("age", 4)),
                  hybrid: Int(kv("mode", 0)), hybridOn: kv("onlow", 0.3))
    case "probe" where a.count >= 7:
        // pitchbench probe <wav> <midi> <from s> <to s> <armed s> [key=value …]: one note hop by hop.
        let (x, fs) = try readMono(URL(fileURLWithPath: a[2]))
        let m = Int(a[3])!, t0 = Double(a[4])!, t1 = Double(a[5])!, ta = Double(a[6])!
        let j = NoteJudge(sampleRate: fs, config: config(a[7...]))
        var since = 0
        j.onHop = { h in
            let t = j.time(ofHop: h)
            if t < ta { since = h }
            guard t >= t0 && t <= t1 else { return }
            let f = j.features(m)
            print(String(format: "%.3f lvl %6.1f rms %6.1f rise %5.1f contrast %5.1f low %5.1f odd %5.1f  %@", t, j.level(m), j.rmsDB,
                         f["rise"]!, f["contrast"]!, f["low"]!, f["odd"]!, "\(j.verdict(m, since: since))"))
        }
        j.process(x)
    case "tabchart" where a.count >= 3:
        // Print the chart read from a .tab file's staves (checks the parser on real tabs).
        let text = try String(contentsOfFile: a[2], encoding: .utf8)
        func meta(_ k: String) -> String? {
            text.components(separatedBy: "\n").first { $0.hasPrefix(k + ":") }.map { String($0.dropFirst(k.count + 1)).trimmingCharacters(in: .whitespaces) }
        }
        guard let c = Chart.fromTab(text, title: meta("title") ?? "", artist: meta("artist") ?? "", tuning: meta("tuning"), capo: Int(meta("capo") ?? "") ?? 0)
        else { print("no staves"); exit(1) }
        if let j = a.firstIndex(of: "--json"), j + 1 < a.count {
            // Untimed chart for tools/align-chart.py: times are only the tab's column spacing.
            let notes = c.steps.flatMap { s in s.notes.map { ["t": s.time, "string": $0.string, "fret": $0.fret, "midi": $0.midi] as [String: Any] } }
            let obj: [String: Any] = ["title": c.title, "artist": c.artist, "timing": "tab columns", "notes": notes]
            try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted]).write(to: URL(fileURLWithPath: a[j + 1]))
        }
        print("\(c.steps.count) steps, \(String(format: "%.0f", c.duration)) s")
        for s in c.steps.prefix(a.count > 3 ? Int(a[3]) ?? 16 : 16) {
            print(String(format: "%6.2f  ", s.time) + s.notes.map { "s\($0.string)f\($0.fret)=\(NoteJudge.name($0.midi))" }.joined(separator: " "))
        }
    case "synth" where a.count >= 4:
        try synth(URL(fileURLWithPath: a[2]), URL(fileURLWithPath: a[3]), rate: a.count > 4 ? Double(a[4]) ?? 44100 : 44100,
                  offset: a.count > 5 ? Double(a[5]) ?? 0 : 0)
    default:
        print("usage: pitchbench eval <audio> <chart.json> [-v] [rise=7 contrast=4 gate=22 odd=-14 partial=4 window=0.085]\n       pitchbench synth <chart.json> <out.wav> [rate] [offset seconds]")
        exit(2)
    }
} catch { print("error: \(error)"); exit(1) }
