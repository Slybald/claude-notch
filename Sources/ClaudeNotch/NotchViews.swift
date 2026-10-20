import AppKit
import SwiftUI

enum Palette {
    static let claudeOrange = Color(red: 0xD9 / 255, green: 0x77 / 255, blue: 0x57 / 255)
    /// Couleur d'accent choisie dans les réglages (orange Claude par défaut).
    static var accent: Color { Preferences.shared.accent }
    static let amber = Color(red: 0xF5 / 255, green: 0xB8 / 255, blue: 0x3D / 255)
    static let green = Color(red: 0x4A / 255, green: 0xDE / 255, blue: 0x80 / 255)
    static let red = Color(red: 0xF8 / 255, green: 0x71 / 255, blue: 0x71 / 255)
    static let primary = Color.white
    static let secondary = Color.white.opacity(0.6)
    static let card = Color.white.opacity(0.05)
}

let notchSpring = Animation.spring(response: 0.42, dampingFraction: 0.78)

// MARK: - Forme

/// Bas arrondi et petits évasements concaves en haut, pour se fondre dans la vraie notch.
struct NotchShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set {
            topRadius = newValue.first
            bottomRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let top = max(0, min(topRadius, rect.width / 4, rect.height / 2))
        let bottom = max(0, min(bottomRadius, (rect.width - 2 * top) / 2, rect.height - top))
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.minX + top, y: rect.minY + top),
                          control: CGPoint(x: rect.minX + top, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + top, y: rect.maxY - bottom))
        path.addQuadCurve(to: CGPoint(x: rect.minX + top + bottom, y: rect.maxY),
                          control: CGPoint(x: rect.minX + top, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - top - bottom, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - top, y: rect.maxY - bottom),
                          control: CGPoint(x: rect.maxX - top, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - top, y: rect.minY + top))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY),
                          control: CGPoint(x: rect.maxX - top, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

/// `max` et non `value = nextValue()` : la valeur par défaut d'un voisin écraserait la mesure.
private struct NotchSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        value = CGSize(width: max(value.width, next.width), height: max(value.height, next.height))
    }
}

// MARK: - Racine

struct NotchRootView: View {
    @ObservedObject var model: NotchViewModel
    @ObservedObject var store: SessionStore
    @ObservedObject var registry: ModuleRegistry
    @ObservedObject var prefs: Preferences
    let actions: NotchActions

    private var expanded: Bool { model.isExpanded }
    private var compact: Bool { model.isFullScreen && prefs.fullScreenBehavior == .compact }
    private var ears: EarsChoice {
        EarsChoice.choose(claude: store.indicator, module: registry.moduleEars, showEars: prefs.showEars)
    }
    private var showsEars: Bool { ears != .none }
    private var topRadius: CGFloat { expanded ? 12 : 6 }
    private var bottomRadius: CGFloat { expanded ? (compact ? 18 : 24) : (showsEars ? 12 : 9) }
    private var bodyWidth: CGFloat {
        if expanded { return prefs.expandedWidth(compact: compact) }
        return model.notchSize.width + (showsEars ? 2 * NotchController.earWidth : 0)
    }

    var body: some View {
        VStack(spacing: 0) {
            notch
                // Les couleurs d'accent sont lues au rendu : la vue est reconstruite quand l'accent change.
                .id(prefs.accentHex)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, .dark)
    }

