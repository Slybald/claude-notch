import CoreGraphics
import Foundation

// Notch détachée en bulle : règles pures (états, seuils, écrans, barillet, goutte), testées sans fenêtre.
// Les fenêtres et les vues sont dans `BubbleWindow.swift`.

/// Où en est la notch : à sa place, en train de s'en décoller, bulle flottante, bulle ouverte, ou qui revient.
enum BubblePhase: String, Equatable {
    case attached
    /// Glisser depuis l'angle : la goutte s'étire depuis la notch.
    case detaching
    case bubble
    /// La bulle s'est ouverte en panneau (contenu de l'onglet actif).
    case bubblePanel
    /// La goutte rentre dans la notch.
    case reattaching

    /// La bulle remplace le panneau : le survol de la notch n'ouvre rien.
    var isDetached: Bool { self == .bubble || self == .bubblePanel || self == .reattaching }

    enum Event: Equatable {
        /// Appui maintenu sur la poignée, ou « Détacher la notch » (menu, VoiceOver).
        case grab
        /// Fin du glisser : au-delà du seuil de décollage ou non.
        case release(detached: Bool)
        case open
        case close
        /// Bulle lâchée près de la notch, menu, double-clic.
        case reattach
        /// Fin de l'animation de rattachement.
        case merged
        /// Réglage coupé, plein écran masqué… : retour immédiat.
        case reset
    }

    /// Transition ; un événement sans effet dans l'état courant le laisse tel quel.
    func next(_ event: Event) -> BubblePhase {
        switch (self, event) {
        case (_, .reset): return .attached
        case (.attached, .grab): return .detaching
        case (.detaching, .release(let detached)): return detached ? .bubble : .attached
        case (.bubble, .open): return .bubblePanel
        case (.bubblePanel, .close): return .bubble
        case (.bubble, .reattach), (.bubblePanel, .reattach): return .reattaching
        case (.reattaching, .merged): return .attached
        default: return self
        }
    }
}

// MARK: - Géométrie de la bulle

/// Taille de la bulle, seuils de décollage et d'aimantation, contraintes d'écran. Coordonnées écran (y vers le haut).
enum BubbleGeometry {
    static let diameter: CGFloat = 148
    static var radius: CGFloat { diameter / 2 }
    /// Marge de la fenêtre autour de la bulle : ombre et pastille d'activité.
    static let windowMargin: CGFloat = 24
    /// Marge de la fenêtre autour du panneau de la bulle (ombre).
    static let panelMargin: CGFloat = 20
    /// Écart minimal entre la bulle et le bord d'un écran visible.
    static let screenInset: CGFloat = 6
    /// Distance de glisser depuis la poignée au-delà de laquelle la goutte se décolle.
    static let detachDistance: CGFloat = 120
    /// La bulle à moins de cet écart du bas de la notch est aimantée (et s'y rattache si on la lâche).
    static let magnetGap: CGFloat = 44

    /// Centre de la bulle juste sous la notch : là où elle s'aimante.
    static func dockPoint(notch: CGRect) -> CGPoint {
        CGPoint(x: notch.midX, y: notch.minY - radius - 8)
    }

    /// Écart entre le bord de la bulle et le milieu du bas de la notch.
    static func gap(center: CGPoint, notch: CGRect) -> CGFloat {
        hypot(center.x - notch.midX, center.y - notch.minY) - radius
    }

    static func isNearNotch(center: CGPoint, notch: CGRect) -> Bool {
        gap(center: center, notch: notch) < magnetGap
    }

    /// Bulle aimantée : tirée à mi-chemin vers la notch ; ailleurs, inchangée.
    static func magnetized(center: CGPoint, notch: CGRect) -> CGPoint {
        guard isNearNotch(center: center, notch: notch) else { return center }
        let dock = dockPoint(notch: notch)
        return CGPoint(x: (center.x + dock.x) / 2, y: (center.y + dock.y) / 2)
    }

