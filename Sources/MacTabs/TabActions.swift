import SwiftUI
import AppKit

/// The row of icons for the open tab: versions, source page, chords, voice, full screen, export.
/// Where it sits is a Design choice (above the title, in the toolbar, or the old dropdown).
struct TabActions: View {
    let tab: TabFile
    let song: Song?
    @ObservedObject var player: Player
    @ObservedObject var voice: Voice
    let openVersion: (TabFile) -> Void

    var body: some View {
        HStack(spacing: 16) {
            if let song, song.versions.count > 1 {
                Menu {
                    ForEach(song.versions) { v in
                        Button { openVersion(v) } label: {
                            if v.url == tab.url { Label(v.version, systemImage: "checkmark") } else { Text(v.version) }
                        }
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "square.stack")
                        Text("\(song.versions.count)").font(.caption.monospacedDigit())
                    }
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("\(song.versions.count) versions (n cycles)")
            }
            if let link = tab.sourceURL {
                icon("arrow.up.right.square", "Open on \(tab.sourceName)") { NSWorkspace.shared.open(link) }
            }
            icon("square.grid.2x2", "Chord diagrams (c)", on: player.showChords) { player.showChords.toggle() }
            icon(voice.listening ? "mic.fill" : "mic", "Voice commands (v)", on: voice.listening) { voice.toggle() }
            icon("arrow.up.left.and.arrow.down.right", "Full screen (⌃⌘F)") {
                NSApp.keyWindow?.toggleFullScreen(nil)
            }
            Menu {
                ShareLink(item: tab.url) { Label("Share file…", systemImage: "square.and.arrow.up") }
                Button("Copy tab text") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(tab.body, forType: .string)
                }
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([tab.url]) }
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Export")
        }
        .imageScale(.medium)
        .foregroundStyle(.secondary)
    }

    private func icon(_ name: String, _ help: String, on: Bool = false, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: name) }
            .buttonStyle(.borderless)
            .foregroundStyle(on ? Color.accentColor : Color.secondary)
            .help(help)
    }
}
