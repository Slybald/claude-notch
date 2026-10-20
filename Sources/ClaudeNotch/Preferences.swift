import AppKit
import SwiftUI

/// Panneau déplié quand une app est en plein écran sur l'écran de la notch.
enum FullScreenBehavior: String, CaseIterable, Identifiable {
    /// Demi-largeur, informations primaires seulement.
    case compact
    case normal
    /// Notch retirée de l'écran tant que l'app est en plein écran.
    case hidden

    var id: String { rawValue }
}

/// Largeur du panneau déplié (mode normal).
enum PanelSize: String, CaseIterable, Identifiable {
    case compact
    case standard
    case large

    var id: String { rawValue }

    var width: CGFloat {
        switch self {
        case .compact: return 480
        case .standard: return 540
        case .large: return 620
        }
    }
}

/// Préférences de l'app, rangées dans UserDefaults et observables par les vues et le contrôleur.
/// Les valeurs lues sont bornées : un `defaults write` fantaisiste ne casse pas la notch.
final class Preferences: ObservableObject {
    static let shared = Preferences()

    /// `defaultTab` : rouvrir le dernier onglet utilisé.
    static let lastTabChoice = "last"
    /// Couleurs d'accent proposées (hexadécimal sRGB) ; la première est celle de Claude, par défaut.
    static let accentPresets = ["D97757", "F5B83D", "4C8DFF", "2DD4BF", "A78BFA", "F472B6"]
    static let openDelayRange: ClosedRange<Double> = 0...0.5
    static let closeDelayRange: ClosedRange<Double> = 0.1...1.5
    static let opacityRange: ClosedRange<Double> = 0.6...1

    private enum Key {
        static let alwaysVisible = "alwaysVisible"
        static let autoUpdate = "autoUpdate"
        static let openDelay = "hover.openDelay"
        static let closeDelay = "hover.closeDelay"
        static let haptics = "hover.haptics"
        static let fullScreen = "fullScreen.behavior"
        static let tabOrder = "tabs.order"
        static let tabEnabled = "tabs.enabled"
        static let defaultTab = "tabs.default"
        static let lastTab = "tabs.last"
        static let accent = "appearance.accent"
        static let panelSize = "appearance.panelSize"
        static let opacity = "appearance.backgroundOpacity"
        static let showEars = "appearance.showEars"
        static let replyFromNotch = "claude.replyFromNotch"
    }

    private let defaults: UserDefaults

    // MARK: Général

    @Published var alwaysVisible: Bool {
        didSet { defaults.set(alwaysVisible, forKey: Key.alwaysVisible) }
    }

    @Published var launchAtLogin: Bool {
        didSet {
            if launchAtLogin != LaunchAgent.isEnabled { LaunchAgent.setEnabled(launchAtLogin) }
        }
    }

    /// Activée par défaut ; désactivée, les nouvelles versions sont seulement signalées dans le menu.
    @Published var autoUpdate: Bool {
        didSet { defaults.set(autoUpdate, forKey: Key.autoUpdate) }
    }

    /// Secondes de survol avant l'ouverture du panneau.
    @Published var openDelay: Double {
        didSet { defaults.set(openDelay, forKey: Key.openDelay) }
    }

    /// Secondes hors de la zone avant la fermeture.
    @Published var closeDelay: Double {
        didSet { defaults.set(closeDelay, forKey: Key.closeDelay) }
    }

    @Published var hapticFeedback: Bool {
        didSet { defaults.set(hapticFeedback, forKey: Key.haptics) }
    }

    @Published var fullScreenBehavior: FullScreenBehavior {
        didSet { defaults.set(fullScreenBehavior.rawValue, forKey: Key.fullScreen) }
    }

    // MARK: Onglets

    /// Identifiants des modules dans l'ordre choisi ; les modules absents suivent dans l'ordre par défaut.
    @Published var tabOrder: [String] {
        didSet { defaults.set(tabOrder, forKey: Key.tabOrder) }
    }

    /// Choix explicites de l'utilisateur ; un module absent garde son activation par défaut.
    @Published var tabEnabled: [String: Bool] {
        didSet { defaults.set(tabEnabled, forKey: Key.tabEnabled) }
    }

