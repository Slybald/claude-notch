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

/// Largeur du panneau déplié (mode normal) ; une largeur libre passe par `Preferences.customPanelWidth`.
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

/// Quand la notch est à l'écran.
enum NotchVisibility: String, CaseIterable, Identifiable {
    case always
    /// Claude Desktop ouvert, un `claude` vivant ou une session vivante (ou des oreilles de module).
    case whenClaudeOpen
    /// Une session au travail, qui attend ou qui vient de finir, ou des oreilles de module.
    case duringActivity

    var id: String { rawValue }
}

/// Ce qui déplie le panneau.
enum OpenTrigger: String, CaseIterable, Identifiable {
    case hover
    case click

    var id: String { rawValue }
}

/// Fond du panneau déplié.
enum PanelBackground: String, CaseIterable, Identifiable {
    case black
    case graphite
    case midnight
    case custom

    var id: String { rawValue }

    /// Couleur fixe (hexadécimal sRGB) ; nil pour `custom`, lue dans les réglages.
    var hex: String? {
        switch self {
        case .black: return "000000"
        case .graphite: return "2A2B30"
        case .midnight: return "101B33"
        case .custom: return nil
        }
    }
}

/// Vitesse des ressorts d'ouverture, de fermeture et de changement d'onglet.
enum AnimationSpeed: String, CaseIterable, Identifiable {
    case fast
    case normal
    case gentle

    var id: String { rawValue }

    /// `normal` = le ressort historique de la notch (`notchSpring`).
    var spring: Animation {
        switch self {
        case .fast: return .spring(response: 0.3, dampingFraction: 0.82)
        case .normal: return notchSpring
        case .gentle: return .spring(response: 0.6, dampingFraction: 0.8)
        }
    }
}

/// Masquage temporaire de la notch.
enum HideDuration: String, CaseIterable, Identifiable {
    case oneHour
    /// Jusqu'au début du jour suivant (minuit).
    case untilTomorrow
    case untilReactivated

    var id: String { rawValue }

    func end(from now: Date, calendar: Calendar = .current) -> Date {
        switch self {
        case .oneHour:
            return now.addingTimeInterval(3600)
        case .untilTomorrow:
            let today = calendar.startOfDay(for: now)
            return calendar.date(byAdding: .day, value: 1, to: today) ?? now.addingTimeInterval(86_400)
        case .untilReactivated:
            return .distantFuture
        }
    }
}

/// Écran de la notch : un des choix ci-dessous, ou le nom d'un écran (`NSScreen.localizedName`).
enum ScreenChoice {
    /// Écran avec encoche, sinon l'écran intégré, sinon le premier.
    static let builtin = "builtin"
    /// Écran principal (celui de la barre des menus dans Réglages Système › Moniteurs).
    static let main = "main"
    static let mouse = "mouse"
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
    /// Largeur libre du panneau, par pas de 10 pt.
    static let customWidthRange: ClosedRange<Double> = 460...720
    static let customWidthStep: Double = 10
    static let defaultCustomBackground = "1C1C1E"

    private enum Key {
        /// Ancien booléen « Toujours visible », lu seulement pour la migration vers `visibility`.
        static let alwaysVisible = "alwaysVisible"
        static let visibility = "visibility.mode"
        static let hiddenUntil = "visibility.hiddenUntil"
        static let autoUpdate = "autoUpdate"
        static let openTrigger = "hover.trigger"
        static let closeOnClickOutside = "hover.closeOnClickOutside"
        static let openDelay = "hover.openDelay"
        static let closeDelay = "hover.closeDelay"
        static let haptics = "hover.haptics"
        static let toggleHotKey = "keyboard.togglePanel"
        static let hideHotKey = "keyboard.toggleHidden"
        static let fullScreen = "fullScreen.behavior"
        static let screen = "display.screen"
        static let tabOrder = "tabs.order"
        static let tabEnabled = "tabs.enabled"
        static let defaultTab = "tabs.default"
        static let lastTab = "tabs.last"
        static let accent = "appearance.accent"
        static let panelSize = "appearance.panelSize"
        static let customWidth = "appearance.customPanelWidth"
        static let background = "appearance.background"
        static let customBackground = "appearance.customBackground"
        static let tintCollapsed = "appearance.tintCollapsed"
        static let opacity = "appearance.backgroundOpacity"
        static let shadow = "appearance.shadow"
        static let animationSpeed = "appearance.animationSpeed"
        static let showEars = "appearance.showEars"
        static let hideFromCapture = "privacy.hideFromCapture"
        static let replyFromNotch = "claude.replyFromNotch"

