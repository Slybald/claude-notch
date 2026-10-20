import AppKit
import SwiftUI

// Règles de la notch indépendantes de la fenêtre (visibilité, écran, géométrie), testées sans écran réel.

/// La notch doit-elle être à l'écran ?
enum NotchVisibilityRule {
    struct Inputs {
        /// Claude Desktop ouvert, un `claude` vivant ou une session vivante.
        var claudeOpen = false
        /// Une session au travail, qui attend ou qui vient de finir (`NotchIndicator` différent de `.none`).
        var claudeActive = false
        /// Un module affiche des oreilles (minuteur, lecture…).
        var moduleEars = false
        /// Montrée à la demande : glisser de fichiers vers l'Étagère, raccourci clavier.
        var onDemand = false
        /// Panneau déplié : on ne le retire pas sous la souris quand l'activité s'arrête.
        var expanded = false
        /// Plein écran avec le réglage « Notch masquée ».
        var hiddenForFullScreen = false
        /// « Masquer la notch » en cours.
        var hiddenByUser = false
    }

    static func shouldShow(_ mode: NotchVisibility, _ inputs: Inputs) -> Bool {
        if inputs.onDemand { return true }
        if inputs.hiddenForFullScreen || inputs.hiddenByUser { return false }
        if inputs.expanded { return true }
        switch mode {
        case .always: return true
        case .whenClaudeOpen: return inputs.claudeOpen || inputs.claudeActive || inputs.moduleEars
        case .duringActivity: return inputs.claudeActive || inputs.moduleEars
        }
    }
}

/// Un écran tel que la notch le voit (double de `NSScreen` dans les tests).
struct ScreenCandidate: Equatable {
    var name: String
    var frame: CGRect
    var visibleFrame: CGRect
    /// Hauteur de l'encoche (`safeAreaInsets.top`), 0 sans encoche.
    var safeAreaTop: CGFloat = 0
    /// Largeurs des zones de la barre des menus à gauche et à droite de l'encoche.
    var auxiliaryLeftWidth: CGFloat?
    var auxiliaryRightWidth: CGFloat?
    var isBuiltin = false

    var hasNotch: Bool { safeAreaTop > 0 && auxiliaryLeftWidth != nil && auxiliaryRightWidth != nil }
}

enum NotchScreenPicker {
    /// Largeur de l'encoche virtuelle des écrans sans encoche.
    static let virtualNotchWidth: CGFloat = 200

    /// Index de l'écran choisi (`ScreenChoice` ou nom d'écran) ; un écran nommé absent ou une souris hors de
    /// tout écran retombent sur l'écran intégré.
    static func pick(_ choice: String, among screens: [ScreenCandidate], mouse: CGPoint) -> Int? {
        guard !screens.isEmpty else { return nil }
        let builtin = screens.firstIndex { $0.hasNotch } ?? screens.firstIndex { $0.isBuiltin } ?? 0
        switch choice {
        case ScreenChoice.builtin: return builtin
        case ScreenChoice.main: return 0
        case ScreenChoice.mouse: return screens.firstIndex { contains($0.frame, mouse) } ?? builtin
        default: return screens.firstIndex { $0.name == choice } ?? builtin
        }
    }

    /// Bord haut compris (la souris peut y être pile) ; bord droit exclu (écrans voisins).
    static func contains(_ frame: CGRect, _ point: CGPoint) -> Bool {
        point.x >= frame.minX && point.x < frame.maxX && point.y >= frame.minY && point.y <= frame.maxY
    }

    /// Encoche réelle, ou encoche virtuelle centrée en haut, à la hauteur de la barre des menus de l'écran.
    static func notchRect(on screen: ScreenCandidate, menuBarThickness: CGFloat) -> (rect: CGRect, hasNotch: Bool) {
        let frame = screen.frame
        if screen.hasNotch, let left = screen.auxiliaryLeftWidth, let right = screen.auxiliaryRightWidth {
            let height = screen.safeAreaTop
            return (CGRect(x: frame.minX + left, y: frame.maxY - height, width: frame.width - left - right,
                           height: height), true)
        }
        let menuBar = max(frame.maxY - screen.visibleFrame.maxY, menuBarThickness)
        return (CGRect(x: frame.midX - virtualNotchWidth / 2, y: frame.maxY - menuBar, width: virtualNotchWidth,
                       height: menuBar), false)
    }
}

extension ScreenCandidate {
    init(_ screen: NSScreen) {
        let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        self.init(name: screen.localizedName, frame: screen.frame, visibleFrame: screen.visibleFrame,
                  safeAreaTop: screen.safeAreaInsets.top, auxiliaryLeftWidth: screen.auxiliaryTopLeftArea?.width,
                  auxiliaryRightWidth: screen.auxiliaryTopRightArea?.width,
                  isBuiltin: number.map { CGDisplayIsBuiltin($0.uint32Value) != 0 } ?? false)
    }
}

/// Animations de la notch : le ressort choisi, ou un simple fondu avec « Réduire les animations ».
enum NotchMotion {
    static func animation(_ speed: AnimationSpeed, reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.18) : speed.spring
    }
}

/// Texte du rappel « Notch masquée jusqu'à … ».
enum HiddenNotice {
    static func text(until: Date, now: Date, calendar: Calendar = .current) -> String {
        if until == .distantFuture { return L("Notch masquée jusqu'à réactivation") }
        guard calendar.isDate(until, inSameDayAs: now) else { return L("Notch masquée jusqu'à demain") }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return String(format: L("Notch masquée jusqu'à %@"), formatter.string(from: until))
    }
}

/// Entrée de menu AppKit qui lance une closure (la cible d'un NSMenuItem est faible : l'entrée la garde).
final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(runHandler), keyEquivalent: "")
        target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) indisponible") }

    @objc private func runHandler() { handler() }
}
