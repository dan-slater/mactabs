import SwiftUI
import Fretboard

/// Finds chord names in a tab and draws their diagrams.
enum Chords {
    // Root + optional accidental + quality + optional /bass.
    static let token = try! NSRegularExpression(pattern:
        #"^([A-G])([#b]?)((?:maj|min|m|M|dim|aug|sus|add|dom|\+|-|°|ø)?[0-9]*(?:sus[24]|add[0-9]+|maj[0-9]*|b5|#5|b9|#9|#11|b13)*)(?:/([A-G][#b]?))?$"#)

    static func isChordToken(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: CharacterSet(charactersIn: "()[]"))
        guard !t.isEmpty, t.count <= 10 else { return false }
        return token.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)) != nil
    }

    /// A line is a chord line when every whitespace-separated token is a chord name.
    static func isChordLine(_ line: String) -> Bool {
        let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        guard !parts.isEmpty, !line.contains("|") else { return false }
        return parts.allSatisfy(isChordToken)
    }

    /// Unique chords in order of first appearance.
    static func inTab(_ body: String) -> [String] {
        var seen: [String] = []
        for line in body.components(separatedBy: "\n") where isChordLine(line) {
            for p in line.split(separator: " ") {
                let c = p.trimmingCharacters(in: CharacterSet(charactersIn: "()[]"))
                if !seen.contains(c) { seen.append(c) }
            }
        }
        return seen
    }

    /// Map a chord name to the chords-db key/suffix and return the first voicing.
    static func position(for name: String) -> Chord.Position? {
        guard let m = token.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)) else { return nil }
        func g(_ i: Int) -> String { Range(m.range(at: i), in: name).map { String(name[$0]) } ?? "" }
        var root = g(1) + g(2)
        root = ["Db": "C#", "D#": "Eb", "Gb": "F#", "G#": "Ab", "A#": "Bb", "Cb": "B", "Fb": "E", "E#": "F", "B#": "C"][root] ?? root
        var q = g(3)
        if q.isEmpty { q = "major" }
        else if q == "m" || q == "min" || q == "-" { q = "minor" }
        else if q.hasPrefix("min") { q = "m" + q.dropFirst(3) }
        else if q == "M7" { q = "maj7" }
        else if q == "+" { q = "aug" }
        else if q == "°" { q = "dim" }
        let bass = g(4)
        let guitar = Instrument.guitar
        if !bass.isEmpty, let p = guitar.findChordPositions(key: root, suffix: "\(q == "major" ? "" : q)/\(bass)").first { return p }
        if let p = guitar.findChordPositions(key: root, suffix: q).first { return p }
        return guitar.findChordPositions(key: root, suffix: "major").first
    }
}

struct ChordPanel: View {
    let body_: String
    var body: some View {
        let names = Chords.inTab(body_)
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 12)], spacing: 16) {
                ForEach(names, id: \.self) { name in
                    VStack(spacing: 4) {
                        Text(name).font(.system(.callout, design: .monospaced).bold())
                        if let p = Chords.position(for: name) {
                            FretboardView(position: p).frame(width: 84, height: 110)
                        } else {
                            Text("?").foregroundStyle(.secondary).frame(width: 84, height: 110)
                        }
                    }
                    .accessibilityIdentifier("chord-\(name)")
                }
            }
            .padding(12)
        }
        .frame(width: 220)
        .accessibilityIdentifier("chordPanel")
        .overlay(alignment: .top) { if names.isEmpty { Text("no chord lines").foregroundStyle(.secondary).padding() } }
    }
}
