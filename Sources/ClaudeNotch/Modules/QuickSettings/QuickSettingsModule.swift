import SwiftUI

/// Onglet « Réglages rapides ». Pas encore codé : vue « bientôt ».
/// Textes dans Resources/{en,fr}.lproj/QuickSettings.strings.
final class QuickSettingsModule: NotchModule {
    let id = "quicksettings"
    let symbol = "switch.2"
    var title: String { L("Réglages rapides", table: "QuickSettings") }

    func makeView() -> AnyView {
        let detail = L("Raccourcis vers les réglages du Mac.", table: "QuickSettings")
        return AnyView(ComingSoonView(symbol: symbol, title: title, detail: detail))
    }
}
