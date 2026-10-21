import AppKit
import SwiftUI

// Vues de la notch détachée : poignée de l'angle, goutte, bulle en barillet, panneau de la bulle.

/// État des vues de la bulle, tenu par `BubbleController`.
final class BubbleModel: ObservableObject {
    /// Centre de la bulle dans sa fenêtre (y vers le bas) et taille de la fenêtre : la bulle reste au même endroit de
    /// l'écran quand la fenêtre grandit pour le panneau.
    @Published private(set) var centerInWindow = CGPoint(x: BubbleController.bubbleWindowSize.width / 2,
                                                         y: BubbleController.bubbleWindowSize.height / 2)
    @Published private(set) var windowSize = BubbleController.bubbleWindowSize
    /// Crans du barillet (voir `Revolver`).
    @Published var turn = 0
    /// Bulle aimantée par la notch : son bord s'allume.
    @Published var nearNotch = false
    /// Échelle de la bulle : 0,72 au décollage (taille de la goutte), puis rebond jusqu'à 1.
    @Published var scale: CGFloat = 1
    /// « Réduire les animations » : bulle à demi transparente qui suit la souris avant le décollage.
    @Published var ghost = false
    /// Goutte en cours (fenêtre de la goutte) ; nil = rien à dessiner.
    @Published var goo: GooState?

    func layout(center: CGPoint, window: CGSize) {
        if centerInWindow != center { centerInWindow = center }
        if windowSize != window { windowSize = window }
    }

    /// Point de la fenêtre d'où sort (et où rentre) le panneau.
    var anchor: UnitPoint {
        UnitPoint(x: windowSize.width > 0 ? centerInWindow.x / windowSize.width : 0.5,
                  y: windowSize.height > 0 ? centerInWindow.y / windowSize.height : 0.5)
    }
}

/// Ce que la bulle demande au contrôleur.
struct BubbleInput {
    var open: () -> Void = {}
    var rotate: (Int) -> Void = { _ in }
    var reattach: () -> Void = {}
    var moveBegan: () -> Void = {}
    var moved: () -> Void = {}
    var moveEnded: () -> Void = {}
    var panelSized: (CGSize) -> Void = { _ in }
}

// MARK: - Poignée

/// Angle bas droit du panneau déplié : un arc et un point, qui s'allument au survol. Appui maintenu puis glisser : la
/// notch se décolle. VoiceOver : un bouton « Détacher la notch ».
struct DetachHandle: View {
    let begin: () -> Void
    let detach: () -> Void
    /// Rayon du coin du panneau, pour que l'arc le suive.
    var cornerRadius: CGFloat = 24

    @State private var hovering = false
    @State private var pressing = false

    static let size: CGFloat = 26

    var body: some View {
        DetachGrip(cornerRadius: cornerRadius, lit: hovering || pressing, pressed: pressing)
            .frame(width: Self.size, height: Self.size)
            .contentShape(Rectangle())
            .onHover { inside in
                guard inside != hovering else { return }
                hovering = inside
                if inside { NSCursor.openHand.push() } else { NSCursor.pop() }
            }
            .onDisappear { if hovering { NSCursor.pop() } }
            .onLongPressGesture(minimumDuration: 0.3, maximumDistance: 8, perform: begin,
                                onPressingChanged: { pressing = $0 })
            .help(L("Maintiens puis glisse pour détacher la notch", table: "Bubble"))
            .accessibilityElement()
            .accessibilityLabel(Text(L("Détacher la notch", table: "Bubble")))
            .accessibilityHint(Text(L("La notch devient une bulle à poser où tu veux.", table: "Bubble")))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { detach() }
    }
}

/// Dessin de la poignée, seul (rendus PNG).
struct DetachGrip: View {
    var cornerRadius: CGFloat = 24
    var lit = false
    var pressed = false

