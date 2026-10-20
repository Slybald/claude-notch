import SwiftUI

/// Onglet « Notes » : notes rapides. Pas encore codé : vue « bientôt ».
/// Textes dans Resources/{en,fr}.lproj/Notes.strings.
final class NotesModule: NotchModule {
    let id = "notes"
    let symbol = "note.text"
    var title: String { L("Notes", table: "Notes") }

    func makeView() -> AnyView {
        let detail = L("Notes rapides.", table: "Notes")
        return AnyView(ComingSoonView(symbol: symbol, title: title, detail: detail))
    }
}
