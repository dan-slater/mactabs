import Foundation

/// A playable chart: notes with a time, a string (1 = high e … 6 = low E) and a fret.
/// JSON: `{"title": …, "artist": …, "notes": [{"t": 3.36, "ts": 3.355, "string": 1, "fret": 0, "midi": 64}]}`.
/// `ts` (time snapped to the audio onset) wins over `t`; `midi` is derived from string/fret
/// in standard tuning when missing.
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
    }

    public var title: String
    public var artist: String
    public var steps: [Step]

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
        let notes: [Note] = raw.compactMap { d in
            guard let t = num(d["ts"]) ?? num(d["t"]), let s = num(d["string"]).map(Int.init), let f = num(d["fret"]).map(Int.init),
                  (1...6).contains(s) else { return nil }
            return Note(time: t, string: s, fret: f, midi: num(d["midi"]).map(Int.init) ?? Chart.openStrings[s - 1] + f)
        }
        let base = url.deletingPathExtension().deletingPathExtension().lastPathComponent   // "Artist - Title.chart.json"
        let parts = base.components(separatedBy: " - ")
        self.init(title: obj["title"] as? String ?? parts.last ?? base,
                  artist: obj["artist"] as? String ?? (parts.count > 1 ? parts[0] : ""),
                  notes: notes)
    }

    public var duration: Double { steps.last.map { $0.time } ?? 0 }
}
