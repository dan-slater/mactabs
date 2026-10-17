import SwiftUI
import AppKit

// Open UI choices, each switchable live from the Design popover (toolbar sliders icon, or ⌘,).
// Adding a fork: one enum here, one @AppStorage key, one row in DesignPanel.
// When Daniel picks: bake the choice in, delete the enum and its row.

enum TabActionsLayout: String, CaseIterable, Identifiable {
    case above = "Icons above title", toolbar = "Icons in toolbar", dropdown = "Dropdown (before)"
    var id: String { rawValue }
}

enum LinkStyle: String, CaseIterable, Identifiable {
    case always = "Always", hover = "On hover", menu = "Menu only"
    var id: String { rawValue }
}

enum ChordColour: String, CaseIterable, Identifiable {
    case teal = "Teal", blue = "Blue", accent = "Accent", ink = "Bold ink"
    var id: String { rawValue }
    var ns: NSColor {
        switch self {
        case .teal: .systemTeal
        case .blue: .systemBlue
        case .accent: .controlAccentColor
        case .ink: .labelColor
        }
    }
}

enum DesignKey {
    static let tabActions = "design.tabActions"
    static let link = "design.link"
    static let chord = "design.chordColour"
}

struct DesignPanel: View {
    @AppStorage(DesignKey.tabActions) private var tabActions: TabActionsLayout = .above
    @AppStorage(DesignKey.link) private var link: LinkStyle = .always
    @AppStorage(DesignKey.chord) private var chord: ChordColour = .teal

    var body: some View {
        Form {
            row("Tab actions", $tabActions)
            row("Source link", $link)
            row("Chord colour", $chord)
            Button("Reset all") {
                tabActions = .above; link = .always; chord = .teal
            }
            .controlSize(.small)
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func row<T: Hashable & Identifiable & RawRepresentable & CaseIterable>(_ title: String, _ value: Binding<T>) -> some View
    where T.RawValue == String, T.AllCases: RandomAccessCollection {
        Picker(title, selection: value) {
            ForEach(T.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
    }
}
