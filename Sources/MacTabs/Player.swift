import AppKit
import Combine

/// Playback state for the open tab: autoscroll speed, running flag, font size.
@MainActor
final class Player: ObservableObject {
    @Published var tab: TabFile?
    @Published var running = false
    /// Lines per second.
    @Published var speed: Double = 1.0
    @Published var fontSize: CGFloat = 18
    @Published var showChords = true
    /// Set by the view to jump; the scroll view consumes and clears it.
    @Published var jumpToLine: Int?
    @Published var status = ""

    private var saveTimer: Timer?

    func open(_ tab: TabFile?) {
        self.tab = tab
        speed = tab?.scroll ?? 1.0
        running = false
        jumpToLine = 0
    }

    func toggle() { running.toggle(); flash(running ? "scrolling" : "paused") }

    func faster() { setSpeed(speed * 1.15) }
    func slower() { setSpeed(speed / 1.15) }

    func setSpeed(_ s: Double) {
        speed = min(max(s, 0.05), 20)
        flash(String(format: "%.2f lines/s", speed))
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.persistSpeed() }
        }
    }

    private func persistSpeed() {
        guard let tab, abs(tab.scroll - speed) > 0.001 else { return }
        if let saved = tab.saveScroll(speed) { self.tab = saved }
    }

    func top() { jumpToLine = 0; flash("top") }

    func nextSection(_ fromLine: Int, forward: Bool) {
        guard let s = tab?.sections, !s.isEmpty else { return }
        let target = forward ? s.first { $0 > fromLine } : s.last { $0 < fromLine }
        if let target { jumpToLine = target; flash("section \(target)") }
    }

    func flash(_ text: String) {
        status = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            if self?.status == text { self?.status = "" }
        }
    }
}
