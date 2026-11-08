import AVFoundation
import Foundation
import NoteJudge

// pitchbench — score NoteJudge offline against a chart whose times match the audio.
//
//   pitchbench eval <audio> <chart.json> [key=value …]   right-note rate, latency, false accepts
//   pitchbench synth <chart.json> <out.wav> [rate] [offset] plucked-string render of a chart (test audio)
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

func config(_ args: ArraySlice<String>) -> NoteJudge.Config {
    var c = NoteJudge.Config()
    for a in args {
        let kv = a.split(separator: "="); guard kv.count == 2, let v = Double(kv[1]) else { continue }
        switch kv[0] {
        case "rise": c.riseDB = Float(v)
        case "contrast": c.contrastDB = Float(v)
        case "gate": c.gateDB = Float(v)
        case "odd": c.oddDB = Float(v)
        case "unique": c.uniqueDB = Float(v)
        case "lowerrise": c.lowerRiseDB = Float(v)
        case "window": c.windowSec = v
        case "risesec": c.riseSec = v
        case "low": c.lowDB = Float(v)
        case "difflag": c.diffLagSec = v
        case "share": c.shareDB = Float(v)
        case "repluck": c.repluckDB = Float(v)
        case "minrms": c.minRMSDB = Float(v)
        case "diffcontrast": c.diffContrastDB = Float(v)
        case "buried": c.buriedDB = Float(v)
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
    let (x, fs) = try readMono(audio)
    var chart = try Chart(url: chartURL)
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
        var need = s.pitches, last: Int? = nil
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
    case "tabchart" where a.count >= 3:
        // Print the chart read from a .tab file's staves (checks the parser on real tabs).
        let text = try String(contentsOfFile: a[2], encoding: .utf8)
        func meta(_ k: String) -> String? {
            text.components(separatedBy: "\n").first { $0.hasPrefix(k + ":") }.map { String($0.dropFirst(k.count + 1)).trimmingCharacters(in: .whitespaces) }
        }
        guard let c = Chart.fromTab(text, title: meta("title") ?? "", artist: meta("artist") ?? "", tuning: meta("tuning"), capo: Int(meta("capo") ?? "") ?? 0)
        else { print("no staves"); exit(1) }
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
