import SwiftUI

/// Onglet « Presse-papiers » : historique des copies. Pas encore codé : vue « bientôt ».
/// Textes dans Resources/{en,fr}.lproj/Clipboard.strings.
final class ClipboardModule: NotchModule {
    let id = "clipboard"
    let symbol = "doc.on.clipboard"
    var title: String { L("Presse-papiers", table: "Clipboard") }

    func makeView() -> AnyView {
        let detail = L("Historique de ce que tu copies.", table: "Clipboard")
        return AnyView(ComingSoonView(symbol: symbol, title: title, detail: detail))
    }
}
