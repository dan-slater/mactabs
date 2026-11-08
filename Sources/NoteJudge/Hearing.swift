import Foundation

/// What the game listens with: NoteJudge (DSP) and, when it loads, Basic Pitch (`NoteModel`).
///
/// A step's note counts when Basic Pitch hears that pitch sounding (its note posterior; it
/// rarely mistakes a fret or an overtone for the note) AND a new pluck shows, from either side:
/// Basic Pitch's onset posterior, or NoteJudge's onset test (a strum over a ringing chord, which
/// Basic Pitch's onset head often misses). Without the model it is NoteJudge alone.
///
/// GuitarSet laptop-mic bench, 2026-11-08 (single / dyad / chord hit, players 00–03):
/// NoteJudge alone 84 / 37 / 42 %, with wrong-fret false accepts 1–4 %; together 92 / 69 / 59 %,
/// wrong-fret accepts 0–3 %, latency ~45–85 ms median.
public final class Hearing {
    public let judge: NoteJudge
    public private(set) var model: NoteModel?
    /// Waiting for `NoteModel.prepare` to finish: attach the model then (NoteJudge alone until).
    private var pending: NoteModel.Config?
    public var onHop: ((Int) -> Void)? {
        get { judge.onHop }
        set { judge.onHop = newValue }
    }

    /// `waitForModel: false` (live): if the model is not warm yet, start with NoteJudge alone and
    /// attach the model once `NoteModel.prepare` has finished.
    public init(sampleRate: Double, config: NoteJudge.Config = .init(), model: NoteModel.Config? = .init(), waitForModel: Bool = true) {
        judge = NoteJudge(sampleRate: sampleRate, config: config)
        if let m = model, !waitForModel, !NoteModel.isReady {
            pending = m
            NoteModel.prepare()
        } else {
            self.model = model.flatMap { NoteModel(sampleRate: sampleRate, config: $0) }
        }
    }

    /// Feed mono samples. The model sees each buffer before the judge's hops inside it run.
    public func process(_ x: [Float]) {
        if let p = pending, NoteModel.isReady { pending = nil; model = NoteModel(sampleRate: judge.fs, config: p) }
        model?.process(x)
        judge.process(x)
    }

    public var hop: Int { judge.hop }
    public func time(ofHop h: Int) -> Double { judge.time(ofHop: h) }

    /// Was `midi` struck since hop `since`? `allowing`: the step's notes (see `NoteJudge.struck`).
    public func struck(_ midi: Int, since: Int = 0, allowing: Set<Int> = []) -> Bool {
        guard let model else { return judge.struck(midi, since: since, allowing: allowing) }
        let armed = judge.time(ofHop: since)
        guard model.heard(midi, after: armed, on: 0) else { return false }
        return model.heard(midi, after: armed, note: 0)
            || judge.verdict(midi, since: since, allowing: allowing).rawValue > NoteJudge.Verdict.onset.rawValue
    }
}