    private var notch: some View {
        ZStack(alignment: .top) {
            if expanded {
                ExpandedPanel(registry: registry, prefs: prefs, selection: $model.selectedTab, compact: compact,
                              notchSize: model.notchSize, actions: actions)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.92, anchor: .top))
                            .animation(notchSpring.delay(0.06)),
                        removal: .opacity.animation(.easeOut(duration: 0.12))
                    ))
            } else {
                switch ears {
                case .claude(let indicator):
                    CollapsedEars(indicator: indicator, ears: store.ears, notchSize: model.notchSize)
                        .transition(.opacity.animation(.easeInOut(duration: 0.18)))
                case .module(let content):
                    ModuleEarsView(ears: content, notchSize: model.notchSize)
                        .transition(.opacity.animation(.easeInOut(duration: 0.18)))
                case .none:
                    EmptyView()
                }
            }
        }
        .frame(width: bodyWidth, alignment: .top)
        .frame(minHeight: model.notchSize.height, alignment: .top)
        .padding(.horizontal, topRadius)
        .background(background)
        .clipShape(NotchShape(topRadius: topRadius, bottomRadius: bottomRadius))
        .shadow(color: .black.opacity(expanded ? 0.45 : 0), radius: 14, y: 6)
        // Replié et sans activité : exactement la notch, donc invisible.
        .opacity(expanded || showsEars ? 1 : 0)
        .background(GeometryReader { proxy in
            Color.clear.preference(key: NotchSizeKey.self, value: proxy.size)
        })
        .onPreferenceChange(NotchSizeKey.self) { size in model.contentSize = size }
        .animation(notchSpring, value: expanded)
        .animation(notchSpring, value: showsEars)
        .animation(notchSpring, value: compact)
        .animation(notchSpring, value: model.selectedTab)
    }

    /// Noir, translucide une fois déplié si les réglages le demandent ; la bande de la notch reste opaque.
    private var background: some View {
        ZStack(alignment: .top) {
            NotchShape(topRadius: topRadius, bottomRadius: bottomRadius)
                .fill(Color.black.opacity(expanded ? prefs.backgroundOpacity : 1))
            Color.black.frame(height: model.notchSize.height)
        }
    }
}

// MARK: - Replié

struct CollapsedEars: View {
    let indicator: NotchIndicator
    let ears: SessionStore.EarsContent?
    let notchSize: CGSize

    var body: some View {
        HStack(spacing: 0) {
            IndicatorGlyph(indicator: indicator)
                .frame(width: NotchController.earWidth)
            Color.clear.frame(width: notchSize.width)
            earText
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(width: NotchController.earWidth)
        }
        .frame(height: notchSize.height)
    }

    /// « 3/7 » (tâches), « 1 » (sessions) ou « 1·6 » avec les agents en orange.
    private var earText: Text {
        guard let ears else { return Text(verbatim: "") }
        if let tasks = ears.tasks { return Text(tasks).foregroundColor(.white.opacity(0.85)) }
        let sessions = Text(verbatim: "\(ears.sessions)").foregroundColor(.white.opacity(0.85))
        guard ears.agents > 0 else { return sessions }
        return sessions + Text(verbatim: "·").foregroundColor(Palette.secondary)
            + Text(verbatim: "\(ears.agents)").foregroundColor(Palette.accent)
    }
}

/// Oreilles d'un module (minuteur, lecture en cours…) : symbole à gauche, texte court à droite.
struct ModuleEarsView: View {
    let ears: ModuleEars
    let notchSize: CGSize

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: ears.symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Palette.accent)
                .frame(width: NotchController.earWidth)
            Color.clear.frame(width: notchSize.width)
            Text(ears.text)
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundColor(.white.opacity(0.85))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(width: NotchController.earWidth)
        }
        .frame(height: notchSize.height)
    }
}

struct IndicatorGlyph: View {
    let indicator: NotchIndicator

    var body: some View {
        switch indicator {
        case .working:
            GlyphSpinner(size: 14)
        case .attention:
            PulsingHand()
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Palette.green)
        case .none:
            EmptyView()
        }
    }
}

/// Spinner à glyphes façon Claude Code (· ✢ ✳ ✶ ✻ ✽).
struct GlyphSpinner: NSViewRepresentable {
    var size: CGFloat = 13

    func makeNSView(context: Context) -> AnimatedGlyphView { AnimatedGlyphView(style: .spinner, size: size) }
    func updateNSView(_ view: AnimatedGlyphView, context: Context) {}
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: AnimatedGlyphView, context: Context) -> CGSize? {
        nsView.intrinsicContentSize
    }
}

/// Main ambre qui pulse : une permission ou une réponse est attendue.
struct PulsingHand: NSViewRepresentable {
    var size: CGFloat = 13

    func makeNSView(context: Context) -> AnimatedGlyphView { AnimatedGlyphView(style: .pulsingHand, size: size) }
    func updateNSView(_ view: AnimatedGlyphView, context: Context) {}
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: AnimatedGlyphView, context: Context) -> CGSize? {
        nsView.intrinsicContentSize
    }
}

/// Animation confiée à Core Animation : images pré-rendues, animées par le serveur de rendu.
/// Un TimelineView SwiftUI relançait tout le layout du NSHostingView à chaque image (~8 % de CPU).
final class AnimatedGlyphView: NSView {
    enum Style {
        case spinner
        case pulsingHand
    }

