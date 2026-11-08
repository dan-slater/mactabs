import AVFoundation
import SwiftUI
import NoteJudge

/// Play mode ("wait mode"): a chart scrolls towards the hit line and stops at each note until
/// the guitar plays that pitch into the mic. Judged by pitch, not by string: any string/fret
/// that sounds the note counts.
@MainActor
final class Game: ObservableObject {
    @Published private(set) var chart: Chart?
    @Published private(set) var index = 0                 // the next step to play
    @Published private(set) var heard: Int?
    /// How sharp/flat the heard note is (tuner readout).
    @Published private(set) var cents: Float?
    @Published private(set) var level: Float = -120
    @Published private(set) var latencies: [Double] = []
    @Published private(set) var plucks = 0                // pitched onsets heard while playing
    @Published private(set) var paused = false
    @Published private(set) var micOn = false
    @Published var speed = 1.0
    @Published var message = ""
    /// Wall time each step was hit, for the flash on the line.
    private(set) var hitWall: [Int: Double] = [:]

    /// Runs before a chart starts (the content view turns voice commands off: they share the mic).
    var beforeStart: (() -> Void)?

    private let listener = Listener()
    private var anchorWall = 0.0
    private var anchorSong = 0.0
    private var injected: Set<Int> = []
    private var log: FileHandle?
    private var startWall = 0.0
    private var lastLevelLog = 0.0

    /// A hit is taken this far before its note reaches the line; earlier plucks re-arm the judge.
    static let lookahead = 0.6
    static let lead = 2.0

    var steps: [Chart.Step] { chart?.steps ?? [] }
    var done: Bool { chart != nil && index >= steps.count }
    var stopAt: Double { index < steps.count ? steps[index].time : .infinity }

    init() {
        listener.onHit = { [weak self] hit in self?.listened(hit) }
        listener.onMeter = { [weak self] note, level, cents in
            guard let self else { return }
            let now = Listener.now()
            if self.chart != nil, now - self.lastLevelLog > 1 { self.lastLevelLog = now; self.write(["event": "level", "rms_db": level.isFinite ? Int(level) : -120]) }
            if self.heard != note { self.heard = note }
            self.cents = cents
            self.level = level
        }
        listener.onStruck = { [weak self] notes, step, rms, cents in
            guard let self, self.chart != nil, !self.done else { return }
            self.plucks += 1
            self.write(["event": "pluck", "notes": notes, "step": step, "rms_db": rms.isFinite ? Int(rms) : -120, "cents": cents])
        }
    }

    // MARK: clock

    func songTime(_ now: Double = Listener.now()) -> Double {
        paused ? anchorSong : min(anchorSong + (now - anchorWall) * speed, stopAt)
    }
    func waiting(_ now: Double = Listener.now()) -> Bool { !done && songTime(now) >= stopAt - 1e-6 }
    private func rebase() { let now = Listener.now(); anchorSong = songTime(now); anchorWall = now }

    // MARK: control

    func start(_ url: URL, mic: Bool) {
        let chart: Chart
        do { chart = try Chart(url: url) } catch { message = "cannot read \(url.lastPathComponent)"; return }
        guard !chart.steps.isEmpty else { message = "no notes in \(url.lastPathComponent)"; return }
        beforeStart?()
        stop()
        self.chart = chart
        message = ""
        startWall = Listener.now()
        openLog(chart)
        restart()
        if mic { startMic() }
    }

    func restart() {
        guard let chart else { return }
        index = 0; latencies = []; plucks = 0; hitWall = [:]; injected = []; paused = false
        anchorSong = (chart.steps.first?.time ?? 0) - Self.lead
        anchorWall = Listener.now()
        startWall = anchorWall
        arm()
    }

    func stop() {
        listener.stop()
        micOn = false
        chart = nil
        log?.closeFile(); log = nil
    }

    func togglePause() { rebase(); paused.toggle() }
    func faster() { rebase(); speed = min(1.5, speed + 0.1) }
    func slower() { rebase(); speed = max(0.3, speed - 0.1) }

    private func startMic() {
        AVCaptureDevice.requestAccess(for: .audio) { ok in
            Task { @MainActor in
                guard self.chart != nil else { return }
                guard ok else { self.message = "mic not authorised (System Settings → Privacy → Microphone)"; return }
                if let err = self.listener.startMic() { self.message = err } else { self.micOn = true; self.arm() }
            }
        }
    }

    /// Test hook: play a recording into the judge instead of the mic.
    func feed(_ url: URL) {
        if let err = listener.startFile(url) { message = err } else { arm() }
    }

    private func arm() {
        guard index < steps.count else { return }
        listener.expect(step: index, pitches: steps[index].pitches)
    }

