import AppKit
import SwiftUI

/// Monospace text in an NSScrollView that the Player drives at `speed` lines/second.
struct ScrollText: NSViewRepresentable {
    @ObservedObject var player: Player
    let text: String

    func makeCoordinator() -> Coordinator { Coordinator(player: player) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.setAccessibilityIdentifier("tabScroll")

        let tv = NSTextView()
        tv.isEditable = false
        tv.isSelectable = false
        tv.drawsBackground = false
        tv.textContainerInset = NSSize(width: 24, height: 40)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = true
        tv.autoresizingMask = [.width]
        // Tab lines never wrap: the font auto-fits the longest line, and anything wider scrolls sideways.
        tv.textContainer?.widthTracksTextView = false
        tv.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        scroll.hasHorizontalScroller = true
        tv.setAccessibilityIdentifier("tabText")
        scroll.documentView = tv
        context.coordinator.scroll = scroll
        context.coordinator.textView = tv
        context.coordinator.start()
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let c = context.coordinator
        guard let tv = c.textView else { return }
        let fitted = Self.fit(player.fontSize, text: text, width: scroll.contentSize.width - 48)
        if c.text != text || c.fontSize != fitted {
            c.text = text
            c.fontSize = fitted
            // Pad the end so the last line can scroll up to the top of the window.
            let pad = Int(scroll.bounds.height * 0.6 / max(1, fitted * 1.5))
            tv.textStorage?.setAttributedString(Self.style(text + String(repeating: "\n", count: pad), size: fitted))
            tv.textContainerInset = NSSize(width: 24, height: 40)
            tv.layoutManager?.ensureLayout(for: tv.textContainer!)
            scroll.contentView.setBoundsOrigin(.zero)
            scroll.reflectScrolledClipView(scroll.contentView)
            c.pendingTop = true   // the first update runs before the view has a size; re-pin once it does
        }
        if let line = player.jumpToLine {
            c.jump(toLine: line)
            DispatchQueue.main.async { player.jumpToLine = nil }
        }
    }

    /// The largest size ≤ `requested` (and ≥ 10) at which the longest line fits in `width`.
    static func fit(_ requested: CGFloat, text: String, width: CGFloat) -> CGFloat {
        guard width > 50 else { return requested }
        let longest = text.components(separatedBy: "\n").map(\.count).max() ?? 0
        guard longest > 0 else { return requested }
        let advance = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular).advancement(forGlyph: 0).width / 10  // per point
        let fits = floor(width / (CGFloat(longest) * advance))
        return min(requested, max(10, fits))
    }

    static func style(_ text: String, size: CGFloat) -> NSAttributedString {
        let mono = NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        let out = NSMutableAttributedString()
        let para = NSMutableParagraphStyle()
        para.lineSpacing = size * 0.25
        for line in text.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            var attrs: [NSAttributedString.Key: Any] = [.font: mono, .paragraphStyle: para,
                                                        .foregroundColor: NSColor.textColor]
            if t.hasPrefix("[") && t.hasSuffix("]") {
                attrs[.font] = NSFont.monospacedSystemFont(ofSize: size, weight: .bold)
                attrs[.foregroundColor] = NSColor.systemOrange
            } else if Chords.isChordLine(line) {
                attrs[.foregroundColor] = NSColor.systemTeal
                attrs[.font] = NSFont.monospacedSystemFont(ofSize: size, weight: .semibold)
            } else if line.contains("|") && line.contains("-") {
                attrs[.foregroundColor] = NSColor.textColor.withAlphaComponent(0.85)
            }
            out.append(NSAttributedString(string: line + "\n", attributes: attrs))
        }
        return out
    }

    @MainActor
    final class Coordinator {
        let player: Player
        weak var scroll: NSScrollView?
        weak var textView: NSTextView?
        var text = ""
        var fontSize: CGFloat = 0
        private var timer: Timer?
        private var last = CACurrentMediaTime()
        private var accumulated: CGFloat = 0
        var pendingTop = false

        init(player: Player) { self.player = player }

        var lineHeight: CGFloat {
            guard let tv = textView, let lm = tv.layoutManager else { return fontSize * 1.5 }
            return lm.defaultLineHeight(for: .monospacedSystemFont(ofSize: fontSize, weight: .regular)) + fontSize * 0.25
        }

        func start() {
            timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.tick() }
            }
        }

        private func tick() {
            let now = CACurrentMediaTime()
            let dt = now - last
            last = now
            if pendingTop, let scroll, scroll.bounds.height > 0 {
                pendingTop = false
                scroll.contentView.setBoundsOrigin(.zero)
                scroll.reflectScrolledClipView(scroll.contentView)
            }
            guard player.running, let scroll, let doc = scroll.documentView else { return }
            let clip = scroll.contentView
            let maxY = max(0, doc.frame.height - clip.bounds.height)
            accumulated += CGFloat(dt * player.speed) * lineHeight
            let step = floor(accumulated)
            guard step >= 1 else { return }
            accumulated -= step
            var origin = clip.bounds.origin
            origin.y = min(origin.y + step, maxY)
            clip.setBoundsOrigin(origin)
            scroll.reflectScrolledClipView(clip)
            if origin.y >= maxY { player.running = false; player.flash("end") }
        }

        func jump(toLine line: Int) {
            guard let scroll else { return }
            let y = line == 0 ? 0 : max(0, CGFloat(line) * lineHeight + (textView?.textContainerInset.height ?? 0) - 24)
            if line == 0 { scroll.contentView.setBoundsOrigin(.zero); scroll.reflectScrolledClipView(scroll.contentView); return }
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.25
                scroll.contentView.animator().setBoundsOrigin(NSPoint(x: 0, y: y))
            }
            scroll.reflectScrolledClipView(scroll.contentView)
        }
    }
}
