import AppKit
import SwiftUI

/// Forme d'un intercalaire : coin extérieur bas arrondi (et coin intérieur bas une fois déployé), bord haut collé au
/// haut de l'écran. Le prolongement derrière la notch (`overlap`, sur `overlapHeight`) bouche le jour que laisse le
/// coin arrondi de la notch contre l'intercalaire qui la touche.
struct EarTabShape: Shape {
    var side: EarTabsLayout.Side
    var outerRadius: CGFloat
    var innerRadius: CGFloat = 0
    var overlap: CGFloat = 0
    var overlapHeight: CGFloat = 0

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, CGFloat> {
        get { AnimatablePair(AnimatablePair(outerRadius, innerRadius), overlapHeight) }
        set {
            outerRadius = newValue.first.first
            innerRadius = newValue.first.second
            overlapHeight = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let outer = max(0, min(outerRadius, rect.width / 2, rect.height))
        let inner = max(0, min(innerRadius, rect.width / 2, rect.height))
        // `s` : du bord extérieur vers le bord intérieur.
        let s: CGFloat = side == .left ? 1 : -1
        let o = side == .left ? rect.minX : rect.maxX
        let i = side == .left ? rect.maxX : rect.minX
        var path = Path()
        path.move(to: CGPoint(x: o, y: rect.minY))
        path.addLine(to: CGPoint(x: o, y: rect.maxY - outer))
        path.addQuadCurve(to: CGPoint(x: o + s * outer, y: rect.maxY), control: CGPoint(x: o, y: rect.maxY))
        path.addLine(to: CGPoint(x: i - s * inner, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: i, y: rect.maxY - inner), control: CGPoint(x: i, y: rect.maxY))
        if overlap > 0, overlapHeight > 0 {
            // Jusqu'en bas de la notch, même si la carte déployée est basse : le jour du coin arrondi de la notch s'y trouve.
            let y = min(overlapHeight, rect.maxY)
            path.addLine(to: CGPoint(x: i, y: y))
            path.addLine(to: CGPoint(x: i + s * overlap, y: y))
            path.addLine(to: CGPoint(x: i + s * overlap, y: rect.minY))
        } else {
            path.addLine(to: CGPoint(x: i, y: rect.minY))
        }
        path.closeSubpath()
        return path
    }
}

/// Hauteur du contenu de l'intercalaire déployé, mesurée par la vue (le contrôleur en tire sa zone de survol).
private struct EarCardHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// Les intercalaires de la notch repliée, posés de part et d'autre de la notch. La fenêtre laisse passer la souris :
/// le contrôleur décide du survol (`EarTabsLayout.hit`) et dit lequel est déployé (`hovered`) ; la vue ne fait que dessiner.
/// Les clics n'arrivent ici que sur un intercalaire déployé (le contrôleur rend alors la souris à la fenêtre).
struct EarTabsView: View {
    let layout: EarTabsLayout
    let hovered: String?
    let claudeEars: SessionStore.EarsContent?
    let fill: Color
    let animation: Animation
    @ObservedObject var registry: ModuleRegistry
    let openTab: (String) -> Void
    let cardHeightChanged: (CGFloat) -> Void

    @State private var cardHeight: CGFloat = 0

    var body: some View {
        ZStack(alignment: .top) {
            ForEach(layout.items) { item in
                let isHovered = item.id == hovered
                EarTabItemView(item: item, layout: layout, isHovered: isHovered, cardHeight: cardHeight,
                               claudeEars: claudeEars, fill: fill, registry: registry, openTab: openTab)
                    .offset(x: frameOf(item, isHovered).midX)
                    .zIndex(isHovered ? 1 : 0)
                    .transition(.opacity)
            }
        }
        // Aussi grand que la fenêtre : un intercalaire hors du cadre de son parent ne recevrait pas les clics.
        .frame(width: NotchController.panelSize.width, height: NotchController.panelSize.height, alignment: .top)
        .animation(animation, value: layout.signature)
        .animation(animation, value: hovered)
        .animation(animation, value: cardHeight)
        .onPreferenceChange(EarCardHeightKey.self) { height in
            cardHeight = height
            cardHeightChanged(height)
        }
    }