    /// Centre ramené dans un écran visible (barre des menus et Dock exclus) : inchangé s'il y est déjà, sinon le point
    /// le plus proche du rectangle permis le plus proche. Sans écran, inchangé.
    static func clamp(_ center: CGPoint, visibleFrames: [CGRect], radius: CGFloat = radius) -> CGPoint {
        let inset = radius + screenInset
        var best: (point: CGPoint, distance: CGFloat)?
        for frame in visibleFrames {
            let allowed = frame.insetBy(dx: min(inset, frame.width / 2), dy: min(inset, frame.height / 2))
            let point = CGPoint(x: min(max(center.x, allowed.minX), allowed.maxX),
                                y: min(max(center.y, allowed.minY), allowed.maxY))
            let distance = hypot(point.x - center.x, point.y - center.y)
            if distance == 0 { return center }
            if best == nil || distance < best!.distance { best = (point, distance) }
        }
        return best?.point ?? center
    }

    /// Rectangle (coin bas gauche, coordonnées écran) d'un panneau de `size` ouvert depuis la bulle : son haut au
    /// niveau du haut de la bulle, centré sur elle, puis ramené dans l'écran visible.
    static func panelFrame(size: CGSize, bubble center: CGPoint, visible: CGRect) -> CGRect {
        var frame = CGRect(x: center.x - size.width / 2, y: center.y + radius - size.height,
                           width: size.width, height: size.height)
        frame.origin.x = min(max(frame.minX, visible.minX), max(visible.minX, visible.maxX - size.width))
        frame.origin.y = min(max(frame.minY, visible.minY), max(visible.minY, visible.maxY - size.height))
        return frame
    }
}

// MARK: - Position mémorisée par écran

/// Position de la bulle rangée par écran (nom de `NotchScreenPicker.labels`), en décalage depuis l'origine de l'écran :
/// un écran déplacé dans l'arrangement garde sa bulle au même endroit.
enum BubblePlacement {
    /// Position par défaut : sous la notch, un peu à droite.
    static func defaultCenter(notch: CGRect) -> CGPoint {
        CGPoint(x: notch.maxX + 140, y: notch.minY - BubbleGeometry.radius - 60)
    }

    /// Écran et centre de la bulle : le dernier écran utilisé s'il est branché, sinon celui de la notch ; la position
    /// rangée pour cet écran, sinon la position par défaut ; toujours dans l'écran visible.
    static func restore(screens: [ScreenCandidate], notchScreen: Int, notch: CGRect, lastScreen: String?,
                        saved: [String: [Double]]) -> (screen: Int, center: CGPoint)? {
        guard screens.indices.contains(notchScreen) else { return nil }
        let labels = NotchScreenPicker.labels(screens)
        let index = lastScreen.flatMap { labels.firstIndex(of: $0) } ?? notchScreen
        let screen = screens[index]
        let center: CGPoint
        if let offset = saved[labels[index]], offset.count == 2, offset.allSatisfy({ $0.isFinite }) {
            center = CGPoint(x: screen.frame.minX + offset[0], y: screen.frame.minY + offset[1])
        } else if index == notchScreen {
            center = defaultCenter(notch: notch)
        } else {
            center = CGPoint(x: screen.visibleFrame.maxX - 160, y: screen.visibleFrame.maxY - 160)
        }
        return (index, BubbleGeometry.clamp(center, visibleFrames: [screen.visibleFrame]))
    }

    /// Écran qui contient `center` (sinon le plus proche) et décalage à ranger.
    static func save(center: CGPoint, screens: [ScreenCandidate]) -> (label: String, offset: [Double])? {
        guard !screens.isEmpty else { return nil }
        let labels = NotchScreenPicker.labels(screens)
        let index = screens.firstIndex { NotchScreenPicker.contains($0.frame, center) }
            ?? screens.indices.min { distance(center, screens[$0].frame) < distance(center, screens[$1].frame) }!
        let frame = screens[index].frame
        return (labels[index], [Double(center.x - frame.minX), Double(center.y - frame.minY)])
    }

    private static func distance(_ point: CGPoint, _ rect: CGRect) -> CGFloat {
        hypot(max(rect.minX - point.x, 0, point.x - rect.maxX), max(rect.minY - point.y, 0, point.y - rect.maxY))
    }
}

