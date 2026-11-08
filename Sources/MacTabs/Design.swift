import SwiftUI

// Open UI choices, each switchable live from the Design popover (toolbar sliders icon, or ⌘,).
// Adding a fork: one enum here, one @AppStorage("design.…") key, one row in DesignPanel, and
// set hasForks = true so the toolbar button shows. When Daniel picks: bake the choice in,
// delete the enum and its row, and set hasForks back to false when none are left.
//
// Settled 2026-10-17: icon row right-aligned above the name; source link only in that row;
// chord lines teal.

/// Play mode: notes sliding left along six tab lines (coloured notes; a printed-tab look with the
/// play line at the left; the same with the play line in the middle so played notes stay in
/// view), or falling down six lanes. Daniel 2026-11-08: falling lanes confuse, wants sideways tab.
enum HighwayLayout: String, CaseIterable, Identifiable {
    case strip = "Tab strip", plain = "Printed tab", plainCentre = "Printed, centred", lanes = "Falling lanes"
    var id: String { rawValue }
}

/// Play mode: what each note shows.
enum NoteLabel: String, CaseIterable, Identifiable {
    case fret = "Fret", fretName = "Fret + note"
    var id: String { rawValue }
}

struct DesignPanel: View {
    static let hasForks = true
    @AppStorage("design.highway") private var highway: HighwayLayout = .strip
    @AppStorage("design.noteLabel") private var noteLabel: NoteLabel = .fret

    var body: some View {
        Form {
            Section("Play mode") {
                row("Highway", $highway)
                row("Notes show", $noteLabel)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// One fork as a segmented picker. Use: `row("Chord colour", $chord)`.
    private func row<T: Hashable & Identifiable & RawRepresentable & CaseIterable>(_ title: String, _ value: Binding<T>) -> some View
    where T.RawValue == String, T.AllCases: RandomAccessCollection {
        Picker(title, selection: value) {
            ForEach(T.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
    }
}