    var body: some View {
        Canvas { context, size in
            // Arc concentrique au coin du panneau, à 6 pt du bord, et un point au milieu de l'arc.
            let center = CGPoint(x: size.width - cornerRadius, y: size.height - cornerRadius)
            let radius = cornerRadius - 6
            var arc = Path()
            arc.addArc(center: center, radius: radius, startAngle: .degrees(8), endAngle: .degrees(82), clockwise: false)
            let color = lit ? Palette.accent : Color.white.opacity(0.32)
            context.stroke(arc, with: .color(color), style: StrokeStyle(lineWidth: pressed ? 3 : 2.2, lineCap: .round))
            let dot = CGPoint(x: center.x + radius * cos(.pi / 4), y: center.y + radius * sin(.pi / 4))
            let dotRadius: CGFloat = pressed ? 3.4 : 2.6
            context.fill(Path(ellipseIn: CGRect(x: dot.x - dotRadius, y: dot.y - dotRadius, width: 2 * dotRadius,
                                                height: 2 * dotRadius)), with: .color(color))
        }
        .animation(.easeOut(duration: 0.12), value: lit)
        .animation(.easeOut(duration: 0.12), value: pressed)
    }
}

// MARK: - Goutte

/// Fenêtre de la goutte : redessinée à chaque image tant qu'une animation est en cours, rien sinon.
struct GooView: View {
    @ObservedObject var bubble: BubbleModel
    let color: Color

    var body: some View {
        if let goo = bubble.goo {
            TimelineView(.animation) { timeline in
                GooCanvas(shapes: goo.shapes(at: timeline.date), color: color)
            }
        }
    }
}

/// Formes floutées puis seuillées : les cercles se fondent en liquide (métaballes), le col s'amincit et se rompt.
struct GooCanvas: View {
    let shapes: GooShapes
    let color: Color

    var body: some View {
        Canvas { context, _ in
            // Ajoutés dans cet ordre, appliqués dans l'ordre inverse : flou, puis seuil.
            context.addFilter(.alphaThreshold(min: 0.5, color: color))
            context.addFilter(.blur(radius: Goo.blur))
            context.drawLayer { layer in
                layer.fill(Path(roundedRect: shapes.body, cornerRadius: shapes.bodyRadius, style: .continuous),
                           with: .color(.black))
                for circle in shapes.neck + [shapes.drop] where circle.radius > 0.5 {
                    layer.fill(Path(ellipseIn: CGRect(x: circle.center.x - circle.radius,
                                                      y: circle.center.y - circle.radius,
                                                      width: 2 * circle.radius, height: 2 * circle.radius)),
                               with: .color(.black))
                }
            }
        }
    }
}

// MARK: - Bulle

/// Racine de la fenêtre de la bulle : la bulle en barillet, ou le panneau qui en sort.
struct BubbleRootView: View {
    @ObservedObject var model: NotchViewModel
    @ObservedObject var bubble: BubbleModel
    @ObservedObject var store: SessionStore
    @ObservedObject var registry: ModuleRegistry
    @ObservedObject var prefs: Preferences
    let actions: NotchActions
    let input: BubbleInput

