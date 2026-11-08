import Foundation

/// What the game listens with: NoteJudge (DSP) and, when it loads, Basic Pitch (`NoteModel`).
///
/// A step's note counts when Basic Pitch hears that pitch sounding (its note posterior; it
/// rarely mistakes a fret for the note) AND a new pluck shows, from either side: Basic Pitch's
/// onset posterior, or NoteJudge's onset test (a strum over a ringing chord, which Basic Pitch's
/// onset head often misses). A single note must also not be just the overtone of a lower note
/// that was plucked (NoteJudge's veto; Basic Pitch hears a G#2's octave as G#3 now and then).
/// Without the model it is NoteJudge alone, with its own defaults.
///
/// GuitarSet laptop-mic bench, 2026-11-08, held-out players 04–05, first-pluck hit for single /
/// dyad / chord steps: Hearing 94 / 65 / 74 %, NoteJudge alone 87 / 33 / 39 %; wrong-fret accepts
/// 0–2.5 % vs 0.2–4 % (`pitchbench suite <manifest> --live`).
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
    /// `config` defaults to `NoteJudge.Config.hybrid` with the model and to NoteJudge's own defaults without.
    public init(sampleRate: Double, config: NoteJudge.Config? = nil, model: NoteModel.Config? = .init(), waitForModel: Bool = true) {
        judge = NoteJudge(sampleRate: sampleRate, config: config ?? (model == nil ? .init() : .hybrid))
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
        guard model.heard(midi, after: armed, note: 0)
            || judge.verdict(midi, since: since, allowing: allowing).rawValue > NoteJudge.Verdict.onset.rawValue else { return false }
        return allowing.count > 1 || !judge.overtone(midi, since: since, allowing: allowing)
    }
}