    /// `lastTabChoice` ou l'identifiant d'un module.
    @Published var defaultTab: String {
        didSet { defaults.set(defaultTab, forKey: Key.defaultTab) }
    }

    @Published var lastTab: String {
        didSet { defaults.set(lastTab, forKey: Key.lastTab) }
    }

    // MARK: Apparence

    /// Couleur d'accent en hexadécimal sRGB (« D97757 »).
    @Published var accentHex: String {
        didSet {
            accent = Color(hex: accentHex) ?? Palette.claudeOrange
            defaults.set(accentHex, forKey: Key.accent)
        }
    }

    /// Couleur d'accent prête à l'emploi (calculée une fois par changement).
    private(set) var accent: Color

    @Published var panelSize: PanelSize {
        didSet { defaults.set(panelSize.rawValue, forKey: Key.panelSize) }
    }

    /// Opacité du fond du panneau déplié ; la bande de la notch reste toujours noire.
    @Published var backgroundOpacity: Double {
        didSet { defaults.set(backgroundOpacity, forKey: Key.opacity) }
    }

    @Published var showEars: Bool {
        didSet { defaults.set(showEars, forKey: Key.showEars) }
    }

    // MARK: Claude

    /// Répondre depuis la notch (permissions, questions) : réglage prêt, fonction pas encore branchée.
    @Published var replyFromNotch: Bool {
        didSet { defaults.set(replyFromNotch, forKey: Key.replyFromNotch) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        func double(_ key: String, _ fallback: Double, _ range: ClosedRange<Double>) -> Double {
            let value = defaults.object(forKey: key) as? Double ?? fallback
            return value.isFinite ? min(max(value, range.lowerBound), range.upperBound) : fallback
        }
        alwaysVisible = defaults.bool(forKey: Key.alwaysVisible)
        autoUpdate = defaults.object(forKey: Key.autoUpdate) as? Bool ?? true
        launchAtLogin = LaunchAgent.isEnabled
        openDelay = double(Key.openDelay, 0.08, Self.openDelayRange)
        closeDelay = double(Key.closeDelay, 0.25, Self.closeDelayRange)
        hapticFeedback = defaults.object(forKey: Key.haptics) as? Bool ?? true
        fullScreenBehavior = defaults.string(forKey: Key.fullScreen).flatMap(FullScreenBehavior.init) ?? .compact
        tabOrder = defaults.stringArray(forKey: Key.tabOrder) ?? []
        tabEnabled = defaults.dictionary(forKey: Key.tabEnabled) as? [String: Bool] ?? [:]
        defaultTab = defaults.string(forKey: Key.defaultTab) ?? Self.lastTabChoice
        lastTab = defaults.string(forKey: Key.lastTab) ?? ModuleRegistry.claudeId
        let hex = defaults.string(forKey: Key.accent).flatMap { Color(hex: $0) != nil ? $0 : nil }
            ?? Self.accentPresets[0]
        accentHex = hex
        accent = Color(hex: hex) ?? Palette.claudeOrange
        panelSize = defaults.string(forKey: Key.panelSize).flatMap(PanelSize.init) ?? .standard
        backgroundOpacity = double(Key.opacity, 1, Self.opacityRange)
        showEars = defaults.object(forKey: Key.showEars) as? Bool ?? true
        replyFromNotch = defaults.bool(forKey: Key.replyFromNotch)
    }

    /// Largeur du panneau déplié : demi-largeur en plein écran compact, sinon la taille choisie.
    func expandedWidth(compact: Bool) -> CGFloat {
        compact ? Self.compactPanelWidth : panelSize.width
    }

    static let compactPanelWidth: CGFloat = 270
}

extension Color {
    /// « D97757 » ou « #D97757 » (sRGB) ; nil si le texte n'est pas une couleur.
    init?(hex: String) {
        var text = hex.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        self.init(.sRGB, red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255,
                  blue: Double(value & 0xFF) / 255)
    }

    /// Hexadécimal sRGB (« D97757 »), pour ranger une couleur libre dans les réglages.
    var hexString: String? {
        guard let color = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        func byte(_ component: CGFloat) -> Int { Int((min(max(component, 0), 1) * 255).rounded()) }
        return String(format: "%02X%02X%02X", byte(color.redComponent), byte(color.greenComponent),
                      byte(color.blueComponent))
    }
}