    private static let glyphs = ["·", "✢", "✳", "✶", "✻", "✽", "✻", "✶", "✳", "✢"]
    private static let glyphInterval: CFTimeInterval = 0.12

    private let style: Style
    private let size: CGFloat
    private let content = CALayer()

    init(style: Style, size: CGFloat) {
        self.style = style
        self.size = size
        super.init(frame: NSRect(x: 0, y: 0, width: size + 4, height: size + 4))
        wantsLayer = true
        content.contentsGravity = .center
        layer?.addSublayer(content)
    }

    required init?(coder: NSCoder) { nil }

    override var intrinsicContentSize: NSSize { NSSize(width: size + 4, height: size + 4) }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        content.frame = bounds
        CATransaction.commit()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        restart()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        restart()
    }

    private func restart() {
        guard let window else {
            content.removeAllAnimations()
            return
        }
        let scale = window.backingScaleFactor
        content.contentsScale = scale
        content.removeAllAnimations()

        switch style {
        case .spinner:
            let font = NSFont.systemFont(ofSize: size, weight: .bold)
            let color = NSColor(Palette.accent)
            let images = Self.glyphs.compactMap { glyph in
                Self.render(scale: scale, box: bounds.size) { rect in
                    let text = NSAttributedString(string: glyph, attributes: [.font: font, .foregroundColor: color])
                    let textSize = text.size()
                    text.draw(at: NSPoint(x: (rect.width - textSize.width) / 2, y: (rect.height - textSize.height) / 2))
                }
            }
            content.contents = images.first
            let animation = CAKeyframeAnimation(keyPath: "contents")
            animation.values = images
            animation.calculationMode = .discrete
            animation.duration = Self.glyphInterval * Double(images.count)
            animation.repeatCount = .infinity
            animation.isRemovedOnCompletion = false
            content.add(animation, forKey: "glyphs")

        case .pulsingHand:
            let configuration = NSImage.SymbolConfiguration(pointSize: size, weight: .semibold)
                .applying(NSImage.SymbolConfiguration(paletteColors: [NSColor(Palette.amber)]))
            guard let symbol = NSImage(systemSymbolName: "hand.raised.fill", accessibilityDescription: nil)?
                .withSymbolConfiguration(configuration) else { return }
            content.contents = Self.render(scale: scale, box: bounds.size) { rect in
                let symbolSize = symbol.size
                symbol.draw(in: NSRect(x: (rect.width - symbolSize.width) / 2, y: (rect.height - symbolSize.height) / 2,
                                       width: symbolSize.width, height: symbolSize.height))
            }
            let opacity = CABasicAnimation(keyPath: "opacity")
            opacity.fromValue = 0.35
            opacity.toValue = 1
            let scaleAnimation = CABasicAnimation(keyPath: "transform.scale")
            scaleAnimation.fromValue = 0.9
            scaleAnimation.toValue = 1.06
            let group = CAAnimationGroup()
            group.animations = [opacity, scaleAnimation]
            group.duration = 0.7
            group.autoreverses = true
            group.repeatCount = .infinity
            group.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            group.isRemovedOnCompletion = false
            content.add(group, forKey: "pulse")
        }
    }

    /// Image bitmap à la bonne densité d'écran.
    private static func render(scale: CGFloat, box: CGSize, draw: (NSRect) -> Void) -> CGImage? {
        guard box.width > 0, box.height > 0,
              let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(box.width * scale),
                                            pixelsHigh: Int(box.height * scale), bitsPerSample: 8, samplesPerPixel: 4,
                                            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                            bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        bitmap.size = box
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        draw(NSRect(origin: .zero, size: box))
        NSGraphicsContext.restoreGraphicsState()
        return bitmap.cgImage
    }
}

// MARK: - Déplié

/// Panneau déplié : bande de la notch, en-tête (onglets, accessoire de l'onglet actif, menu « … »), puis le
/// contenu de l'onglet actif. En plein écran compact : le résumé de chaque module, sans onglets.
struct ExpandedPanel: View {
    @ObservedObject var registry: ModuleRegistry
    @ObservedObject var prefs: Preferences
    @Binding var selection: String
    let compact: Bool
    let notchSize: CGSize
    let actions: NotchActions

    static let spacing: CGFloat = 10
    static let bottomPadding: CGFloat = 14
    static let horizontalPadding: CGFloat = 14
    /// Ligne des onglets, sous la bande de la barre des menus.
    static let headerHeight: CGFloat = 24
    /// Fenêtre de 480 pt moins la place de l'ombre.
    static let maxPanelHeight: CGFloat = 460

