import SwiftUI

/// Onglet « Lecteur » : lecture en cours et calendrier. Pas encore codé : vue « bientôt ».
/// Textes dans Resources/{en,fr}.lproj/Media.strings.
final class MediaModule: NotchModule {
    let id = "media"
    let symbol = "play.circle"
    var title: String { L("Lecteur", table: "Media") }

    func makeView() -> AnyView {
        let detail = L("Lecture en cours et calendrier.", table: "Media")
        return AnyView(ComingSoonView(symbol: symbol, title: title, detail: detail))
    }
}
