import Accelerate
import Foundation

/// Hears whether an *expected* note was just played. It does not track pitch open-endedly:
/// each hop it measures the energy at every candidate note's fundamental and harmonics, and a
/// note counts as struck when that energy jumps (an onset), stands clear of the neighbouring
/// semitones, and is not just an upper partial of a lower note that was struck with it.
///
/// Feed mono samples at any rate with `process`; `onHop` fires after each analysis hop, and
/// `struck(_:)` answers for the newest hop. Pure DSP, no audio I/O, so the bench and the tests
/// run it on files.
public final class NoteJudge {
    public struct Config {
        public var lowMidi = 36            // C2: below drop-D
        public var highMidi = 91           // G6: 24th fret on the high e plus a little
        public var harmonics = 8
        public var windowSec = 0.085
        public var hopSec = 0.0107
        public var riseDB: Float = 7       // jump over the note's own recent minimum
        public var riseSec = 0.12          // how far back that minimum looks
        public var contrastDB: Float = 5   // above both neighbouring semitones
        public var gateDB: Float = 22      // above the noise floor
        public var oddDB: Float = -14      // odd harmonics vs even ones (rejects "an octave too low")
        public var partialDB: Float = 4    // a lower note this close in level explains this one away
        public var diffContrastDB: Float = 11  // …and clear of the neighbours in the new energy by this
        public var buriedDB: Float = 6     // …while at most this far under the ringing neighbour
        public var diffLagSec = 0.08       // "new energy" = this spectrum minus the one this long ago
        public var lowDB: Float = 8        // harmonic 1 or 2 within this of the strongest (rejects ghosts below)
        public init() {}
    }

    public let fs: Double
    public let config: Config
    public let windowSize: Int
    public let hopSize: Int
    /// Number of completed hops; hop `h` analysed the samples ending at `h * hopSize`.
    public private(set) var hop = 0
    public private(set) var samples = 0
    public var onHop: ((Int) -> Void)?
    /// Input level of the newest window, dBFS (RMS).
    public private(set) var rmsDB: Float = -120
    /// Slowly tracked noise floor of the note levels, dB.
    public private(set) var floorDB: Float = -200

    let nfft: Int
    let log2n: vDSP_Length
    let fft: FFTSetup
    var ring: [Float]
    var ringPos = 0
    var sinceHop = 0
    let window: [Float]
    var frame: [Float]
    var power: [Float]
    var re: [Float], im: [Float]
    /// For each candidate note and harmonic, the bin range to take the peak from.
    var bins: [[(Int, Int)]] = []
    var weights: [Float] = []
    /// History of note levels (dB): `hist[h % depth][noteIndex]`.
    let depth: Int
    var hist: [[Float]]
    var oddHist: [[Float]]
    var evenHist: [[Float]]
    /// Strongest of harmonics 1–2 minus the strongest harmonic, dB (0 = the bottom leads).
    var lowHist: [[Float]]
    /// Level from only the harmonics far enough from the next semitone's to be told apart.
    var sharpHist: [[Float]]
    /// Resolved-harmonic level of the energy that is new since `diffLagSec` ago.
    var newRow: [Float] = []
    var pastPower: [[Float]] = []
    var pastPos = 0
    /// Per note, which harmonics are resolved from the semitone neighbours.
    var resolved: [[Bool]] = []

    public var notes: ClosedRange<Int> { config.lowMidi...config.highMidi }

