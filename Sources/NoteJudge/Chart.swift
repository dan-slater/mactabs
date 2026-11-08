import Foundation

/// A playable chart: notes with a time, a string (1 = high e … 6 = low E) and a fret.
/// JSON: `{"title": …, "artist": …, "capo": 0, "notes": [{"t": 3.36, "ts": 3.355, "string": 1, "fret": 0, "midi": 64}]}`.
/// `ts` (time snapped to the audio onset) wins over `t`; `midi` is derived from string/fret
/// in standard tuning (plus the capo) when missing.
public struct Chart {
    public struct Note: Hashable {
        public var time: Double
        public var string: Int
        public var fret: Int
        public var midi: Int
    }
    /// Notes that start together (a chord or a dyad) form one step.
    public struct Step {
        public var time: Double
        public var notes: [Note]
        public var pitches: Set<Int> { Set(notes.map(\.midi)) }
        /// What must be heard to pass: every note of a single note or a dyad; the lowest and
        /// highest of a bigger chord (a strum rarely sounds all six clearly).
        public var required: Set<Int> {
            let p = pitches
            return p.count <= 2 ? p : [p.min()!, p.max()!]
        }
    }

    public var title: String
    public var artist: String
    public var steps: [Step]
    /// The capo the pitches include (frets stay as written, relative to it).
    public var capo = 0

    public static let openStrings = [64, 59, 55, 50, 45, 40]   // e B G D A E

    public init(title: String, artist: String, notes: [Note]) {
        self.title = title
        self.artist = artist
        var steps: [Step] = []
        for n in notes.sorted(by: { $0.time < $1.time }) {
            if let last = steps.last, n.time - last.time < 0.035 { steps[steps.count - 1].notes.append(n) }
            else { steps.append(Step(time: n.time, notes: [n])) }
        }
        self.steps = steps
    }