// MARK: - Barillet

/// Onglets en barillet de revolver : une chambre par onglet autour du centre ; l'onglet en haut est l'onglet actif.
/// `turn` compte les crans depuis le premier onglet, sans borne : l'animation tourne toujours dans le bon sens.
/// Angles en radians, 0 en haut, sens horaire (coordonnées de vue, y vers le bas).
struct Revolver: Equatable {
    var count: Int
    var turn: Int

    /// Distance du centre aux chambres.
    static let ringRadius: CGFloat = 50
    /// Rayon du moyeu (clic : ouvrir).
    static let hubRadius: CGFloat = 32

    var step: Double { count > 0 ? 2 * .pi / Double(count) : 0 }

    /// Index de l'onglet en haut (actif).
    var activeIndex: Int { count > 0 ? ((turn % count) + count) % count : 0 }

    /// Angle de la chambre `index` : 0 pour l'onglet actif.
    func angle(of index: Int) -> Double { Double(index - turn) * step }

    /// Rotation du barillet entier (radians) : les icônes tournent avec lui puis se redressent.
    var rotation: Double { -Double(turn) * step }

    /// Centre de la chambre `index` dans une bulle de centre `center`.
    func position(of index: Int, center: CGPoint, radius: CGFloat = ringRadius) -> CGPoint {
        let angle = angle(of: index)
        return CGPoint(x: center.x + radius * CGFloat(sin(angle)), y: center.y - radius * CGFloat(cos(angle)))
    }

    /// Diamètre d'une chambre : 28 pt, moins quand dix onglets se partagent le tour.
    static func chamberDiameter(count: Int) -> CGFloat {
        guard count > 0 else { return 28 }
        return min(28, 2 * .pi * ringRadius / CGFloat(count) - 5)
    }

    /// Crans à tourner pour amener `index` en haut, par le plus court chemin (à égalité, dans le sens horaire).
    func steps(toTop index: Int) -> Int {
        guard count > 0 else { return 0 }
        var delta = ((index - activeIndex) % count + count) % count
        if delta > count / 2 { delta -= count }
        return delta
    }

    mutating func rotate(by steps: Int) { turn += steps }

    enum Zone: Equatable {
        case hub
        case chamber(Int)
        /// Bord de la bulle (glisser : déplacer ; double-clic : rattacher).
        case rim
        case outside
    }

    /// Ce qui est sous `point` (coordonnées de vue d'une bulle de centre `center`).
    func zone(at point: CGPoint, center: CGPoint, bubbleRadius: CGFloat = BubbleGeometry.radius) -> Zone {
        let distance = hypot(point.x - center.x, point.y - center.y)
        if distance > bubbleRadius { return .outside }
        if distance <= Self.hubRadius { return .hub }
        let reach = Self.chamberDiameter(count: count) / 2 + 3
        for index in 0..<count {
            let chamber = position(of: index, center: center)
            if hypot(point.x - chamber.x, point.y - chamber.y) <= reach { return .chamber(index) }
        }
        return .rim
    }

    /// Angle d'un point autour du centre, même convention que `angle(of:)`.
    static func angle(of point: CGPoint, center: CGPoint) -> Double {
        atan2(Double(point.x - center.x), Double(center.y - point.y))
    }
}

/// Molette et trackpad : les petits défilements s'additionnent jusqu'à un cran. L'inertie est ignorée (un cran = un
/// geste voulu).
struct RevolverScroll: Equatable {
    /// Points de défilement précis (trackpad) par cran ; une ligne de molette = un cran.
    static let preciseStep: CGFloat = 28
    private(set) var accumulated: CGFloat = 0

