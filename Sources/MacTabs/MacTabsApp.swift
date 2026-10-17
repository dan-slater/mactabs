import SwiftUI
import AppKit

@main
struct MacTabsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var library = Library()
    @StateObject private var player = Player()

    init() {
        // One window that quits the app when closed, so restoring windows buys nothing, and an
        // app killed with no window open would otherwise relaunch with nothing on screen.
        UserDefaults.standard.register(defaults: ["ApplePersistenceIgnoreState": true])
    }

    var body: some Scene {
        WindowGroup("MacTabs") {
            ContentView(library: library, player: player)
                .frame(minWidth: 800, minHeight: 500)
        }
        .defaultSize(width: 1200, height: 800)
        .commands { CommandGroup(replacing: .newItem) {} }
        Settings { DesignPanel() }
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
    @State private var selection: String?          // Song.id
    @State private var picked: [String: URL] = [:]  // which version of each song was last open
    @State private var query = ""
    @State private var monitor: Any?
    @State private var showDesign = false
    @AppStorage(DesignKey.tabActions) private var tabActions: TabActionsLayout = .above
    @AppStorage(DesignKey.link) private var linkStyle: LinkStyle = .always
    @AppStorage(DesignKey.chord) private var chordColour: ChordColour = .teal

    init(library: Library, player: Player) {
        self.library = library
        self.player = player
        _voice = StateObject(wrappedValue: Voice(player: player))
    }

    var songs: [Song] { Song.group(library.tabs) }

    var filtered: [Song] {
        let q = query.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? songs : songs.filter { ($0.artist + " " + $0.title).localizedCaseInsensitiveContains(q) }
    }

    var currentSong: Song? { songs.first { $0.id == selection } }

    /// Open one version of a song; remembered per song so re-selecting the row comes back to it.
    func openVersion(_ tab: TabFile) {
        picked[tab.songKey] = tab.url
        if selection != tab.songKey { selection = tab.songKey }
        player.open(tab)
    }

    func openSong(_ id: String?) {
        guard let song = songs.first(where: { $0.id == id }) else { player.open(nil); return }
        let tab = song.versions.first { $0.url == picked[song.id] } ?? song.versions[0]
        player.open(tab)
    }

    /// The version a song's row stands for: the open one, else the last picked, else the first.
    func shown(_ song: Song) -> TabFile {
        song.versions.first { $0.url == player.tab?.url }
            ?? song.versions.first { $0.url == picked[song.id] } ?? song.versions[0]
    }

    func cycleVersion() {
        guard let song = currentSong, song.versions.count > 1 else { return }
        let i = song.versions.firstIndex { $0.url == player.tab?.url } ?? 0
        let next = song.versions[(i + 1) % song.versions.count]
        openVersion(next)
        player.flash("version: \(next.version)")
    }

    var body: some View {
        NavigationSplitView {
          VStack(spacing: 0) {   // the folder label sits under the list, never over a row
            List(filtered, selection: $selection) { song in
                SongRow(song: song, link: shown(song).sourceURL, linkName: shown(song).sourceName, style: linkStyle)
                .tag(song.id)
                .contextMenu {
                    ForEach(song.versions) { v in
                        Button { openVersion(v) } label: {
                            if v.url == player.tab?.url { Label(v.version, systemImage: "checkmark") } else { Text(v.version) }
                        }
                    }
                    Divider()
                    if let link = shown(song).sourceURL {
                        Button("Open on \(shown(song).sourceName)") { NSWorkspace.shared.open(link) }
                    }
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting(song.versions.map(\.url)) }
                }
            }
            .accessibilityIdentifier("tabList")
            Text(Library.dir.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                .font(.caption2).foregroundStyle(.tertiary).padding(6)
                .frame(maxWidth: .infinity)
          }
          .searchable(text: $query, placement: .sidebar, prompt: "Filter")
          .navigationSplitViewColumnWidth(min: 180, ideal: 240)
        } detail: {
            if let tab = player.tab {
              VStack(alignment: .leading, spacing: 0) {
                if tabActions == .above {
                    VStack(alignment: .leading, spacing: 6) {
                        TabActions(tab: tab, song: currentSong, player: player, voice: voice, openVersion: openVersion)
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(tab.title).font(.title2.weight(.semibold)).lineLimit(1)
                            if !tab.artist.isEmpty { Text(tab.artist).font(.title3).foregroundStyle(.secondary).lineLimit(1) }
                        }
                    }
                    .padding(.horizontal, 24).padding(.top, 10).padding(.bottom, 2)
                }
                HSplitView {
                    ScrollText(player: player, text: tab.body, chord: chordColour.ns)
                    if player.showChords { ChordPanel(body_: tab.body) }
                }
              }
                .overlay(alignment: .bottom) { hud(tab) }
                // Above-title layout shows the name in the pane, so the toolbar title stays empty.
                .navigationTitle(tabActions == .above ? "" : (tab.artist.isEmpty ? tab.title : "\(tab.artist) — \(tab.title)"))
                .toolbar {
                    if tabActions == .toolbar {
                        ToolbarItem(placement: .primaryAction) {
                            TabActions(tab: tab, song: currentSong, player: player, voice: voice, openVersion: openVersion)
                        }
                    }
                    if let song = currentSong, song.versions.count > 1, tabActions == .dropdown {
                        ToolbarItem(placement: .principal) {
                            let picker = Picker("Version", selection: Binding(
                                get: { player.tab?.url ?? song.versions[0].url },
                                set: { url in if let v = song.versions.first(where: { $0.url == url }) { openVersion(v) } })) {
                                ForEach(song.versions) { v in Text(v.version).tag(v.url) }
                            }
                            .labelsHidden()
                            .fixedSize()
                            .help("\(song.versions.count) versions — press n to cycle")
                            .accessibilityIdentifier("versionPicker")
                            picker.pickerStyle(.menu)
                        }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button { showDesign.toggle() } label: { Image(systemName: "slider.horizontal.3") }
                            .help("Design options (⌘,)")
                            .popover(isPresented: $showDesign, arrowEdge: .bottom) { DesignPanel() }
                    }
                }
            } else {
                ContentUnavailableView("No tab open", systemImage: "guitars",
                    description: Text("Drop .tab files into \(Library.dir.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")) and pick one.\n\nspace scroll · ↑↓ speed · [ ] sections · + − size · t top · c chords · n next version · v voice"))
            }
        }
        .onChange(of: selection) { _, id in
            if player.tab?.songKey != id { openSong(id) }
        }
        .onChange(of: library.tabs) { _, tabs in
            // The folder changed: pick up an edited body for the open tab without resetting playback.
            if let cur = player.tab, let fresh = tabs.first(where: { $0.url == cur.url }), fresh.modified != cur.modified {
                let speed = player.speed
                player.tab = fresh
                player.speed = speed
            } else if let cur = player.tab, !tabs.contains(where: { $0.url == cur.url }) {
                openSong(selection)   // the open version was renamed or deleted: fall back within the song
            }
            if selection == nil, let first = Song.group(tabs).first { selection = first.id }
        }
        .onAppear {
            installKeys()
            if selection == nil, let first = songs.first { selection = first.id }
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
            Text((currentSong?.versions.count ?? 1) > 1 ? "space ↑↓ [ ] +− t c n v" : "space ↑↓ [ ] +− t c v").foregroundStyle(.tertiary)
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
                case "n": cycleVersion()
                case "v": voice.toggle()
                default: return event
                }
            }
            return nil
        }
    }

    /// Test hook: `TABS_TEST_FIFO=/path` makes the app read command words from a FIFO
    /// ("faster", "slower", "go", "stop", "top", "next", "chords", "state") so the voice path and the player
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
                            let srcLines = ((sv?.documentView as? NSTextView)?.string ?? "").components(separatedBy: "\n").count - 1
                            let s = "{\"running\":\(player.running),\"speed\":\(player.speed),\"y\":\(y),\"fragments\":\(frags),\"lines\":\(srcLines),\"fontSize\":\(player.fontSize),\"tab\":\"\(player.tab?.title ?? "")\",\"version\":\"\(player.tab?.version ?? "")\",\"chords\":\(player.showChords),\"fileScroll\":\(player.tab?.scroll ?? -1),\"link\":\"\(player.tab?.sourceURL?.absoluteString ?? "")\",\"window\":\(NSApp.windows.first?.windowNumber ?? -1)}\n"
                            if let out = FileHandle(forWritingAtPath: path + ".out") { out.seekToEndOfFile(); out.write(s.data(using: .utf8)!) }
                            else { try? s.write(toFile: path + ".out", atomically: true, encoding: .utf8) }
                        } else if w.hasPrefix("shot ") {
                            // Render the window's view tree to a PNG (no Screen Recording permission needed).
                            if let view = NSApp.windows.first?.contentView,
                               let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                                view.cacheDisplay(in: view.bounds, to: rep)
                                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: String(w.dropFirst(5))))
                            }
                        } else if w == "next" { cycleVersion()
                        } else if w == "chords" { player.showChords.toggle()
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

/// One sidebar row. Its own view so it can track the pointer for the "On hover" link style.
struct SongRow: View {
    let song: Song
    let link: URL?
    let linkName: String
    let style: LinkStyle
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(song.title).lineLimit(1)
                if !song.artist.isEmpty { Text(song.artist).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            if song.versions.count > 1 {
                Text("\(song.versions.count)")
                    .font(.caption2.monospacedDigit())
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(.quaternary, in: Capsule())
                    .help("\(song.versions.count) versions — right-click, or press n to cycle")
            }
            if let link, style == .always || (style == .hover && hovering) {
                Button { NSWorkspace.shared.open(link) } label: {
                    Image(systemName: "arrow.up.right.square").foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Open on \(linkName)")
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}