    // MARK: judging

    private func listened(_ hit: Listener.Hit) {
        guard hit.step == index, index < steps.count else { return }
        if stopAt - songTime() > Self.lookahead { arm(); return }   // too early to be this note
        advance(latency: hit.latency)
    }

    /// Test hook: notes "heard" without audio. A step passes once all its pitches have come in.
    func inject(_ notes: [Int]) {
        guard index < steps.count else { return }
        plucks += 1
        injected.formUnion(notes)
        if steps[index].pitches.isSubset(of: injected) { injected = []; advance(latency: nil) }
    }

    private func advance(latency: Double?) {
        rebase()
        let now = Listener.now()
        hitWall[index] = now
        if let latency { latencies.append(latency) }
        write(["event": "hit", "step": index, "pitches": steps[index].pitches.sorted(),
               "latency_ms": latency.map { Int($0 * 1000) } as Any, "waited": waiting(now)])
        index += 1
        if done {
            write(["event": "done", "steps": steps.count, "plucks": plucks, "seconds": now - startWall,
                   "median_latency_ms": medianLatency.map { Int($0 * 1000) } as Any])
            listener.expect(step: -1, pitches: [])
        } else { arm() }
    }

    var medianLatency: Double? { latencies.isEmpty ? nil : latencies.sorted()[latencies.count / 2] }

    // MARK: session log (JSON lines, for scoring a play test afterwards)

    private func openLog(_ chart: Chart) {
        let env = ProcessInfo.processInfo.environment
        let url: URL
        if let fifo = env["TABS_TEST_FIFO"] { url = URL(fileURLWithPath: fifo + ".play.jsonl") }
        else {
            let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/MacTabs")
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let f = DateFormatter(); f.dateFormat = "yyyyMMdd-HHmmss"
            url = dir.appendingPathComponent("play-\(f.string(from: Date())).jsonl")
        }
        FileManager.default.createFile(atPath: url.path, contents: nil)
        log = FileHandle(forWritingAtPath: url.path)
        write(["event": "start", "title": chart.title, "artist": chart.artist, "steps": chart.steps.count])
    }

    private func write(_ obj: [String: Any]) {
        guard let log else { return }
        var o = obj; o["t"] = ((Listener.now() - startWall) * 1000).rounded() / 1000
        if let d = try? JSONSerialization.data(withJSONObject: o) { log.write(d + Data("\n".utf8)) }
    }

    /// One JSON line for the test harness.
    func stateJSON() -> String {
        let now = Listener.now()
        let o: [String: Any] = [
            "playing": chart != nil, "title": chart?.title ?? "", "step": index, "steps": steps.count,
            "done": done, "waiting": waiting(now), "songTime": songTime(now), "plucks": plucks,
            "hits": hitWall.count, "mic": micOn, "speed": speed, "message": message,
            "latencies": latencies.map { Int($0 * 1000) },
        ]
        let d = (try? JSONSerialization.data(withJSONObject: o)) ?? Data("{}".utf8)
        return String(decoding: d, as: UTF8.self)
    }
}

// MARK: - the view

struct PlayView: View {
    @ObservedObject var game: Game
    @AppStorage("design.highway") private var layout: HighwayLayout = .lanes
    @AppStorage("design.noteLabel") private var label: NoteLabel = .fret
    @State private var showDesign = false