    public init(url: URL) throws {
        let obj = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any] ?? [:]
        let raw = obj["notes"] as? [[String: Any]] ?? []
        func num(_ v: Any?) -> Double? { (v as? NSNumber)?.doubleValue }
        let capo = num(obj["capo"]).map(Int.init) ?? 0
        let notes: [Note] = raw.compactMap { d in
            guard let t = num(d["ts"]) ?? num(d["t"]), let s = num(d["string"]).map(Int.init), let f = num(d["fret"]).map(Int.init),
                  (1...6).contains(s) else { return nil }
            return Note(time: t, string: s, fret: f, midi: num(d["midi"]).map(Int.init) ?? Chart.openStrings[s - 1] + capo + f)
        }
        let base = url.deletingPathExtension().deletingPathExtension().lastPathComponent   // "Artist - Title.chart.json"
        let parts = base.components(separatedBy: " - ")
        self.init(title: obj["title"] as? String ?? parts.last ?? base,
                  artist: obj["artist"] as? String ?? (parts.count > 1 ? parts[0] : ""),
                  notes: notes)
        self.capo = capo
    }

    /// The same chart with every pitch moved `semitones` (frets as written): playing with or
    /// without the capo the tab asks for.
    public func transposed(_ semitones: Int) -> Chart {
        var c = self
        for i in c.steps.indices { for j in c.steps[i].notes.indices { c.steps[i].notes[j].midi += semitones } }
        return c
    }

    /// Read the ASCII tab staves (`e|---0---|`) out of a tab's text: six lines in a row, high e
    /// first. Notes in one column form a step. Spacing follows the columns, kept between 0.3 and
    /// 1 s per step (wait mode stops at every note anyway). `tuning` is low to high ("EADGBE",
    /// "DADGBE", "Eb Ab Db Gb Bb Eb"); `capo` raises every fret. Nil when there are no staves.
    public static func fromTab(_ text: String, title: String, artist: String, tuning: String? = nil, capo: Int = 0) -> Chart? {
        let open = openStrings(tuning).map { $0 + capo }    // high e first
        let staff = try! NSRegularExpression(pattern: #"^\s*[A-Ga-g][#b]?\s*\|+(.*)$"#)
        func content(_ line: String) -> [Character]? {
            let ns = line as NSString
            guard let m = staff.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else { return nil }
            var body = ns.substring(with: m.range(at: 1))
            guard body.filter({ $0 == "-" }).count >= 4 else { return nil }
            // Drop a trailing "(x4)" or similar after the last bar line.
            if let bar = body.lastIndex(of: "|"), !body[body.index(after: bar)...].contains("-") { body = String(body[..<bar]) }
            return Array(body)
        }
        let lines = text.components(separatedBy: "\n")
        var cols: [(col: Int, notes: [Note])] = []
        var base = 0, i = 0
        while i + 6 <= lines.count {
            let block = lines[i..<(i + 6)].map(content)
            guard block.allSatisfy({ $0 != nil }) else { i += 1; continue }
            let rows = block.map { $0! }
            let width = rows.map(\.count).max() ?? 0
            // "(x4)" / "x2" after the block's last bar line: play the block that many times.
            let rep = lines[i..<(i + 6)].compactMap { l -> Int? in
                guard let bar = l.lastIndex(of: "|") else { return nil }
                let tail = l[l.index(after: bar)...].lowercased()
                guard let r = tail.range(of: #"x\s*([2-9])"#, options: .regularExpression) else { return nil }
                return Int(tail[r].filter(\.isNumber))
            }.max() ?? 1
            for _ in 0..<rep {
            var skip = Array(repeating: -1, count: 6)
            for c in 0..<width {
                var notes: [Note] = []
                for (s, row) in rows.enumerated() where c < row.count && c != skip[s] {
                    guard let d = row[c].wholeNumberValue, row[c].isASCII else { continue }
                    var fret = d
                    if c + 1 < row.count, let d2 = row[c + 1].wholeNumberValue, row[c + 1].isASCII, d * 10 + d2 <= 24 {
                        fret = d * 10 + d2; skip[s] = c + 1
                    }
                    notes.append(Note(time: 0, string: s + 1, fret: fret, midi: open[s] + fret))
                }
                if !notes.isEmpty { cols.append((base + c, notes)) }
            }
            base += width + 8
            }
            i += 6
        }
        guard cols.count >= 2 else { return nil }
        var t = 0.0, notes: [Note] = []
        for (k, c) in cols.enumerated() {
            if k > 0 { t += min(1.0, max(0.3, Double(c.col - cols[k - 1].col) * 0.09)) }
            for var n in c.notes { n.time = t; notes.append(n) }
        }
        var c = Chart(title: title, artist: artist, notes: notes)
        c.capo = capo
        return c
    }

    /// Open-string pitches, high e first, from a low-to-high tuning name; standard when unreadable.
    public static func openStrings(_ tuning: String?) -> [Int] {
        guard let tuning else { return openStrings }
        let pcs: [Character: Int] = ["C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11]
        var names: [Int] = []
        let chars = Array(tuning.replacingOccurrences(of: " ", with: ""))
        var k = 0
        while k < chars.count {
            guard let pc = pcs[Character(chars[k].uppercased())] else { k += 1; continue }
            var p = pc
            if k + 1 < chars.count, chars[k + 1] == "#" { p += 1; k += 1 }
            else if k + 1 < chars.count, chars[k + 1] == "b" { p -= 1; k += 1 }
            names.append((p + 12) % 12); k += 1
        }
        guard names.count == 6 else { return openStrings }
        // Each string takes the octave nearest standard tuning's.
        let std = Array(openStrings.reversed())             // low E first
        let low = zip(names, std).map { pc, s -> Int in
            let base = s - ((s % 12) - pc)
            return [base - 12, base, base + 12].min { abs($0 - s) < abs($1 - s) }!
        }
        return low.reversed()
    }

    public var duration: Double { steps.last.map { $0.time } ?? 0 }
}
