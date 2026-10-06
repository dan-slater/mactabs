import SwiftUI
import AppKit

@main
struct TabsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var library = Library()
    @StateObject private var player = Player()

    var body: some Scene {
        WindowGroup("Tabs") {
            ContentView(library: library, player: player)
                .frame(minWidth: 800, minHeight: 500)
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 1200, height: 800)
        .commands { CommandGroup(replacing: .newItem) {} }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ n: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { true }
}

struct ContentView: View {
    @ObservedObject var library: Library
    @ObservedObject var player: Player
    @StateObject private var voice: Voice
    @State private var selection: URL?
    @State private var query = ""
    @State private var monitor: Any?

    init(library: Library, player: Player) {
        self.library = library
        self.player = player
        _voice = StateObject(wrappedValue: Voice(player: player))
    }

    var filtered: [TabFile] {
        let q = query.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? library.tabs : library.tabs.filter { ($0.artist + " " + $0.title).localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        NavigationSplitView {
            List(filtered, selection: $selection) { tab in
                VStack(alignment: .leading, spacing: 2) {
                    Text(tab.title).lineLimit(1)
                    if !tab.artist.isEmpty { Text(tab.artist).font(.caption).foregroundStyle(.secondary) }
                }
                .tag(tab.url)
            }
            .accessibilityIdentifier("tabList")
            .searchable(text: $query, placement: .sidebar, prompt: "Filter")
            .navigationSplitViewColumnWidth(min: 180, ideal: 240)
            .overlay(alignment: .bottom) {
                Text(Library.dir.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                    .font(.caption2).foregroundStyle(.tertiary).padding(6)
            }
        } detail: {
            if let tab = player.tab {
                HSplitView {
                    ScrollText(player: player, text: tab.body)
                    if player.showChords { ChordPanel(body_: tab.body) }
                }
                .overlay(alignment: .bottom) { hud(tab) }
                .navigationTitle(tab.artist.isEmpty ? tab.title : "\(tab.artist) — \(tab.title)")
            } else {
                ContentUnavailableView("No tab open", systemImage: "guitars",
                    description: Text("Drop .tab files into \(Library.dir.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")) and pick one.\n\nspace scroll · ↑↓ speed · [ ] sections · + − size · t top · c chords · v voice"))
            }
        }
        .onChange(of: selection) { _, url in player.open(library.tabs.first { $0.url == url }) }
        .onChange(of: library.tabs) { _, tabs in
            // The folder changed: pick up an edited body for the open tab without resetting playback.
            if let cur = player.tab, let fresh = tabs.first(where: { $0.url == cur.url }), fresh.modified != cur.modified {
                let speed = player.speed
                player.tab = fresh
                player.speed = speed
            }
            if selection == nil, let first = tabs.first { selection = first.url }
        }
        .onAppear {
            installKeys()
            if selection == nil, let first = library.tabs.first { selection = first.url }
            installTestHook()
        }
    }

    func hud(_ tab: TabFile) -> some View {
        HStack(spacing: 14) {
            Image(systemName: player.running ? "pause.fill" : "play.fill")
            Text(String(format: "%.2f l/s", player.speed)).monospacedDigit().accessibilityIdentifier("hudSpeed")
            if let cap = tab.meta["capo"], cap != "0" { Text("capo \(cap)") }
            if let tun = tab.meta["tuning"] { Text(tun) }
            if voice.listening {
                Label(voice.heard.isEmpty ? "listening" : voice.heard, systemImage: "mic.fill").foregroundStyle(.red)
            }
            if !player.status.isEmpty { Text(player.status).foregroundStyle(.orange).accessibilityIdentifier("hudStatus") }
            Spacer()
            Text("space ↑↓ [ ] +− t c v").foregroundStyle(.tertiary)
        }
        .font(.system(.callout, design: .monospaced))
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .padding(12)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("hud")
    }

    func installKeys() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Let the search field keep its keystrokes.
            if let fr = NSApp.keyWindow?.firstResponder as? NSTextView, fr.isFieldEditor { return event }
            if event.modifierFlags.contains(.command) { return event }
            switch event.keyCode {
            case 49: player.toggle()                                    // space
            case 126: player.faster()                                   // ↑
            case 125: player.slower()                                   // ↓
            default:
                switch event.charactersIgnoringModifiers ?? "" {
                case "+", "=": player.fontSize = min(40, player.fontSize + 1)
                case "-", "_": player.fontSize = max(10, player.fontSize - 1)
                case "]": player.nextSection(currentLine(), forward: true)
                case "[": player.nextSection(currentLine(), forward: false)
                case "t", "0": player.top()
                case "c": player.showChords.toggle()
                case "v": voice.toggle()
                default: return event
                }
            }
            return nil
        }
    }