    private func frameOf(_ item: EarTabsLayout.Item, _ isHovered: Bool) -> CGRect {
        isHovered ? layout.cardFrame(item, height: cardHeight) : item.frame
    }
}

/// Un intercalaire : au repos, une icône et une information courte (ou une languette) ; déployé, son titre et son contenu.
private struct EarTabItemView: View {
    let item: EarTabsLayout.Item
    let layout: EarTabsLayout
    let isHovered: Bool
    let cardHeight: CGFloat
    let claudeEars: SessionStore.EarsContent?
    let fill: Color
    @ObservedObject var registry: ModuleRegistry
    let openTab: (String) -> Void

    private var accent: Color { item.tab.accentHex.flatMap { Color(hex: $0) } ?? Palette.accent }
    private var cardWidth: CGFloat { layout.cardWidth(item) }
    private var isSliver: Bool { item.width <= EarTabs.sliverWidth }
    private var title: String {
        if case .more(let hidden) = item.tab.kind { return Self.moreTitle(hidden.count) }
        return registry.earTitle(item.tab.id)
    }

    static func moreTitle(_ count: Int) -> String {
        String(format: L(count, one: "%d autre activité", other: "%d autres activités"), count)
    }
    /// L'intercalaire contre la notch prolonge sa forme derrière elle.
    private var overlap: CGFloat { item.rank == 0 ? EarTabs.overlap : 0 }