    public init(sampleRate: Double, config: Config = Config()) {
        fs = sampleRate
        self.config = config
        var n = 1; while Double(n) < sampleRate * config.windowSec { n <<= 1 }
        windowSize = n
        hopSize = max(64, Int(sampleRate * config.hopSec))
        nfft = n * 4                                         // zero-padded: fine sampling of the spectrum
        log2n = vDSP_Length(log2(Double(nfft)))
        fft = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
        ring = [Float](repeating: 0, count: n)
        window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: n, isHalfWindow: false)
        frame = [Float](repeating: 0, count: nfft)
        power = [Float](repeating: 0, count: nfft / 2)
        re = [Float](repeating: 0, count: nfft / 2)
        im = [Float](repeating: 0, count: nfft / 2)
        let count = config.highMidi - config.lowMidi + 1
        depth = max(4, Int((config.riseSec + 0.1) / (Double(hopSize) / sampleRate)) + 2)
        hist = Array(repeating: Array(repeating: -200, count: count), count: depth)
        oddHist = hist; evenHist = hist; lowHist = hist; sharpHist = hist
        let nyq = sampleRate / 2 * 0.95
        for m in config.lowMidi...config.highMidi {
            let f0 = NoteJudge.hz(m)
            var row: [(Int, Int)] = []
            for h in 1...config.harmonics {
                let f = f0 * Double(h)
                if f > nyq { row.append((-1, -1)); continue }
                let b = f * Double(nfft) / sampleRate
                let lo = Int((b * 0.988).rounded(.down)), hi = Int((b * 1.012).rounded(.up))
                row.append((max(1, lo), min(nfft / 2 - 1, max(lo, hi))))
            }
            bins.append(row)
        }
        // Hann main lobe is ±2 bins of the unpadded window; a harmonic is resolved when the
        // semitone neighbour's matching harmonic sits beyond that.
        let lobe = 2 * sampleRate / Double(n)
        resolved = (config.lowMidi...config.highMidi).map { m in
            let f0 = NoteJudge.hz(m)
            return (1...config.harmonics).map { h in Double(h) * f0 * (pow(2, 1.0 / 12) - 1) * 0.97 > lobe }
        }
        let lagHops = max(1, Int(config.diffLagSec / (Double(hopSize) / sampleRate)))
        pastPower = Array(repeating: [Float](repeating: 0, count: nfft / 2), count: lagHops)
        newRow = [Float](repeating: -200, count: count)
        weights = (1...config.harmonics).map { Float(pow(0.85, Double($0 - 1))) }
    }

    deinit { vDSP_destroy_fftsetup(fft) }

    public static func hz(_ midi: Int) -> Double { 440 * pow(2, Double(midi - 69) / 12) }
    public static func name(_ midi: Int) -> String {
        ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"][((midi % 12) + 12) % 12] + "\(midi / 12 - 1)"
    }

    /// Seconds of input at the end of hop `h`.
    public func time(ofHop h: Int) -> Double { Double(h * hopSize) / fs }

    public func process(_ input: UnsafeBufferPointer<Float>) {
        for x in input {
            ring[ringPos] = x
            ringPos = (ringPos + 1) % windowSize
            samples += 1
            sinceHop += 1
            if sinceHop >= hopSize {
                sinceHop = 0
                analyse()
                hop = samples / hopSize
                onHop?(hop)
            }
        }
    }

    public func process(_ input: [Float]) { input.withUnsafeBufferPointer { process($0) } }

    private func analyse() {
        // Unroll the ring into a windowed, zero-padded frame.
        let tail = windowSize - ringPos
        for i in 0..<tail { frame[i] = ring[ringPos + i] * window[i] }
        for i in 0..<ringPos { frame[tail + i] = ring[i] * window[tail + i] }
        for i in windowSize..<nfft { frame[i] = 0 }
        var ms: Float = 0
        ring.withUnsafeBufferPointer { vDSP_measqv($0.baseAddress!, 1, &ms, vDSP_Length(windowSize)) }
        rmsDB = 10 * log10(ms + 1e-12)

        re.withUnsafeMutableBufferPointer { rp in
            im.withUnsafeMutableBufferPointer { ip in
                var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                frame.withUnsafeBufferPointer { fp in
                    fp.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: nfft / 2) {
                        vDSP_ctoz($0, 2, &split, 1, vDSP_Length(nfft / 2))
                    }
                }
                vDSP_fft_zrip(fft, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                split.imagp[0] = 0                           // packed Nyquist, not needed
                power.withUnsafeMutableBufferPointer { pp in
                    vDSP_zvmags(&split, 1, pp.baseAddress!, 1, vDSP_Length(nfft / 2))
                }
            }
        }
        // Normalise so a full-scale sine reads about 0 dB.
        let scale = 1 / Float(windowSize * windowSize) * 4

        let slot = (samples / hopSize) % depth
        var levels = hist[slot], odd = oddHist[slot], even = evenHist[slot], low = lowHist[slot], sharp = sharpHist[slot]
        for (k, row) in bins.enumerated() {
            var sum: Float = 0, so: Float = 0, se: Float = 0, pl: Float = 0, pt: Float = 0, ss: Float = 0
            for (h, (lo, hi)) in row.enumerated() where lo >= 0 {
                var p: Float = 0
                for b in lo...hi where power[b] > p { p = power[b] }
                p *= scale
                sum += weights[h] * p
                if h % 2 == 0 { so += p } else { se += p }
                if h < 2 { pl = max(pl, p) }
                if resolved[k][h] { ss += weights[h] * p }
                pt = max(pt, p)
            }
            // New energy: this hop's peak minus the peak `diffLagSec` ago, on resolved harmonics only.
            var sn: Float = 0
            let old = pastPower[pastPos]
            for (h, (lo, hi)) in row.enumerated() where lo >= 0 && resolved[k][h] {
                var p: Float = 0, q: Float = 0
                for b in lo...hi { p = max(p, power[b]); q = max(q, old[b]) }
                sn += weights[h] * max(0, p - q) * scale
            }
            newRow[k] = 10 * log10(sn + 1e-14)
            low[k] = 10 * log10((pl + 1e-14) / (pt + 1e-14))
            sharp[k] = 10 * log10(ss + 1e-14)
            levels[k] = 10 * log10(sum + 1e-14)
            odd[k] = 10 * log10(so + 1e-14)
            even[k] = 10 * log10(se + 1e-14)
        }
        pastPower[pastPos] = power
        pastPos = (pastPos + 1) % pastPower.count
        hist[slot] = levels; oddHist[slot] = odd; evenHist[slot] = even; lowHist[slot] = low; sharpHist[slot] = sharp
        // Noise floor: follow the median level down fast, up slowly.
        let med = levels.sorted()[levels.count / 2]
        if floorDB < -150 { floorDB = med } else { floorDB = med < floorDB ? med : floorDB + 0.02 }
    }

    private func idx(_ midi: Int) -> Int? { notes.contains(midi) ? midi - config.lowMidi : nil }
    private func at(_ k: Int, ago: Int = 0) -> Float { hist[((samples / hopSize) - ago + depth * 4) % depth][k] }

    /// Resolved-harmonic level over the louder semitone neighbour, dB.
    private func contrast(_ k: Int) -> Float {
        let slot = (samples / hopSize) % depth, row = sharpHist[slot]
        return row[k] - max(k > 0 ? row[k - 1] : -200, k + 1 < row.count ? row[k + 1] : -200)
    }

    /// The same, on the new energy only (a note still ringing next door drops out).
    private func diffContrast(_ k: Int) -> Float {
        newRow[k] - max(k > 0 ? newRow[k - 1] : -200, k + 1 < newRow.count ? newRow[k + 1] : -200)
    }

    /// Could this note be what is sounding (not a ghost below it, not an octave too low)?
    private func pitched(_ k: Int) -> Bool {
        let slot = (samples / hopSize) % depth
        return lowHist[slot][k] >= -config.lowDB && oddHist[slot][k] - evenHist[slot][k] >= config.oddDB
    }

    /// The judge's tests for one note in the newest hop (for the bench's diagnosis).
    public func features(_ midi: Int) -> [String: Float] {
        guard let k = idx(midi) else { return [:] }
        let slot = (samples / hopSize) % depth
        let back = min(Int(config.riseSec * fs / Double(hopSize)), hop, depth - 1)
        var lo = Float.infinity
        for a in 1...max(1, back) { lo = min(lo, at(k, ago: a)) }
        return ["gate": at(k) - floorDB, "rise": at(k) - lo, "contrast": contrast(k),
                "low": lowHist[slot][k], "odd": oddHist[slot][k] - evenHist[slot][k]]
    }

    /// Level of a note in the newest hop, dB.
    public func level(_ midi: Int) -> Float { idx(midi).map { at($0) } ?? -200 }

    /// Was `midi` struck in the newest hop? `since` (a hop number) keeps the rise reference
    /// after an earlier hit, so one pluck cannot satisfy two steps. `allowing` lists notes
    /// played with it (a chord) that may share its harmonics without explaining it away.
    public func struck(_ midi: Int, since: Int = 0, allowing: Set<Int> = []) -> Bool {
        guard let k = idx(midi) else { return false }
        let c = config
        let now = at(k)
        guard now >= floorDB + c.gateDB else { return false }
        // Onset: a jump over the note's own recent minimum.
        let back = Int(c.riseSec * fs / Double(hopSize))
        let avail = min(back, hop - since, depth - 1)
        guard avail >= 1 else { return false }
        var lo = Float.infinity
        for a in 1...avail { lo = min(lo, at(k, ago: a)) }
        guard now - lo >= c.riseDB else { return false }
        // Clear of the semitones either side; or, when a neighbour is still ringing from the last
        // note, clear of it in the new energy alone (and not buried under it).
        let cont = contrast(k)
        if cont < c.contrastDB {
            guard cont > -c.buriedDB, diffContrast(k) >= c.diffContrastDB else { return false }
        }
        // Its bottom harmonics sound and its odd ones too: not a ghost, not an octave too low.
        guard pitched(k) else { return false }
        // Not an upper partial (octave, twelfth, two octaves) of a lower note sounding as loud.
        for d in [12, 19, 24] {
            let lowNote = midi - d
            guard let j = idx(lowNote), !allowing.contains(lowNote) else { continue }
            if at(j) >= now - c.partialDB && pitched(j) && contrast(j) >= c.contrastDB { return false }
        }
        return true
    }

    /// The hop where `midi`'s level first jumped (3 dB over its recent minimum), looking back
    /// from the newest hop; for measuring pluck-to-registered latency.
    public func onsetHop(_ midi: Int, before: Int, since: Int = 0) -> Int {
        guard let k = idx(midi) else { return hop }
        let avail = min(Int(config.riseSec * fs / Double(hopSize)), hop - since, depth - 1)
        guard avail >= 1 else { return hop }
        var lo = Float.infinity, loAgo = 0
        for a in 0...avail where at(k, ago: a) <= lo { lo = at(k, ago: a); loAgo = a }
        var a = loAgo
        while a > 0 && at(k, ago: a) < lo + 3 { a -= 1 }
        return hop - a
    }

    /// Every note struck in the newest hop (for a "heard" readout), lowest first, without the
    /// upper partials of notes already listed.
    public func struckNotes(since: Int = 0) -> [Int] {
        var out: [Int] = []
        for m in notes where struck(m, since: since) {
            if out.contains(where: { [12, 19, 24].contains(m - $0) }) { continue }
            out.append(m)
        }
        return out
    }

    /// The loudest clearly pitched note right now, struck or ringing (for the tuner-style readout).
    public func loudest() -> Int? {
        var best: (Int, Float)? = nil
        for m in notes {
            let k = m - config.lowMidi, l = at(k)
            guard l >= floorDB + config.gateDB else { continue }
            guard contrast(k) >= config.contrastDB, pitched(k) else { continue }
            if best == nil || l > best!.1 + 1 { best = (m, l) }   // ties go to the lower note
        }
        return best?.0
    }
}