    private var width: CGFloat { prefs.expandedWidth(compact: compact) }

    /// Place laissée au contenu sous l'en-tête pour que le panneau tienne dans sa fenêtre.
    private var contentMaxHeight: CGFloat {
        Self.maxPanelHeight - notchSize.height - Self.headerHeight - Self.spacing - Self.bottomPadding
    }

    private var selected: (any NotchModule)? {
        registry.enabled.first { $0.id == selection } ?? registry.enabled.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Self.spacing) {
            header
            if compact {
                compactContent
            } else if let module = selected {
                module.makeView()
                    .id(module.id)
                    .transition(.opacity.animation(.easeOut(duration: 0.15)))
            }
        }
        .padding(.horizontal, Self.horizontalPadding)
        .padding(.bottom, Self.bottomPadding)
        .frame(width: width, alignment: .top)
        .environment(\.notchContentWidth, width - 2 * Self.horizontalPadding)
        .environment(\.notchContentMaxHeight, contentMaxHeight)
    }

    /// La bande à hauteur de barre des menus reste vide : son milieu est la notch physique. L'en-tête vient dessous.
    private var header: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: notchSize.height)
            headerRow.frame(height: Self.headerHeight)
        }
    }

    private var headerRow: some View {
        HStack(spacing: 6) {
            if compact {
                registry.module(ModuleRegistry.claudeId)?.makeTabIcon()
                Spacer(minLength: 8)
            } else {
                NotchTabBar(modules: registry.enabled, selection: $selection)
                Spacer(minLength: 8)
                selected?.makeHeaderAccessory()
            }
            NotchMoreMenu(prefs: prefs, actions: actions)
        }
    }

    /// Résumé de chaque module activé qui en fournit un, dans l'ordre des onglets.
    private var compactContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(registry.enabled.map { $0.id }, id: \.self) { id in
                registry.module(id)?.makeCompactView()
            }
        }
    }
}

/// Barre d'onglets en icônes. L'onglet actif porte aussi son titre, dans une capsule qui glisse d'un onglet à
/// l'autre. Clic, ou survol de 0,2 s, pour changer d'onglet (en passant dessus, rien ne change).
struct NotchTabBar: View {
    let modules: [any NotchModule]
    @Binding var selection: String

    @Namespace private var namespace
    @State private var hovered: String?

    static let hoverDelay: TimeInterval = 0.2

    var body: some View {
        HStack(spacing: 2) {
            ForEach(modules.map { $0.id }, id: \.self) { id in
                if let module = modules.first(where: { $0.id == id }) {
                    tab(module)
                }
            }
        }
        .animation(notchSpring, value: selection)
    }

    private func tab(_ module: any NotchModule) -> some View {
        let active = module.id == selection
        return HStack(spacing: 5) {
            Group {
                if let icon = module.makeTabIcon() {
                    icon
                } else {
                    Image(systemName: module.symbol)
                        .font(.system(size: 12, weight: .semibold))
                }
            }
            .frame(width: 17, height: 17)
            if active {
                Text(module.title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .fixedSize()
                    .transition(.opacity)
            }
        }
        .foregroundColor(active ? Palette.primary : .white.opacity(hovered == module.id ? 0.85 : 0.5))
        .padding(.horizontal, active ? 8 : 5)
        .frame(height: 22)
        .background {
            if active {
                Capsule()
                    .fill(Color.white.opacity(0.12))
                    .matchedGeometryEffect(id: "active-tab", in: namespace)
            }
        }
        .contentShape(Capsule())
        .onTapGesture { selection = module.id }
        .onHover { inside in hover(module.id, inside) }
        .help(module.title)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(module.title)
        .accessibilityAddTraits(active ? [.isButton, .isSelected] : .isButton)
    }

    private func hover(_ id: String, _ inside: Bool) {
        if inside {
            hovered = id
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.hoverDelay) {
                if hovered == id, selection != id { selection = id }
            }
        } else if hovered == id {
            hovered = nil
        }
    }
}

/// Menu « … » de l'en-tête.
struct NotchMoreMenu: View {
    @ObservedObject var prefs: Preferences
    let actions: NotchActions