    /// Crans à tourner pour ce défilement (positif : vers le bas ou la gauche = onglet suivant).
    mutating func add(deltaX: CGFloat, deltaY: CGFloat, precise: Bool) -> Int {
        let delta = abs(deltaY) >= abs(deltaX) ? -deltaY : deltaX
        guard delta != 0 else { return 0 }
        if (delta > 0) != (accumulated > 0), accumulated != 0 { accumulated = 0 }
        accumulated += precise ? delta / Self.preciseStep : (delta > 0 ? 1 : -1)
        let steps = Int(accumulated.rounded(.towardZero))
        accumulated -= CGFloat(steps)
        return steps
    }

    mutating func reset() { accumulated = 0 }
}

/// Glisser circulaire sur les chambres : l'angle parcouru s'additionne (plus d'un demi-tour possible) et tourne le
/// barillet d'un cran à chaque pas d'angle franchi.
struct RevolverDrag: Equatable {
    let step: Double
    private var lastAngle: Double
    private var travelled: Double = 0
    private var applied = 0

    init(startAngle: Double, step: Double) {
        lastAngle = startAngle
        self.step = step
    }

    /// Crans à appliquer depuis le dernier appel. Glisser dans le sens horaire amène l'onglet de gauche en haut.
    mutating func move(to angle: Double) -> Int {
        guard step > 0 else { return 0 }
        var delta = angle - lastAngle
        while delta > .pi { delta -= 2 * .pi }
        while delta < -.pi { delta += 2 * .pi }
        lastAngle = angle
        travelled += delta
        let total = -Int((travelled / step).rounded())
        defer { applied = total }
        return total - applied
    }
}

// MARK: - Goutte

/// La goutte entre la notch et la bulle (effet « gooey » : formes floutées puis seuillées). Coordonnées de la fenêtre
/// de la goutte (y vers le bas). Tout est fonction de la progression, testable et rendu tel quel.
struct GooShapes: Equatable {
    struct Circle: Equatable {
        var center: CGPoint
        var radius: CGFloat
    }

    /// Corps resté contre la notch (le panneau qui se replie).
    var body: CGRect
    var bodyRadius: CGFloat
    /// Goutte sous la souris ; rayon 0 = plus de goutte.
    var drop: Circle
    /// Col entre le corps et la goutte : un chapelet de cercles, pincé au milieu.
    var neck: [Circle]
}

enum Goo {
    /// Cercles du col.
    static let neckCount = 14
    /// Flou avant le seuil : arrondit les jonctions comme un liquide.
    static let blur: CGFloat = 7
    /// Rayon du col au plus fin, juste avant la rupture : plus fin, le seuil l'effacerait (≈ 0,7 × le flou).
    static let neckFloor: CGFloat = 5.5
    static let snapDuration: TimeInterval = 0.32
    static let cancelDuration: TimeInterval = 0.28
    static let mergeDuration: TimeInterval = 0.48
    /// Détachement depuis le menu : la goutte parcourt le seuil seule.
    static let autoPullDuration: TimeInterval = 0.34

    /// Progression du décollage : 0 contre la poignée, 1 au seuil.
    static func progress(distance: CGFloat) -> CGFloat {
        min(max(distance / BubbleGeometry.detachDistance, 0), 1)
    }

    /// Rayon de la goutte : petite au départ, presque la bulle au seuil.
    static func dropRadius(progress p: CGFloat) -> CGFloat {
        14 + (BubbleGeometry.radius * 0.72 - 14) * p
    }

    /// Point du corps le plus proche de la goutte : le col part de là.
    static func anchor(body: CGRect, inset: CGFloat, toward point: CGPoint) -> CGPoint {
        let inner = body.insetBy(dx: min(inset, body.width / 2), dy: min(inset, body.height / 2))
        return CGPoint(x: min(max(point.x, inner.minX), inner.maxX), y: min(max(point.y, inner.minY), inner.maxY))
    }

    /// Rayon du cercle `t` du col (0 côté corps, 1 côté goutte) : épais aux deux bouts, pincé au milieu, de plus en plus
    /// fin à mesure que `p` monte, jusqu'à `neckFloor` au seuil ; la rupture vient ensuite (`snap`).
    static func neckRadius(t: CGFloat, progress p: CGFloat, start: CGFloat, end: CGFloat) -> CGFloat {
        let base = max(0, start + (end - start) * t)
        let thin = pow(min(max(p, 0), 1), 0.8) * sin(.pi * t)
        return base + (min(neckFloor, base) - base) * thin
    }

