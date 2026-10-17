import SwiftUI
import AppKit

/// The row of icons for the open tab: versions, source page, chords, voice, full screen, export.
/// Sits right-aligned above the song's name.
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
                Button("Save as PDF…") { PDFExport.save(tab) }
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

/// Renders a tab to a PDF on A4, always in light colours, with the name on top.
enum PDFExport {
    @MainActor
    static func save(_ tab: TabFile) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        let name = tab.artist.isEmpty ? tab.title : "\(tab.artist) - \(tab.title)"
        panel.nameFieldStringValue = name + ".pdf"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        write(tab, to: url)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @MainActor
    static func write(_ tab: TabFile, to url: URL) {
        let info = NSPrintInfo()
        info.paperSize = NSSize(width: 595, height: 842)   // A4 in points
        info.topMargin = 40; info.bottomMargin = 40; info.leftMargin = 40; info.rightMargin = 40
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url

        let width = info.paperSize.width - info.leftMargin - info.rightMargin
        let size = ScrollText.fit(11, text: tab.body, width: width - 10)
        let doc = NSMutableAttributedString(string: tab.title + "\n", attributes: [
            .font: NSFont.systemFont(ofSize: 18, weight: .semibold), .foregroundColor: NSColor.labelColor])
        let sub = [tab.artist, tab.meta["capo"].flatMap { $0 == "0" ? nil : "capo \($0)" }, tab.meta["tuning"]]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        doc.append(NSAttributedString(string: sub + "\n\n", attributes: [
            .font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]))
        doc.append(ScrollText.style(tab.body, size: size))

        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: 100))
        view.appearance = NSAppearance(named: .aqua)   // dark text on white paper, whatever the system mode
        view.textStorage?.setAttributedString(doc)
        view.isVerticallyResizable = true
        view.textContainer?.widthTracksTextView = true
        view.layoutManager?.ensureLayout(for: view.textContainer!)
        view.sizeToFit()

        let op = NSPrintOperation(view: view, printInfo: info)
        op.showsPrintPanel = false
        op.showsProgressPanel = false
        op.run()
    }
}