    private var motion: Animation { NotchMotion.animation(prefs.animationSpeed, reduceMotion: model.reduceMotion) }
    private var panelOpen: Bool { model.bubble == .bubblePanel }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if panelOpen {
                panel
                    .transition(model.reduceMotion ? .opacity
                                : .scale(scale: 0.25, anchor: bubble.anchor).combined(with: .opacity))
            } else {
                RevolverBubble(tabs: registry.enabled.map { RevolverBubble.Tab($0) }, turn: bubble.turn,
                               activity: registry.earTabs(claude: store.indicator, claudeEars: store.ears),
                               claudeEars: store.ears, fill: prefs.panelColor, nearNotch: bubble.nearNotch,
                               reduceMotion: model.reduceMotion, input: input)
                    .scaleEffect(bubble.scale)
                    .opacity(bubble.ghost ? 0.55 : 1)
                    .position(bubble.centerInWindow)
                    .transition(model.reduceMotion ? .opacity
                                : .scale(scale: 0.6, anchor: bubble.anchor).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .environment(\.colorScheme, .dark)
        .animation(motion, value: panelOpen)
        .animation(.easeOut(duration: 0.15), value: bubble.ghost)
        // Les couleurs d'accent sont lues au rendu : la vue est reconstruite quand l'accent change.
        .id(prefs.accentHex)
    }

    /// Le panneau de la notch (onglets, menu « … », contenu), dans une forme arrondie au lieu de la notch.
    private var panel: some View {
        ExpandedPanel(registry: registry, prefs: prefs, selection: $model.selectedTab,
                      editingTabs: $model.isEditingTabs, compact: false,
                      notchSize: CGSize(width: 0, height: BubbleRootView.panelTopInset),
                      tabAnimation: motion, reduceMotion: model.reduceMotion, actions: actions)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(prefs.panelColor.opacity(prefs.backgroundOpacity)))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(.white.opacity(0.08)))
            .background(GeometryReader { proxy in
                Color.clear.preference(key: BubblePanelSizeKey.self, value: proxy.size)
            })
            .onPreferenceChange(BubblePanelSizeKey.self) { input.panelSized($0) }
            .shadow(color: .black.opacity(prefs.panelShadow ? 0.45 : 0), radius: 14, y: 6)
            .animation(motion, value: model.selectedTab)
            .animation(motion, value: model.isEditingTabs)
            .padding(BubbleGeometry.panelMargin)
    }

    /// Marge au-dessus de la barre d'onglets (la notch y a la bande de la barre des menus).
    static let panelTopInset: CGFloat = 8
}

/// `max`, comme `NotchSizeKey` : la valeur par défaut d'un voisin n'écrase pas la mesure.
private struct BubblePanelSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        value = CGSize(width: max(value.width, next.width), height: max(value.height, next.height))
    }
}

/// Bulle ronde, onglets en barillet de revolver : une chambre par onglet, l'onglet du haut est l'onglet actif (repère
/// fixe au-dessus). Le moyeu porte son titre. Anneau et pastille : les activités des intercalaires.
///
/// Souris : clic au centre ou sur l'onglet du haut = ouvrir ; clic sur une autre chambre = la tourner en haut ; glisser
/// sur les chambres = tourner, cran par cran ; glisser ailleurs = déplacer ; double-clic sur le bord = rattacher. La
/// molette arrive par la vue AppKit (`BubbleHostingView`).
struct RevolverBubble: View {
    struct Tab: Identifiable, Equatable {
        let id: String
        let title: String
        let symbol: String

        init(_ module: any NotchModule) {
            id = module.id
            title = module.title
            symbol = module.symbol
        }

        init(id: String, title: String, symbol: String) {
            self.id = id
            self.title = title
            self.symbol = symbol
        }
    }

    let tabs: [Tab]
    let turn: Int
    let activity: [EarTab]
    let claudeEars: SessionStore.EarsContent?
    let fill: Color
    var nearNotch = false
    var reduceMotion = false
    var input = BubbleInput()

    private enum Drag {
        case pending(Revolver.Zone)
        case rotating(RevolverDrag)
        case moving
    }

    @State private var drag: Drag?

    private static let diameter = BubbleGeometry.diameter
    private var center: CGPoint { CGPoint(x: Self.diameter / 2, y: Self.diameter / 2) }
    private var revolver: Revolver { Revolver(count: tabs.count, turn: turn) }
    private var chamber: CGFloat { Revolver.chamberDiameter(count: tabs.count) }
    private var activeTab: Tab? { tabs.indices.contains(revolver.activeIndex) ? tabs[revolver.activeIndex] : nil }

    /// Activités par onglet (le « +N » rendu à chacune de ses activités).
    private var activityById: [String: EarTab] {
        var result: [String: EarTab] = [:]
        for tab in activity {
            if case .more(let hidden) = tab.kind {
                for inner in hidden { result[inner.id] = inner }
            } else {
                result[tab.id] = tab
            }
        }
        return result
    }