    var body: some View {
        VStack(spacing: 0) {
            header
            TimelineView(.animation(paused: game.chart == nil)) { tl in
                Canvas { ctx, size in
                    let now = Listener.now()
                    switch layout {
                    case .lanes: drawLanes(&ctx, size, now)
                    case .strip: drawStrip(&ctx, size, now)
                    }
                }
            }
            .background(Color(nsColor: .textBackgroundColor))
            hud
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showDesign.toggle() } label: { Image(systemName: "slider.horizontal.3") }
                    .help("Design options (⌘,)")
                    .popover(isPresented: $showDesign, arrowEdge: .bottom) { DesignPanel() }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(game.chart?.title ?? "").font(.title2.weight(.semibold))
            Text(game.chart?.artist ?? "").font(.title3).foregroundStyle(.secondary)
            Text("wait mode").font(.caption).padding(.horizontal, 6).padding(.vertical, 2)
                .background(.quaternary, in: Capsule())
            Spacer()
            Button { game.stop() } label: { Image(systemName: "xmark") }
                .buttonStyle(.borderless).help("Leave play mode (esc)")
        }
        .padding(.horizontal, 24).padding(.vertical, 10)
    }

    private var hud: some View {
        HStack(spacing: 16) {
            Text("\(min(game.index, game.steps.count)) / \(game.steps.count)").monospacedDigit()
            if game.done {
                Text(summary).foregroundStyle(.green)
            } else if game.index < game.steps.count {
                Text("play " + describe(game.steps[game.index])).foregroundStyle(.primary)
            }
            Spacer()
            if game.micOn {
                HStack(spacing: 6) {
                    Image(systemName: "mic.fill").foregroundStyle(.red)
                    meter
                    Text(game.heard.map(NoteJudge.name) ?? "–").frame(width: 34, alignment: .leading)
                    if game.heard != nil, let c = game.cents {
                        Text(String(format: "%+.0f¢", c)).monospacedDigit().frame(width: 44, alignment: .leading)
                            .foregroundStyle(abs(c) > 20 ? Color.orange : Color.secondary)
                            .help("How far the note sits from in tune (cents). Over ±20 and the string wants tuning.")
                    }
                }
            } else {
                Label("no mic", systemImage: "mic.slash").foregroundStyle(.secondary)
            }
            if let m = game.medianLatency { Text("\(Int(m * 1000)) ms").monospacedDigit().help("Median pluck-to-registered latency") }
            Text("\(Int((game.speed * 100).rounded()))%").monospacedDigit().help("Speed (↑ ↓)")
            if !game.message.isEmpty { Text(game.message).foregroundStyle(.orange) }
            Text(game.paused ? "paused · space" : "space ↑↓ r esc").foregroundStyle(.tertiary)
        }
        .font(.system(.callout, design: .monospaced))
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .padding(12)
    }

    private var meter: some View {
        let v = CGFloat(min(1, max(0, (Double(game.level) + 70) / 60)))
        return ZStack(alignment: .leading) {
            Capsule().fill(.quaternary).frame(width: 60, height: 6)
            Capsule().fill(v > 0.9 ? Color.orange : Color.green).frame(width: 60 * v, height: 6)
        }
    }

    private var summary: String {
        let notes = game.steps.count
        let rate = game.plucks > 0 ? " · \(Int(100 * Double(notes) / Double(max(notes, game.plucks))))% of plucks right" : ""
        return "done: \(notes) notes\(rate)" + (game.medianLatency.map { " · median \(Int($0 * 1000)) ms" } ?? "")
    }

    private func describe(_ s: Chart.Step) -> String {
        s.notes.sorted { $0.midi > $1.midi }.map { n in
            "\(NoteJudge.name(n.midi)) (string \(n.string), \(n.fret == 0 ? "open" : "fret \(n.fret)"))"
        }.joined(separator: " + ")
    }

    // MARK: drawing

    static let stringColors: [Color] = [   // high e … low E
        Color(red: 0.90, green: 0.29, blue: 0.50), Color(red: 0.48, green: 0.38, blue: 1.00),
        Color(red: 0.11, green: 0.61, blue: 0.84), Color(red: 0.18, green: 0.70, blue: 0.48),
        Color(red: 0.95, green: 0.72, blue: 0.02), Color(red: 0.91, green: 0.35, blue: 0.05),
    ]
    static let stringNames = ["e", "B", "G", "D", "A", "E"]

    private func noteText(_ n: Chart.Note, size: CGFloat) -> Text {
        let fret = Text("\(n.fret)").font(.system(size: size, weight: .bold, design: .rounded)).foregroundColor(.white)
        guard label == .fretName else { return fret }
        return fret + Text(" " + NoteJudge.name(n.midi)).font(.system(size: size * 0.55, weight: .semibold)).foregroundColor(.white.opacity(0.85))
    }

    /// Alpha and fill for a step: pending, waiting (pulses), or hit (fades out green).
    private func look(_ i: Int, _ n: Chart.Note, now: Double, waiting: Bool) -> (Color, Double, Double) {
        let base = Self.stringColors[n.string - 1]
        if i < game.index {
            let age = now - (game.hitWall[i] ?? now)
            return (Color.green, max(0, 1 - age / 0.6), 1 + 0.25 * max(0, 1 - age / 0.25))
        }
        if i == game.index && waiting { return (base, 1, 1 + 0.06 * sin(now * 9)) }
        return (base, 0.92, 1)
    }

    private func drawLanes(_ ctx: inout GraphicsContext, _ size: CGSize, _ now: Double) {
        let laneW = min(96, size.width * 0.8 / 6), x0 = (size.width - laneW * 6) / 2
        let hitY = size.height - 70, pps = 230.0
        let t = game.songTime(now), waiting = game.waiting(now)
        func laneX(_ string: Int) -> CGFloat { x0 + laneW * (CGFloat(6 - string) + 0.5) }   // low E on the left
        for s in 1...6 {
            let x = laneX(s)
            ctx.fill(Path(CGRect(x: x - laneW / 2 + 1, y: 0, width: laneW - 2, height: size.height)),
                     with: .color(Self.stringColors[s - 1].opacity(0.05)))
            ctx.stroke(Path { $0.move(to: CGPoint(x: x, y: 0)); $0.addLine(to: CGPoint(x: x, y: size.height)) },
                       with: .color(Self.stringColors[s - 1].opacity(0.35)), lineWidth: CGFloat(1 + (s - 1)) * 0.5)
            ctx.draw(Text(Self.stringNames[s - 1]).font(.system(size: 14, weight: .semibold)).foregroundColor(.secondary),
                     at: CGPoint(x: x, y: size.height - 22))
        }
        ctx.stroke(Path { $0.move(to: CGPoint(x: x0 - 10, y: hitY)); $0.addLine(to: CGPoint(x: x0 + laneW * 6 + 10, y: hitY)) },
                   with: .color(waiting ? .accentColor : .primary.opacity(0.6)), lineWidth: waiting ? 4 : 2)
        for (i, step) in game.steps.enumerated() {
            let y = hitY - CGFloat((step.time - t) * pps)
            if y < -40 { break }
            if y > size.height + 40 { continue }
            for n in step.notes {
                let (fill, alpha, scale) = look(i, n, now: now, waiting: waiting)
                guard alpha > 0 else { continue }
                let w = laneW * 0.78 * scale, h = 34 * scale
                let r = CGRect(x: laneX(n.string) - w / 2, y: y - h / 2, width: w, height: h)
                ctx.fill(Path(roundedRect: r, cornerRadius: 9), with: .color(fill.opacity(alpha)))
                if i == game.index && waiting {
                    ctx.stroke(Path(roundedRect: r.insetBy(dx: -3, dy: -3), cornerRadius: 11), with: .color(.primary.opacity(0.7)), lineWidth: 2)
                }
                ctx.opacity = alpha
                ctx.draw(noteText(n, size: 19), at: CGPoint(x: r.midX, y: r.midY))
                ctx.opacity = 1
            }
        }
    }

    private func drawStrip(_ ctx: inout GraphicsContext, _ size: CGSize, _ now: Double) {
        let gap = min(46, size.height * 0.7 / 6), y0 = (size.height - gap * 5) / 2
        let hitX = max(70, size.width * 0.16), pps = 230.0
        let t = game.songTime(now), waiting = game.waiting(now)
        func lineY(_ string: Int) -> CGFloat { y0 + gap * CGFloat(string - 1) }   // high e on top, as in tab
        for s in 1...6 {
            let y = lineY(s)
            ctx.stroke(Path { $0.move(to: CGPoint(x: 40, y: y)); $0.addLine(to: CGPoint(x: size.width - 10, y: y)) },
                       with: .color(Self.stringColors[s - 1].opacity(0.45)), lineWidth: CGFloat(1 + (s - 1)) * 0.5)
            ctx.draw(Text(Self.stringNames[s - 1]).font(.system(size: 14, weight: .semibold)).foregroundColor(.secondary),
                     at: CGPoint(x: 22, y: y))
        }
        ctx.stroke(Path { $0.move(to: CGPoint(x: hitX, y: y0 - 24)); $0.addLine(to: CGPoint(x: hitX, y: y0 + gap * 5 + 24)) },
                   with: .color(waiting ? .accentColor : .primary.opacity(0.6)), lineWidth: waiting ? 4 : 2)
        for (i, step) in game.steps.enumerated() {
            let x = hitX + CGFloat((step.time - t) * pps)
            if x > size.width + 40 { break }
            if x < -40 { continue }
            for n in step.notes {
                let (fill, alpha, scale) = look(i, n, now: now, waiting: waiting)
                guard alpha > 0 else { continue }
                let d = min(gap - 6, 36) * scale * (label == .fretName ? 1.25 : 1)
                let r = CGRect(x: x - d / 2 * (label == .fretName ? 1.4 : 1), y: lineY(n.string) - d / 2,
                               width: d * (label == .fretName ? 1.4 : 1), height: d)
                ctx.fill(Path(roundedRect: r, cornerRadius: d / 2), with: .color(fill.opacity(alpha)))
                if i == game.index && waiting {
                    ctx.stroke(Path(roundedRect: r.insetBy(dx: -3, dy: -3), cornerRadius: d / 2 + 3), with: .color(.primary.opacity(0.7)), lineWidth: 2)
                }
                ctx.opacity = alpha
                ctx.draw(noteText(n, size: d * 0.5), at: CGPoint(x: r.midX, y: r.midY))
                ctx.opacity = 1
            }
        }
    }
}