    var body: some View {
        Menu {
            Button("Réglages…", action: actions.openSettings)
                .keyboardShortcut(",", modifiers: .command)
            Divider()
            Toggle("Toujours visible", isOn: $prefs.alwaysVisible)
            Toggle("Lancer à l'ouverture de session", isOn: $prefs.launchAtLogin)
            Divider()
            Button("Effacer les sessions terminées", action: actions.clearEnded)
            Divider()
            HookMenuItems(setup: .shared)
            Divider()
            UpdateMenuItems(updater: .shared, prefs: prefs)
            Divider()
            Button("Quitter Claude Notch", action: actions.quit)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(0.8))
                .frame(width: 22, height: 18)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

struct StatusPill: View {
    let text: String
    let active: Bool

    var body: some View {
        HStack(spacing: 4) {
            Text(text)
            Circle()
                .fill(active ? Palette.green : Color.white.opacity(0.25))
                .frame(width: 6, height: 6)
        }
        .font(.system(size: 10.5, weight: .medium))
        .foregroundColor(active ? .white.opacity(0.85) : Palette.secondary)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.white.opacity(0.07)))
    }
}

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 5) {
            Text("Aucune session en cours")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Palette.primary)
            Text("Lance `claude` dans un terminal ou ouvre l'onglet Code de Claude Desktop.")
                .font(.system(size: 11))
                .foregroundColor(Palette.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
    }
}

struct DesktopRow: View {
    let frontmost: Bool
    let open: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "macwindow")
                .font(.system(size: 12))
                .foregroundColor(Palette.secondary)
            Text(verbatim: "Claude Desktop")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Palette.primary)
            Text(frontmost ? L("Au premier plan") : L("Ouvert"))
                .font(.system(size: 11))
                .foregroundColor(Palette.secondary)
            Spacer()
            // Déjà devant : rien à ouvrir, un bouton sans effet visible laisserait croire à une panne.
            if !frontmost {
                Text("Ouvrir")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.white.opacity(0.12)))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.03)))
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture { if !frontmost { open() } }
    }
}

// MARK: - Carte de session

struct SessionCard: View {
    let session: Session
    let now: Date
    @Binding var showTasks: Bool
    let onTap: () -> Void

    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                PhaseIcon(phase: session.phase)
                    .frame(width: 16, height: 16)
                Text(session.projectName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Palette.primary)
                    .lineLimit(1)
                SourcePill(text: session.sourceLabel)
                if let title = session.title {
                    Text(title)
                        .font(.system(size: 11))
                        .foregroundColor(Palette.secondary)
                        .lineLimit(1)
                        .layoutPriority(-1)
                }
                if !session.activeAgents.isEmpty {
                    let count = session.activeAgents.count
                    Text(String(format: L(count, one: "%d agent", other: "%d agents"), count))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Palette.accent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Palette.accent.opacity(0.15)))
                }
                Spacer(minLength: 8)
                Text(timeText)
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundColor(Palette.secondary)
            }
            activityLine
            if !session.tasks.isEmpty {
                taskRow
                if showTasks { checklist }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(hovering ? 0.08 : 0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Palette.amber.opacity(session.phase.needsAttention ? 0.9 : 0), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture(perform: onTap)
        .onHover { hovering = $0 }
        .help(session.title ?? session.cwd ?? "")
    }

    // MARK: Lignes

    private var activityLine: some View {
        let status = session.status
        return HStack(spacing: 6) {
            Text(status.label)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundColor(status.color)
                .lineLimit(1)
                .layoutPriority(1)
            if let detail = status.detail {
                Text(detail)
                    .font(.system(size: 11, design: status.isCode ? .monospaced : .default))
                    .foregroundColor(.white.opacity(0.75))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }

    private var taskRow: some View {
        let done = session.completedTaskCount
        let total = session.tasks.count
        return HStack(spacing: 8) {
            ProgressBar(fraction: total > 0 ? CGFloat(done) / CGFloat(total) : 0)
                .frame(width: 72, height: 4)
            Text(verbatim: "\(done)/\(total)")
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundColor(.white.opacity(0.8))
            if let current = session.currentTask {
                Text(current.activeForm ?? current.subject)
                    .font(.system(size: 11))
                    .foregroundColor(Palette.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Button {
                withAnimation(notchSpring) { showTasks.toggle() }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Palette.secondary)
                    .rotationEffect(.degrees(showTasks ? 180 : 0))
                    .frame(width: 20, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var checklist: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(session.tasks) { task in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(task.status.symbol)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(task.status.color)
                        .frame(width: 12)
                    Text(task.subject)
                        .font(.system(size: 11))
                        .foregroundColor(task.status == .completed ? Palette.secondary : .white.opacity(0.85))
                        .strikethrough(task.status == .completed, color: Palette.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(.leading, 2)
        .padding(.top, 2)
    }

    private var timeText: String {
        if session.inTurn, let start = session.turnStart {
            return Self.duration(now.timeIntervalSince(start))
        }
        return Self.relative(now.timeIntervalSince(session.endedAt ?? session.lastActivity))
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        if total < 60 { return String(format: L("%d s"), total) }
        if total < 3600 { return String(format: "%d:%02d", total / 60, total % 60) }
        return String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }

    static func relative(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        if total < 10 { return L("à l'instant") }
        if total < 60 { return String(format: L("il y a %d s"), total) }
        if total < 3600 { return String(format: L("il y a %d min"), total / 60) }
        if total < 86_400 { return String(format: L("il y a %d h"), total / 3600) }
        return String(format: L("il y a %d j"), total / 86_400)
    }
}

struct SourcePill: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(.white.opacity(0.7))
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.white.opacity(0.08)))
    }
}

struct ProgressBar: View {
    let fraction: CGFloat

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.12))
                Capsule()
                    .fill(Palette.green)
                    .frame(width: proxy.size.width * min(max(fraction, 0), 1))
            }
        }
    }
}