    private var top: EarTab? { activity.first.flatMap { tab in
        if case .more(let hidden) = tab.kind { return hidden.first }
        return tab
    } }

    private func accent(_ tab: EarTab) -> Color { tab.accentHex.flatMap { Color(hex: $0) } ?? Palette.accent }

    private var rotation: Animation {
        reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.32, dampingFraction: 0.62)
    }

    var body: some View {
        ZStack {
            Circle().fill(fill)
            cylinder
            firingMark
            hub
            Circle()
                .strokeBorder(rimColor, lineWidth: nearNotch ? 3 : (top == nil ? 1 : 2.5))
        }
        .frame(width: Self.diameter, height: Self.diameter)
        .contentShape(Circle())
        .overlay(alignment: .bottom) { pill }
        .shadow(color: .black.opacity(0.4), radius: 10, y: 5)
        .gesture(gesture)
        .help(L("Centre : ouvrir. Molette ou glisser sur les onglets : tourner. Bord : déplacer ; double-clic pour "
                + "rattacher à la notch.", table: "Bubble"))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(L("Bulle de la notch", table: "Bubble")))
        .accessibilityValue(Text(accessibilityValue))
        .accessibilityHint(Text(L("Balaie vers le haut ou le bas pour tourner le barillet, active pour ouvrir.",
                                  table: "Bubble")))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: input.rotate(1)
            case .decrement: input.rotate(-1)
            @unknown default: break
            }
        }
        .accessibilityAction { input.open() }
        .accessibilityAction(named: Text(L("Rattacher à la notch", table: "Bubble"))) { input.reattach() }
    }

    private var accessibilityValue: String {
        guard let activeTab else { return "" }
        var value = String(format: L("%@, onglet %d sur %d", table: "Bubble"), activeTab.title,
                           revolver.activeIndex + 1, tabs.count)
        if let top { value += ". " + String(format: L("Activité : %@", table: "Bubble"), top.label(tabs)) }
        return value
    }

    private var rimColor: Color {
        if nearNotch { return Palette.accent }
        guard let top else { return .white.opacity(0.12) }
        return accent(top)
    }

    /// Le barillet tourne d'un bloc ; chaque icône se redresse pour rester lisible.
    private var cylinder: some View {
        let byId = activityById
        let cylinderRadius = Revolver.ringRadius + chamber / 2 + 5
        return ZStack {
            Circle()
                .fill(Color.white.opacity(0.06))
                .frame(width: 2 * cylinderRadius, height: 2 * cylinderRadius)
            // Cannelures entre les chambres, au bord du barillet.
            ForEach(tabs.indices, id: \.self) { index in
                let angle = (Double(index) + 0.5) * revolver.step
                Capsule()
                    .fill(Color.black.opacity(0.35))
                    .frame(width: 3, height: 9)
                    .offset(y: -(cylinderRadius - 5))
                    .rotationEffect(.radians(angle))
            }
            ForEach(Array(tabs.enumerated()), id: \.element.id) { index, tab in
                chamberView(tab, active: index == revolver.activeIndex, activity: byId[tab.id])
                    .rotationEffect(.radians(-revolver.rotation))
                    .position(Revolver(count: tabs.count, turn: 0).position(of: index, center: center))
            }
        }
        .frame(width: Self.diameter, height: Self.diameter)
        .rotationEffect(.radians(revolver.rotation))
        .animation(rotation, value: turn)
    }

    private func chamberView(_ tab: Tab, active: Bool, activity: EarTab?) -> some View {
        ZStack {
            Circle().fill(Color.black.opacity(active ? 0.2 : 0.45))
            Circle().strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
            Image(systemName: tab.symbol)
                .font(.system(size: chamber * 0.45, weight: .semibold))
                .foregroundColor(active ? Palette.primary : Palette.secondary)
        }
        .frame(width: chamber, height: chamber)
        .overlay(alignment: .topTrailing) {
            if let activity {
                Circle()
                    .fill(accent(activity))
                    .frame(width: 7, height: 7)
                    .overlay(Circle().strokeBorder(fill, lineWidth: 1.5))
                    .offset(x: 2, y: -2)
            }
        }
    }

    /// Repère fixe de la chambre du haut (l'onglet actif).
    private var firingMark: some View {
        ZStack {
            Circle()
                .strokeBorder(Palette.accent, lineWidth: 2)
                .frame(width: chamber + 6, height: chamber + 6)
                .position(x: center.x, y: center.y - Revolver.ringRadius)
            Triangle()
                .fill(Palette.accent)
                .frame(width: 8, height: 5)
                .position(x: center.x, y: center.y - Revolver.ringRadius - chamber / 2 - 9)
        }
        .frame(width: Self.diameter, height: Self.diameter)
        .allowsHitTesting(false)
    }

    private var hub: some View {
        ZStack {
            Circle().fill(Color.white.opacity(0.09))
            Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            if let activeTab {
                Text(verbatim: activeTab.title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Palette.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .frame(width: 2 * Revolver.hubRadius - 10)
                    .id(activeTab.id)
                    .transition(.opacity)
            }
        }
        .frame(width: 2 * Revolver.hubRadius, height: 2 * Revolver.hubRadius)
        .animation(.easeOut(duration: 0.15), value: activeTab?.id)
    }

    /// Pastille de l'activité la plus prioritaire, à cheval sur le bas de la bulle (comme un intercalaire).
    @ViewBuilder private var pill: some View {
        if let top {
            let accent = accent(top)
            HStack(spacing: EarTabs.iconGap) {
                EarTabIcon(tab: top, accent: accent)
                EarTabInfo(tab: top, claudeEars: claudeEars, accent: accent)
            }
            .padding(.horizontal, 8)
            .frame(height: 20)
            .background(Capsule().fill(Color.black))
            .overlay(Capsule().strokeBorder(accent.opacity(0.6), lineWidth: 1))
            .fixedSize()
            .offset(y: 10)
            .allowsHitTesting(false)
        }
    }

    // MARK: Gestes

    private var gesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                switch drag {
                case nil:
                    drag = .pending(revolver.zone(at: value.startLocation, center: center))
                case .pending(let zone):
                    guard hypot(value.translation.width, value.translation.height) > 3 else { return }
                    if case .chamber = zone {
                        var rotating = RevolverDrag(startAngle: Revolver.angle(of: value.startLocation, center: center),
                                                    step: revolver.step)
                        let steps = rotating.move(to: Revolver.angle(of: value.location, center: center))
                        drag = .rotating(rotating)
                        if steps != 0 { input.rotate(steps) }
                    } else {
                        drag = .moving
                        input.moveBegan()
                        input.moved()
                    }
                case .rotating(var rotating):
                    let steps = rotating.move(to: Revolver.angle(of: value.location, center: center))
                    drag = .rotating(rotating)
                    if steps != 0 { input.rotate(steps) }
                case .moving:
                    input.moved()
                }
            }
            .onEnded { value in
                defer { drag = nil }
                switch drag {
                case .moving:
                    input.moveEnded()
                case .pending(let zone):
                    tap(zone, clickCount: NSApp.currentEvent?.clickCount ?? 1)
                case .rotating, nil:
                    break
                }
            }
    }

    private func tap(_ zone: Revolver.Zone, clickCount: Int) {
        switch zone {
        case .hub:
            input.open()
        case .chamber(let index):
            let steps = revolver.steps(toTop: index)
            if steps == 0 { input.open() } else { input.rotate(steps) }
        case .rim where clickCount >= 2:
            input.reattach()
        case .rim, .outside:
            break
        }
    }
}

private extension EarTab {
    /// Activité dite par VoiceOver : le titre de l'onglet et son information courte.
    func label(_ tabs: [RevolverBubble.Tab]) -> String {
        let title = tabs.first { $0.id == id }?.title ?? id
        return text.isEmpty ? title : "\(title) \(text)"
    }
}

/// Petit triangle pointé vers le bas (repère de l'onglet actif).
private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