    /// Test hook: `TABS_TEST_FIFO=/path` makes the app read command words from a FIFO
    /// ("faster", "slower", "go", "stop", "top", "state") so the voice path and the player
    /// can be driven without a microphone. "state" appends a JSON line to `$TABS_TEST_FIFO.out`.
    func installTestHook() {
        guard let path = ProcessInfo.processInfo.environment["TABS_TEST_FIFO"] else { return }
        Thread.detachNewThread {
            // One long-lived reader; the harness keeps a writer fd open so lines stream in order.
            while let fh = FileHandle(forReadingAtPath: path) {
                var buf = Data()
                while true {
                    let chunk = fh.availableData
                    if chunk.isEmpty { break }              // writer closed → reopen
                    buf.append(chunk)
                    var lines = String(decoding: buf, as: UTF8.self).components(separatedBy: "\n")
                    buf = Data(lines.removeLast().utf8)      // keep any partial line
                for word in lines where !word.isEmpty {
                    let w = word
                    DispatchQueue.main.sync {
                        if w == "state" {
                            let sv = NSApp.windows.first?.contentView.flatMap { find(NSScrollView.self, in: $0) }
                            let y = sv?.contentView.bounds.origin.y ?? -1
                            // Rendered line fragments vs source lines: equal means nothing wrapped.
                            var frags = 0
                            if let tv = sv?.documentView as? NSTextView, let lm = tv.layoutManager {
                                lm.enumerateLineFragments(forGlyphRange: NSRange(location: 0, length: lm.numberOfGlyphs)) { _, _, _, _, _ in frags += 1 }
                            }
                            let srcLines = (player.tab?.body ?? "").components(separatedBy: "\n").count
                            let s = "{\"running\":\(player.running),\"speed\":\(player.speed),\"y\":\(y),\"fragments\":\(frags),\"lines\":\(srcLines),\"fontSize\":\(player.fontSize),\"tab\":\"\(player.tab?.title ?? "")\",\"chords\":\(player.showChords),\"fileScroll\":\(player.tab?.scroll ?? -1),\"window\":\(NSApp.windows.first?.windowNumber ?? -1)}\n"
                            if let out = FileHandle(forWritingAtPath: path + ".out") { out.seekToEndOfFile(); out.write(s.data(using: .utf8)!) }
                            else { try? s.write(toFile: path + ".out", atomically: true, encoding: .utf8) }
                        } else if w.hasPrefix("shot ") {
                            // Render the window's view tree to a PNG (no Screen Recording permission needed).
                            if let view = NSApp.windows.first?.contentView,
                               let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                                view.cacheDisplay(in: view.bounds, to: rep)
                                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: String(w.dropFirst(5))))
                            }
                        } else { voice.apply(w) }
                    }
                }
                }
            }
        }
    }

    func currentLine() -> Int {
        guard let win = NSApp.keyWindow, let sv = find(NSScrollView.self, in: win.contentView), let tv = sv.documentView as? NSTextView else { return 0 }
        let lineH = (tv.layoutManager?.defaultLineHeight(for: .monospacedSystemFont(ofSize: player.fontSize, weight: .regular)) ?? 24) + player.fontSize * 0.25
        return Int(max(0, sv.contentView.bounds.origin.y - tv.textContainerInset.height + 24) / lineH) + 1
    }

    func find<T: NSView>(_ type: T.Type, in view: NSView?) -> T? {
        guard let view else { return nil }
        if let v = view as? T, (v as? NSScrollView)?.documentView is NSTextView { return v }
        for sub in view.subviews { if let f = find(type, in: sub) { return f } }
        return nil
    }
}