    var body: some View {
        ZStack(alignment: .top) {
            if isHovered {
                card
            } else {
                rest
            }
        }
        .frame(width: isHovered ? cardWidth : item.width,
               height: isHovered ? max(cardHeight, layout.notch.height) : item.height, alignment: .top)
        .clipShape(shape)
        .background(shape.fill(fill))
        .contentShape(shape)
        .accessibilityElement(children: isHovered ? .contain : .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(L("Ouvre l'onglet correspondant"))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { openTab(item.id) }
    }

    /// Coin intérieur bas de la carte : pas plus haut que ce qui dépasse sous la notch, sinon il laisse un jour contre elle.
    private var cardInnerRadius: CGFloat {
        min(EarTabs.cardRadius, max(0, max(cardHeight, layout.notch.height) - layout.notch.height))
    }

    private var shape: EarTabShape {
        EarTabShape(side: item.side, outerRadius: isHovered ? EarTabs.cardRadius : EarTabs.restRadius,
                    innerRadius: isHovered ? cardInnerRadius : 0, overlap: overlap,
                    overlapHeight: overlap > 0 ? (isHovered ? layout.notch.height : item.height) : 0)
    }

    // MARK: Au repos

    private var rest: some View {
        Group {
            if isSliver {
                Capsule()
                    .fill(accent)
                    .frame(width: 3, height: max(6, item.height - 12))
                    .frame(maxHeight: .infinity)
            } else {
                HStack(spacing: EarTabs.iconGap) {
                    EarTabIcon(tab: item.tab, accent: accent)
                    EarTabInfo(tab: item.tab, claudeEars: claudeEars, accent: accent)
                }
                .padding(.horizontal, EarTabs.padding)
                .frame(maxHeight: .infinity)
                .overlay(alignment: .bottom) {
                    Capsule()
                        .fill(accent.opacity(0.9))
                        .frame(height: 2)
                        .padding(.horizontal, EarTabs.padding + 1)
                        .padding(.bottom, 2)
                }
            }
        }
        .frame(width: item.width, height: item.height)
        .transition(.opacity)
    }

    // MARK: Déployé

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            // La bande de la notch : la ligne de l'intercalaire au repos, avec son titre.
            HStack(spacing: 6) {
                EarTabIcon(tab: item.tab, accent: accent)
                Text(verbatim: title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Palette.primary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if item.tab.id != EarTab.moreId {
                    EarTabInfo(tab: item.tab, claudeEars: claudeEars, accent: accent)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: layout.notch.height)
            detail
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
        }
        .frame(width: cardWidth, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .contentShape(Rectangle())
        .onTapGesture { openTab(item.id) }
        .background(GeometryReader { proxy in
            Color.clear.preference(key: EarCardHeightKey.self, value: proxy.size.height)
        })
        .transition(.opacity.animation(.easeOut(duration: 0.12).delay(0.05)))
    }

    @ViewBuilder
    private var detail: some View {
        let width = cardWidth - 20
        Group {
            if case .more(let hidden) = item.tab.kind {
                EarTabMoreList(tabs: hidden, registry: registry, openTab: openTab)
            } else if let view = registry.earDetailView(item.tab.id) {
                view
            }
        }
        .environment(\.notchContentWidth, width)
        .environment(\.notchContentMaxHeight, 140)
        .frame(width: width, alignment: .leading)
    }

    private var accessibilityLabel: String {
        switch item.tab.kind {
        case .claude(let indicator):
            let state: String
            switch indicator {
            case .attention: state = L("Claude attend ta réponse")
            case .working: state = L("Claude travaille")
            case .done, .none: state = L("Claude a terminé")
            }
            return item.tab.text.isEmpty ? state : String(format: L("%@ : %@"), state, item.tab.text)
        case .module:
            return item.tab.text.isEmpty ? title : String(format: L("%@ : %@"), title, item.tab.text)
        case .more(let hidden):
            return Self.moreTitle(hidden.count)
        }
    }
}

/// Icône d'un intercalaire : l'état de Claude, la pochette ou le symbole du module, « … » pour le reste.
private struct EarTabIcon: View {
    let tab: EarTab
    let accent: Color

    var body: some View {
        Group {
            switch tab.kind {
            case .claude(let indicator):
                IndicatorGlyph(indicator: indicator)
            case .module(let ears):
                if let image = ears.image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 16, height: 16)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                } else {
                    Image(systemName: ears.symbol)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(accent)
                }
            case .more:
                Image(systemName: "ellipsis")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(accent)
            }
        }
        .frame(width: EarTabs.iconWidth, height: 14)
    }
}

/// Information courte d'un intercalaire : « 1·6 » (Claude, agents en couleur), texte du module ou barres d'égaliseur.
private struct EarTabInfo: View {
    let tab: EarTab
    let claudeEars: SessionStore.EarsContent?
    let accent: Color

    var body: some View {
        if tab.bars {
            EqualizerBars(color: accent)
        } else if !tab.text.isEmpty {
            text
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }

    private var text: Text {
        guard case .claude = tab.kind, let ears = claudeEars else {
            return Text(verbatim: tab.text).foregroundColor(.white.opacity(0.85))
        }
        if let tasks = ears.tasks { return Text(tasks).foregroundColor(.white.opacity(0.85)) }
        let sessions = Text(verbatim: "\(ears.sessions)").foregroundColor(.white.opacity(0.85))
        guard ears.agents > 0 else { return sessions }
        return sessions + Text(verbatim: "·").foregroundColor(Palette.secondary)
            + Text(verbatim: "\(ears.agents)").foregroundColor(Palette.accent)
    }
}

/// Contenu de « +N » déployé : les activités qui n'ont pas de place, une ligne chacune ; un clic ouvre son onglet.
private struct EarTabMoreList: View {
    let tabs: [EarTab]
    @ObservedObject var registry: ModuleRegistry
    let openTab: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(tabs) { tab in
                let accent = tab.accentHex.flatMap { Color(hex: $0) } ?? Palette.accent
                ModuleSummaryRow {
                    EarTabIcon(tab: tab, accent: accent)
                    Text(verbatim: registry.earTitle(tab.id))
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundColor(Palette.primary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    EarTabInfo(tab: tab, claudeEars: nil, accent: accent)
                }
                .onTapGesture { openTab(tab.id) }
            }
        }
    }
}
