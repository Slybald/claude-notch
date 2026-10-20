import SwiftUI

/// Onglet « Minuteur ». Pas encore codé : vue « bientôt ».
/// Textes dans Resources/{en,fr}.lproj/Timer.strings.
final class TimerModule: NotchModule {
    let id = "timer"
    let symbol = "timer"
    var title: String { L("Minuteur", table: "Timer") }

    func makeView() -> AnyView {
        let detail = L("Minuteurs et chronomètre.", table: "Timer")
        return AnyView(ComingSoonView(symbol: symbol, title: title, detail: detail))
    }
}
