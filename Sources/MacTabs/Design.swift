import SwiftUI

// Open UI choices, each switchable live from the Design popover (toolbar sliders icon, or ⌘,).
// Adding a fork: one enum here, one @AppStorage("design.…") key, one row in DesignPanel, and
// set hasForks = true so the toolbar button shows. When Daniel picks: bake the choice in,
// delete the enum and its row, and set hasForks back to false when none are left.
//
// Settled 2026-10-17: icon row right-aligned above the name; source link only in that row;
// chord lines teal.

struct DesignPanel: View {
    static let hasForks = false

    var body: some View {
        Form {
            Text("No open design choices.").foregroundStyle(.secondary)
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