    /// Corps qui se replie du panneau vers la notch quand `p` monte : à moitié au seuil, le reste au décollage.
    static func body(from panel: CGRect, to notch: CGRect, progress p: CGFloat) -> CGRect {
        let e = 0.55 * pow(min(max(p, 0), 1), 1.3)
        func mix(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * e }
        return CGRect(x: mix(panel.minX, notch.minX), y: mix(panel.minY, notch.minY),
                      width: mix(panel.width, notch.width), height: mix(panel.height, notch.height))
    }

    /// Formes pendant le glisser : corps entre le panneau et la notch, goutte en `drop`, col entre les deux.
    static func pull(panel: CGRect, notch: CGRect, drop: CGPoint, progress p: CGFloat, neckScale: CGFloat = 1)
        -> GooShapes {
        let body = body(from: panel, to: notch, progress: p)
        let bodyRadius = 22 - 10 * p
        let dropRadius = dropRadius(progress: p)
        let anchor = anchor(body: body, inset: bodyRadius, toward: drop)
        let start = min(30, body.height / 2) * (1 - 0.35 * p)
        let end = dropRadius * 0.8
        let neck = (0..<neckCount).map { index -> GooShapes.Circle in
            let t = CGFloat(index) / CGFloat(neckCount - 1)
            let center = CGPoint(x: anchor.x + (drop.x - anchor.x) * t, y: anchor.y + (drop.y - anchor.y) * t)
            return .init(center: center, radius: neckRadius(t: t, progress: p, start: start, end: end) * neckScale)
        }
        return GooShapes(body: body, bodyRadius: bodyRadius, drop: .init(center: drop, radius: dropRadius), neck: neck)
    }

    /// Ressort amorti de 0 à 1 (léger dépassement) : le corps qui rentre, la bulle qui rebondit.
    static func spring(_ t: CGFloat) -> CGFloat {
        guard t < 1 else { return 1 }
        let x = max(t, 0)
        return 1 - exp(-6 * x) * cos(9 * x)
    }

    /// Après le décollage (`t` de 0 à 1) : le col se résorbe, le corps rentre dans la notch ; la goutte est partie (la
    /// fenêtre de la bulle la remplace).
    static func snap(panel: CGRect, notch: CGRect, drop: CGPoint, t: CGFloat) -> GooShapes {
        var shapes = pull(panel: panel, notch: notch, drop: drop, progress: 1, neckScale: 0)
        let k = spring(t)
        let from = shapes.body
        shapes.body = CGRect(x: from.minX + (notch.minX - from.minX) * k, y: from.minY + (notch.minY - from.minY) * k,
                             width: from.width + (notch.width - from.width) * k,
                             height: from.height + (notch.height - from.height) * k)
        shapes.drop.radius = 0
        // Un reste du col pend sous le corps qui remonte, puis rentre dedans.
        let tail = max(0, 1 - t * 1.8)
        let anchor = anchor(body: shapes.body, inset: shapes.bodyRadius, toward: drop)
        let dx = drop.x - anchor.x, dy = drop.y - anchor.y
        let length = max(hypot(dx, dy), 1)
        shapes.neck = (0..<6).map { index -> GooShapes.Circle in
            let s = CGFloat(index) / 5
            let reach = 46 * tail * s
            return .init(center: CGPoint(x: anchor.x + dx / length * reach, y: anchor.y + dy / length * reach),
                         radius: (12 - 5 * s) * tail)
        }
        return shapes
    }

    /// Glisser abandonné avant le seuil (`t` de 0 à 1) : la goutte revient à la poignée, le corps redevient le panneau.
    static func cancel(panel: CGRect, notch: CGRect, handle: CGPoint, from drop: CGPoint, progress p0: CGFloat,
                       t: CGFloat) -> GooShapes {
        let e = 1 - pow(1 - min(max(t, 0), 1), 3)
        let point = CGPoint(x: drop.x + (handle.x - drop.x) * e, y: drop.y + (handle.y - drop.y) * e)
        var shapes = pull(panel: panel, notch: notch, drop: point, progress: p0 * (1 - e))
        shapes.drop.radius *= 1 - e
        return shapes
    }

