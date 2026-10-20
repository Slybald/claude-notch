import SwiftUI

/// Onglet « Étagère » : fichiers gardés sous la main. Pas encore codé : vue « bientôt ».
/// Textes dans Resources/{en,fr}.lproj/Shelf.strings.
final class ShelfModule: NotchModule {
    let id = "shelf"
    let symbol = "tray"
    var title: String { L("Étagère", table: "Shelf") }

    func makeView() -> AnyView {
        let detail = L("Dépose des fichiers ici pour les garder sous la main.", table: "Shelf")
        return AnyView(ComingSoonView(symbol: symbol, title: title, detail: detail))
    }
}