struct PhaseIcon: View {
    let phase: Phase

    var body: some View {
        switch phase {
        case .thinking, .tool, .compacting:
            GlyphSpinner(size: 12)
        case .waitingPermission:
            PulsingHand(size: 12)
        case .waitingAnswer:
            symbol("questionmark.bubble.fill", Palette.amber)
        case .planReview:
            symbol("checklist", Palette.amber)
        case .done:
            symbol("checkmark.circle.fill", Palette.green)
        case .error:
            symbol("exclamationmark.triangle.fill", Palette.red)
        case .ready:
            symbol("circle.fill", Color.white.opacity(0.35), size: 7)
        case .ended:
            symbol("xmark.circle", Palette.secondary)
        }
    }

    private func symbol(_ name: String, _ color: Color, size: CGFloat = 12) -> some View {
        Image(systemName: name)
            .font(.system(size: size, weight: .semibold))
            .foregroundColor(color)
    }
}

// MARK: - Présentation

struct SessionStatus {
    let label: String
    let detail: String?
    let isCode: Bool
    let color: Color
}

extension Session {
    var status: SessionStatus {
        switch phase {
        case .ready:
            return SessionStatus(label: L("Prête"), detail: lastMessage, isCode: false, color: Palette.secondary)
        case .thinking:
            return SessionStatus(label: L("Réfléchit…"), detail: lastPrompt.map { String(format: L("« %@ »"), $0) },
                                 isCode: false, color: Palette.accent)
        case .tool:
            let tool = currentTool
            return SessionStatus(label: tool?.label ?? L("Outil"), detail: tool?.detail, isCode: tool?.isCode ?? false,
                                 color: Palette.accent)
        case .waitingPermission:
            return SessionStatus(label: L("Attend ta permission"), detail: attentionText, isCode: true,
                                 color: Palette.amber)
        case .waitingAnswer:
            return SessionStatus(label: L("Attend ta réponse"), detail: attentionText, isCode: false,
                                 color: Palette.amber)
        case .planReview:
            return SessionStatus(label: L("Plan à valider"), detail: attentionText, isCode: false, color: Palette.amber)
        case .done:
            return SessionStatus(label: L("Terminé"), detail: lastMessage, isCode: false, color: Palette.green)
        case .error:
            return SessionStatus(label: L("Erreur"), detail: errorText, isCode: false, color: Palette.red)
        case .compacting:
            return SessionStatus(label: L("Compacte le contexte"), detail: nil, isCode: false,
                                 color: Palette.accent)
        case .ended:
            return SessionStatus(label: L("Session terminée"), detail: nil, isCode: false,
                                 color: Palette.secondary)
        }
    }
}

extension TaskItem.Status {
    var symbol: String {
        switch self {
        case .completed: return "✓"
        case .inProgress: return "◐"
        case .pending: return "○"
        }
    }

    var color: Color {
        switch self {
        case .completed: return Palette.green
        case .inProgress: return Palette.accent
        case .pending: return Palette.secondary
        }
    }
}
