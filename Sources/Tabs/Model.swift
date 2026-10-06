import Foundation

/// One `.tab` file: a `---` YAML-ish frontmatter block followed by monospace text.
struct TabFile: Identifiable, Hashable {
    let url: URL
    var meta: [String: String] = [:]
    var body: String = ""
    var modified: Date = .distantPast

    var id: URL { url }
    var title: String { meta["title"] ?? url.deletingPathExtension().lastPathComponent }
    var artist: String { meta["artist"] ?? "" }
    var scroll: Double { Double(meta["scroll"] ?? "") ?? 1.0 }

    /// Line indices of `[Section]` headers, for jumping.
    var sections: [Int] {
        body.components(separatedBy: "\n").enumerated().compactMap { i, line in
            let t = line.trimmingCharacters(in: .whitespaces)
            return t.hasPrefix("[") && t.hasSuffix("]") ? i : nil
        }
    }

    static func load(_ url: URL) -> TabFile? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        var tab = TabFile(url: url)
        tab.modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
        let lines = text.components(separatedBy: "\n")
        if lines.first?.trimmingCharacters(in: .whitespaces) == "---",
           let end = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) {
            for line in lines[1..<end] {
                guard let colon = line.firstIndex(of: ":") else { continue }
                let key = line[..<colon].trimmingCharacters(in: .whitespaces)
                var value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                if let hash = value.range(of: " #") { value = String(value[..<hash.lowerBound]).trimmingCharacters(in: .whitespaces) }
                tab.meta[key] = value
            }
            tab.body = lines[(end + 1)...].joined(separator: "\n")
        } else {
            tab.body = text
        }
        return tab
    }

    /// Rewrite the file with `scroll` updated (adds a frontmatter block if there is none).
    func saveScroll(_ value: Double) -> TabFile? {
        var meta = self.meta
        meta["scroll"] = String(format: "%.2f", value)
        let order = ["title", "artist", "tuning", "capo", "bpm", "scroll", "source"]
        let keys = order.filter { meta[$0] != nil } + meta.keys.filter { !order.contains($0) }.sorted()
        let head = (["---"] + keys.map { "\($0): \(meta[$0]!)" } + ["---"]).joined(separator: "\n")
        guard (try? (head + "\n" + body).write(to: url, atomically: true, encoding: .utf8)) != nil else { return nil }
        return TabFile.load(url)
    }
}

/// Watches the tabs folder and keeps the list fresh.
@MainActor
final class Library: ObservableObject {
    static let dir: URL = {
        if let env = ProcessInfo.processInfo.environment["TABS_DIR"] { return URL(fileURLWithPath: env) }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Tabs")
    }()

    @Published private(set) var tabs: [TabFile] = []
    private var source: DispatchSourceFileSystemObject?

    init() {
        try? FileManager.default.createDirectory(at: Self.dir, withIntermediateDirectories: true)
        reload()
        let fd = open(Self.dir.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
        src.setEventHandler { [weak self] in self?.reload() }
        src.setCancelHandler { close(fd) }
        src.resume()
        source = src
    }

    func reload() {
        let urls = (try? FileManager.default.contentsOfDirectory(at: Self.dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        tabs = urls
            .filter { ["tab", "txt"].contains($0.pathExtension.lowercased()) }
            .compactMap(TabFile.load)
            .sorted { ($0.artist + $0.title).localizedCaseInsensitiveCompare($1.artist + $1.title) == .orderedAscending }
    }
}