        /// Réglages de la notch remis à zéro par « Rétablir les réglages par défaut » : ni les onglets, ni les
        /// réglages des modules, ni le lancement à l'ouverture de session, ni les mises à jour.
        static let notchSettings = [
            alwaysVisible, visibility, hiddenUntil, openTrigger, closeOnClickOutside, openDelay, closeDelay, haptics,
            toggleHotKey, hideHotKey, fullScreen, screen, accent, panelSize, customWidth, background, customBackground,
            tintCollapsed, opacity, shadow, animationSpeed, showEars, hideFromCapture,
        ]
    }

    private let defaults: UserDefaults

    // MARK: Général

    @Published var visibility: NotchVisibility {
        didSet { defaults.set(visibility.rawValue, forKey: Key.visibility) }
    }

    /// Notch masquée par l'utilisateur jusqu'à cette date (`distantFuture` : jusqu'à réactivation).
    @Published var hiddenUntil: Date? {
        didSet { defaults.set(hiddenUntil, forKey: Key.hiddenUntil) }
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

    @Published var openTrigger: OpenTrigger {
        didSet { defaults.set(openTrigger.rawValue, forKey: Key.openTrigger) }
    }

    /// Le panneau reste ouvert quand la souris le quitte ; un clic ailleurs le ferme.
    @Published var closeOnClickOutside: Bool {
        didSet { defaults.set(closeOnClickOutside, forKey: Key.closeOnClickOutside) }
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

    /// Raccourci global : ouvrir ou fermer le panneau.
    @Published var toggleHotKey: HotKeyChoice {
        didSet {
            defaults.set(toggleHotKey.rawValue, forKey: Key.toggleHotKey)
            // Une combinaison ne sert qu'à une chose.
            if toggleHotKey != .none, hideHotKey == toggleHotKey { hideHotKey = .none }
        }
    }

    /// Raccourci global : masquer ou réafficher la notch.
    @Published var hideHotKey: HotKeyChoice {
        didSet {
            defaults.set(hideHotKey.rawValue, forKey: Key.hideHotKey)
            if hideHotKey != .none, toggleHotKey == hideHotKey { toggleHotKey = .none }
        }
    }

    @Published var fullScreenBehavior: FullScreenBehavior {
        didSet { defaults.set(fullScreenBehavior.rawValue, forKey: Key.fullScreen) }
    }

    /// `ScreenChoice` ou le nom d'un écran.
    @Published var screenChoice: String {
        didSet { defaults.set(screenChoice, forKey: Key.screen) }
    }

    /// Fenêtre de la notch exclue des captures et du partage d'écran (`NSWindow.sharingType = .none`).
    @Published var hideFromCapture: Bool {
        didSet { defaults.set(hideFromCapture, forKey: Key.hideFromCapture) }
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

    /// Largeur libre (pt) ; nil = la taille prédéfinie `panelSize`. Toujours bornée et arrondie au pas.
    @Published var customPanelWidth: Double? {
        didSet {
            // Réaffecter dans son propre didSet ne relance pas l'observateur.
            if let width = customPanelWidth, width != Self.clampWidth(width) { customPanelWidth = Self.clampWidth(width) }
            defaults.set(customPanelWidth, forKey: Key.customWidth)
        }
    }

    @Published var panelBackground: PanelBackground {
        didSet { defaults.set(panelBackground.rawValue, forKey: Key.background) }
    }

    /// Fond libre (hexadécimal sRGB), utilisé avec `panelBackground == .custom`.
    @Published var customBackgroundHex: String {
        didSet { defaults.set(customBackgroundHex, forKey: Key.customBackground) }
    }

    /// Notch repliée teintée elle aussi (écrans sans encoche seulement : sur une vraie encoche elle reste noire).
    @Published var tintCollapsed: Bool {
        didSet { defaults.set(tintCollapsed, forKey: Key.tintCollapsed) }
    }

    /// Opacité du fond du panneau déplié ; la bande de la notch reste toujours opaque.
    @Published var backgroundOpacity: Double {
        didSet { defaults.set(backgroundOpacity, forKey: Key.opacity) }
    }

    @Published var panelShadow: Bool {
        didSet { defaults.set(panelShadow, forKey: Key.shadow) }
    }

    @Published var animationSpeed: AnimationSpeed {
        didSet { defaults.set(animationSpeed.rawValue, forKey: Key.animationSpeed) }
    }

    @Published var showEars: Bool {
        didSet { defaults.set(showEars, forKey: Key.showEars) }
    }

    // MARK: Claude

    /// Répondre depuis la notch (permissions, questions, plans, messages).
    @Published var replyFromNotch: Bool {
        didSet { defaults.set(replyFromNotch, forKey: Key.replyFromNotch) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        func double(_ key: String, _ fallback: Double, _ range: ClosedRange<Double>) -> Double {
            let value = defaults.object(forKey: key) as? Double ?? fallback
            return value.isFinite ? min(max(value, range.lowerBound), range.upperBound) : fallback
        }
        func choice<T: RawRepresentable>(_ key: String, _ fallback: T) -> T where T.RawValue == String {
            defaults.string(forKey: key).flatMap(T.init) ?? fallback
        }
        visibility = defaults.string(forKey: Key.visibility).flatMap(NotchVisibility.init)
            ?? Self.migratedVisibility(alwaysVisible: defaults.object(forKey: Key.alwaysVisible) as? Bool)
        hiddenUntil = defaults.object(forKey: Key.hiddenUntil) as? Date
        autoUpdate = defaults.object(forKey: Key.autoUpdate) as? Bool ?? true
        launchAtLogin = LaunchAgent.isEnabled
        openTrigger = choice(Key.openTrigger, OpenTrigger.hover)
        closeOnClickOutside = defaults.object(forKey: Key.closeOnClickOutside) as? Bool ?? false
        openDelay = double(Key.openDelay, 0.08, Self.openDelayRange)
        closeDelay = double(Key.closeDelay, 0.25, Self.closeDelayRange)
        hapticFeedback = defaults.object(forKey: Key.haptics) as? Bool ?? true
        let toggle = choice(Key.toggleHotKey, HotKeyChoice.none)
        toggleHotKey = toggle
        let hide = choice(Key.hideHotKey, HotKeyChoice.none)
        hideHotKey = hide == toggle ? .none : hide
        fullScreenBehavior = choice(Key.fullScreen, FullScreenBehavior.compact)
        screenChoice = defaults.string(forKey: Key.screen).flatMap { $0.isEmpty ? nil : $0 } ?? ScreenChoice.builtin
        hideFromCapture = defaults.object(forKey: Key.hideFromCapture) as? Bool ?? false
        tabOrder = defaults.stringArray(forKey: Key.tabOrder) ?? []
        tabEnabled = defaults.dictionary(forKey: Key.tabEnabled) as? [String: Bool] ?? [:]
        defaultTab = defaults.string(forKey: Key.defaultTab) ?? Self.lastTabChoice
        lastTab = defaults.string(forKey: Key.lastTab) ?? ModuleRegistry.claudeId
        let hex = defaults.string(forKey: Key.accent).flatMap { Color(hex: $0) != nil ? $0 : nil }
            ?? Self.accentPresets[0]
        accentHex = hex
        accent = Color(hex: hex) ?? Palette.claudeOrange
        panelSize = choice(Key.panelSize, PanelSize.standard)
        customPanelWidth = (defaults.object(forKey: Key.customWidth) as? Double)
            .flatMap { $0.isFinite ? Self.clampWidth($0) : nil }
        panelBackground = choice(Key.background, PanelBackground.black)
        customBackgroundHex = defaults.string(forKey: Key.customBackground)
            .flatMap { Color(hex: $0) != nil ? $0 : nil } ?? Self.defaultCustomBackground
        tintCollapsed = defaults.bool(forKey: Key.tintCollapsed)
        backgroundOpacity = double(Key.opacity, 1, Self.opacityRange)
        panelShadow = defaults.object(forKey: Key.shadow) as? Bool ?? true
        animationSpeed = choice(Key.animationSpeed, AnimationSpeed.normal)
        showEars = defaults.object(forKey: Key.showEars) as? Bool ?? true
        replyFromNotch = defaults.bool(forKey: Key.replyFromNotch)
    }

    /// Ancien « Toujours visible » : vrai → toujours, faux → quand Claude est ouvert ; jamais réglé → toujours.
    static func migratedVisibility(alwaysVisible: Bool?) -> NotchVisibility {
        alwaysVisible == false ? .whenClaudeOpen : .always
    }

    /// Largeur du panneau déplié : demi-largeur en plein écran compact, sinon la largeur choisie.
    func expandedWidth(compact: Bool) -> CGFloat {
        if compact { return Self.compactPanelWidth }
        return customPanelWidth.map { CGFloat($0) } ?? panelSize.width
    }

    static let compactPanelWidth: CGFloat = 270

    static func clampWidth(_ width: Double) -> Double {
        let stepped = (width / customWidthStep).rounded() * customWidthStep
        return min(max(stepped, customWidthRange.lowerBound), customWidthRange.upperBound)
    }

    /// Fond du panneau déplié, opaque (l'opacité est appliquée par la vue).
    var panelColor: Color {
        Color(hex: panelBackground.hex ?? customBackgroundHex) ?? .black
    }

    // MARK: Masquage temporaire

    func hide(_ duration: HideDuration, now: Date = Date(), calendar: Calendar = .current) {
        hiddenUntil = duration.end(from: now, calendar: calendar)
    }

    func showAgain() {
        if hiddenUntil != nil { hiddenUntil = nil }
    }

    func isHidden(at now: Date) -> Bool {
        hiddenUntil.map { $0 > now } ?? false
    }

    // MARK: Réinitialisation

    /// Remet les réglages de la notch à leurs valeurs d'origine (voir `Key.notchSettings`) : mêmes valeurs qu'au
    /// premier lancement, lues par un `Preferences` neuf sur les clés effacées.
    func resetNotchSettings() {
        for key in Key.notchSettings { defaults.removeObject(forKey: key) }
        let fresh = Preferences(defaults: defaults)
        visibility = fresh.visibility
        hiddenUntil = fresh.hiddenUntil
        openTrigger = fresh.openTrigger
        closeOnClickOutside = fresh.closeOnClickOutside
        openDelay = fresh.openDelay
        closeDelay = fresh.closeDelay
        hapticFeedback = fresh.hapticFeedback
        toggleHotKey = fresh.toggleHotKey
        hideHotKey = fresh.hideHotKey
        fullScreenBehavior = fresh.fullScreenBehavior
        screenChoice = fresh.screenChoice
        hideFromCapture = fresh.hideFromCapture
        accentHex = fresh.accentHex
        panelSize = fresh.panelSize
        customPanelWidth = fresh.customPanelWidth
        panelBackground = fresh.panelBackground
        customBackgroundHex = fresh.customBackgroundHex
        tintCollapsed = fresh.tintCollapsed
        backgroundOpacity = fresh.backgroundOpacity
        panelShadow = fresh.panelShadow
        animationSpeed = fresh.animationSpeed
        showEars = fresh.showEars
    }
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