    /// Rattachement (`t` de 0 à 1) : la goutte monte dans la notch, un col se reforme, le corps gonfle puis se calme.
    static func merge(notch: CGRect, from drop: CGPoint, t: CGFloat) -> GooShapes {
        let t = min(max(t, 0), 1)
        let travel = t * t
        let target = CGPoint(x: notch.midX, y: notch.maxY - 4)
        let point = CGPoint(x: drop.x + (target.x - drop.x) * travel, y: drop.y + (target.y - drop.y) * travel)
        let radius = BubbleGeometry.radius * pow(1 - t, 0.8)
        let swell = sin(.pi * t) * 12
        var grown = notch.insetBy(dx: -swell, dy: 0)
        grown.size.height += swell
        let anchor = Goo.anchor(body: grown, inset: 8, toward: point)
        // Le col se forme quand la goutte approche, puis s'épaissit jusqu'à se fondre.
        let p = max(0, 1 - t * 2.4)
        let forming = min(1, t * 4)
        let neck = (0..<neckCount).map { index -> GooShapes.Circle in
            let s = CGFloat(index) / CGFloat(neckCount - 1)
            let center = CGPoint(x: anchor.x + (point.x - anchor.x) * s, y: anchor.y + (point.y - anchor.y) * s)
            return .init(center: center,
                         radius: neckRadius(t: s, progress: p, start: 14 + swell, end: radius * 0.8) * forming)
        }
        return GooShapes(body: grown, bodyRadius: 10, drop: .init(center: point, radius: radius), neck: neck)
    }
}

/// Animation en cours dans la fenêtre de la goutte (coordonnées de cette fenêtre, y vers le bas). Les formes sont
/// recalculées à chaque image d'après l'heure : aucun minuteur, la vue s'arrête avec l'animation.
struct GooState: Equatable {
    enum Mode: Equatable {
        /// La goutte suit la souris (`drop`).
        case pull
        /// « Détacher la notch » (menu) : la goutte va seule de la poignée à `to`.
        case autoPull(start: Date, to: CGPoint)
        case snap(start: Date)
        case cancel(start: Date, from: CGPoint, progress: CGFloat)
        case merge(start: Date, from: CGPoint)
    }

    var panel: CGRect
    var notch: CGRect
    var handle: CGPoint
    var drop: CGPoint
    var mode: Mode = .pull

    var progress: CGFloat { Goo.progress(distance: hypot(drop.x - handle.x, drop.y - handle.y)) }

    func shapes(at date: Date) -> GooShapes {
        func elapsed(_ start: Date, _ duration: TimeInterval) -> CGFloat {
            CGFloat(min(max(date.timeIntervalSince(start) / duration, 0), 1))
        }
        switch mode {
        case .pull:
            return Goo.pull(panel: panel, notch: notch, drop: drop, progress: progress)
        case .autoPull(let start, let to):
            let t = elapsed(start, Goo.autoPullDuration)
            let e = t * t * (3 - 2 * t)
            let point = CGPoint(x: handle.x + (to.x - handle.x) * e, y: handle.y + (to.y - handle.y) * e)
            let p = Goo.progress(distance: hypot(point.x - handle.x, point.y - handle.y))
            return Goo.pull(panel: panel, notch: notch, drop: point, progress: p)
        case .snap(let start):
            return Goo.snap(panel: panel, notch: notch, drop: drop, t: elapsed(start, Goo.snapDuration))
        case .cancel(let start, let from, let p):
            return Goo.cancel(panel: panel, notch: notch, handle: handle, from: from, progress: p,
                              t: elapsed(start, Goo.cancelDuration))
        case .merge(let start, let from):
            return Goo.merge(notch: notch, from: from, t: elapsed(start, Goo.mergeDuration))
        }
    }
}
