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

    /// Part du décollage où la goutte reste dessinée sous la bulle qui vient de la remplacer : si la fenêtre de la bulle
    /// arrive une image plus tard, rien ne clignote (la goutte suit la bulle, cachée dessous).
    static let snapOverlap: CGFloat = 0.15

    /// Après le décollage (`t` de 0 à 1) : le col se résorbe, le corps rentre dans la notch ; la goutte s'efface sous la
    /// bulle qui la remplace.
    static func snap(panel: CGRect, notch: CGRect, drop: CGPoint, t: CGFloat) -> GooShapes {
        var shapes = pull(panel: panel, notch: notch, drop: drop, progress: 1, neckScale: 0)
        let k = spring(t)
        let from = shapes.body
        shapes.body = CGRect(x: from.minX + (notch.minX - from.minX) * k, y: from.minY + (notch.minY - from.minY) * k,
                             width: from.width + (notch.width - from.width) * k,
                             height: from.height + (notch.height - from.height) * k)
        if t >= snapOverlap { shapes.drop.radius = 0 }
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
        /// Décollage fini : le corps repose dans la notch (dessin fixe) jusqu'à ce que la notch reprenne sa place.
        case rest
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
        case .rest:
            return Goo.snap(panel: panel, notch: notch, drop: drop, t: 1)
        }
    }
}

// MARK: - Retour aimanté (ferrofluide)

/// Retour dans la notch : la notch attire la bulle comme un aimant attire du ferrofluide. L'attraction croît quand
/// l'écart diminue ; la bulle se tend vers la notch, se hérisse de pointes, puis la notch l'aspire et rebondit.
/// Écran (y vers le haut) pour l'attraction ; formes dans la fenêtre de la bulle (y vers le bas).
enum Ferro {
    /// Écart (bord de la bulle, milieu du bas de la notch) où l'attraction commence.
    static let reach: CGFloat = 150
    /// Écart où la notch aspire la bulle, sans qu'on la lâche.
    static let captureGap: CGFloat = 16
    /// Déplacement de la bulle vers la notch à pleine attraction.
    static let maxPull: CGFloat = 30
    /// Pointes vers la notch : nombre, hauteur de celle du milieu à pleine attraction.
    static let spikeCount = 7
    static let spikeHeight: CGFloat = 26
    /// Pas du contour (360 points) ; les pointes sont espacées et larges d'un nombre entier de pas : leur sommet tombe
    /// toujours sur un point, elles ne scintillent pas en tournant.
    static let samples = 360
    static var spikeSpacing: CGFloat { 11 * 2 * .pi / CGFloat(samples) }
    static var spikeWidth: CGFloat { 6 * 2 * .pi / CGFloat(samples) }
    /// Pointe de la notch vers la bulle : demi-largeur de sa base, longueur à pleine attraction.
    static let coneHalfWidth: CGFloat = 34
    static let coneLength: CGFloat = 16
    static let aspirateDuration: TimeInterval = 0.42
    /// Rebond de la notch une fois la bulle avalée.
    static let settleDuration: TimeInterval = 0.45
    static let relaxDuration: TimeInterval = 0.6
    /// Renflement du bas de la notch quand la bulle y entre.
    static let swellHeight: CGFloat = 9

    /// Champ de la notch (écran) : tant que la bulle y est attirée, sa fenêtre le couvre, notch comprise, et ne bouge
    /// plus. Assez grand pour toute bulle à moins de `reach` de la notch, avec sa marge et ses pointes.
    static func fieldFrame(notch: CGRect) -> CGRect {
        let side = reach + BubbleGeometry.diameter + BubbleGeometry.windowMargin + maxPull
        return CGRect(x: notch.midX - side, y: notch.minY - side, width: 2 * side, height: side + notch.height)
            .integral
    }

    /// Attraction de 0 (au-delà de `reach`) à 1 (à `captureGap`), de plus en plus forte quand l'écart diminue.
    static func strength(gap: CGFloat) -> CGFloat {
        let x = min(max((reach - gap) / (reach - captureGap), 0), 1)
        return x * x
    }

    /// La bulle suit la souris, tirée vers le milieu du bas de la notch d'autant plus qu'elle en est près (jamais
    /// au-delà) ; l'écart rendu est celui de la bulle tirée.
    static func attract(_ center: CGPoint, notch: CGRect) -> (center: CGPoint, strength: CGFloat, gap: CGFloat) {
        let target = CGPoint(x: notch.midX, y: notch.minY)
        let s = strength(gap: BubbleGeometry.gap(center: center, notch: notch))
        let dx = target.x - center.x, dy = target.y - center.y
        let length = max(hypot(dx, dy), 1)
        let pull = min(maxPull * s, max(0, length - BubbleGeometry.radius))
        let pulled = CGPoint(x: center.x + dx / length * pull, y: center.y + dy / length * pull)
        return (pulled, s, BubbleGeometry.gap(center: pulled, notch: notch))
    }

    /// Détente après un lâcher hors de portée : de `s0` à 0 avec une petite oscillation (la bulle s'aplatit un peu du
    /// côté de la notch, puis redevient ronde).
    static func relax(from s0: CGFloat, t: TimeInterval) -> CGFloat {
        guard t < relaxDuration else { return 0 }
        let x = CGFloat(max(t, 0))
        return s0 * exp(-7 * x) * cos(11 * x)
    }

    /// Rayon du contour à l'angle `delta` de la direction de la notch : cercle de rayon `radius`, tendu vers la notch
    /// (`bulge` > 0) ou aplati (< 0), hérissé de pointes en cône (sommet vif, base tangente au cercle).
    static func outlineRadius(_ delta: CGFloat, radius: CGFloat, bulge: CGFloat, spikes: CGFloat,
                              phase: CGFloat) -> CGFloat {
        let d = atan2(sin(delta), cos(delta))
        let front = max(0, cos(d))
        var r = radius * (1 + bulge * front * front - 0.35 * bulge * sin(d) * sin(d))
        guard spikes > 0 else { return r }
        let middle = CGFloat(spikeCount - 1) / 2
        for k in 0..<spikeCount {
            let offset = CGFloat(k) - middle
            let u = abs(d - offset * spikeSpacing) / spikeWidth
            guard u < 1 else { continue }
            // Plus hautes au milieu ; chacune ondule un peu, décalée de ses voisines.
            let height = spikes * (1 - 0.8 * abs(offset) / middle) * (1 + 0.18 * sin(phase + 1.9 * CGFloat(k)))
            r += height * (1 - u) * (1 - u)
        }
        return r
    }

    /// Contour fermé de la bulle de centre `center`, orienté vers l'angle `toward` (y vers le bas).
    static func outline(center: CGPoint, radius: CGFloat, toward: CGFloat, bulge: CGFloat, spikes: CGFloat,
                        phase: CGFloat) -> [CGPoint] {
        guard radius > 0.5 else { return [] }
        return (0..<samples).map { index in
            let delta = CGFloat(index) / CGFloat(samples) * 2 * .pi
            let r = outlineRadius(delta, radius: radius, bulge: bulge, spikes: spikes, phase: phase)
            return CGPoint(x: center.x + r * cos(toward + delta), y: center.y + r * sin(toward + delta))
        }
    }

    /// Point du bas de la notch d'où part la pointe : sous la bulle, sans sortir de la notch.
    static func coneBase(notch: CGRect, toward center: CGPoint) -> CGPoint {
        let margin = coneHalfWidth + 10
        return CGPoint(x: min(max(center.x, notch.minX + margin), max(notch.minX + margin, notch.maxX - margin)),
                       y: notch.maxY)
    }

    /// Pointe qui descend du bas de la notch vers `center` : profil en cône (sommet vif, base tangente au bord). Le
    /// polygone remonte de 6 pt dans la notch pour s'y fondre.
    static func cone(notch: CGRect, toward center: CGPoint, length: CGFloat, halfWidth: CGFloat) -> [CGPoint] {
        guard length > 0.5 else { return [] }
        let base = coneBase(notch: notch, toward: center)
        let dx = center.x - base.x, dy = center.y - base.y
        let norm = max(hypot(dx, dy), 1)
        let steps = 24
        var points = [CGPoint(x: base.x - halfWidth, y: base.y - 6)]
        for index in 0...steps {
            let u = -1 + 2 * CGFloat(index) / CGFloat(steps)
            let h = length * (1 - abs(u)) * (1 - abs(u))
            points.append(CGPoint(x: base.x + u * halfWidth + dx / norm * h, y: base.y + dy / norm * h))
        }
        points.append(CGPoint(x: base.x + halfWidth, y: base.y - 6))
        return points
    }

    /// Col entre le bas de la notch (base de demi-largeur `halfWidth` en `baseX`) et la bulle (`center`, `radius`) :
    /// deux courbes qui partent à plat du bord de la notch et arrivent tangentes au cercle, de part et d'autre de
    /// l'axe, à l'angle `spread` ; refermé par le centre de la bulle.
    static func bridge(notch: CGRect, baseX: CGFloat, halfWidth: CGFloat, center: CGPoint, radius: CGFloat,
                       spread: CGFloat) -> [CGPoint] {
        guard radius > 1 else { return [] }
        let baseY = notch.maxY
        let toward = atan2(baseY - center.y, baseX - center.x)
        func side(_ sign: CGFloat) -> [CGPoint] {
            let start = CGPoint(x: baseX + sign * halfWidth, y: baseY)
            // Point de tangence du même côté que `start`.
            let candidates = [toward + spread, toward - spread].map {
                (angle: $0, point: CGPoint(x: center.x + radius * cos($0), y: center.y + radius * sin($0)))
            }
            let end = candidates.min { hypot($0.point.x - start.x, $0.point.y - start.y)
                < hypot($1.point.x - start.x, $1.point.y - start.y) }!
            var tangent = CGPoint(x: -sin(end.angle), y: cos(end.angle))
            if tangent.x * (start.x - end.point.x) + tangent.y * (start.y - end.point.y) < 0 {
                tangent = CGPoint(x: -tangent.x, y: -tangent.y)
            }
            let reach = hypot(start.x - end.point.x, start.y - end.point.y)
            let c1 = CGPoint(x: start.x - sign * halfWidth * 0.6, y: start.y)
            let c2 = CGPoint(x: end.point.x + tangent.x * reach * 0.45, y: end.point.y + tangent.y * reach * 0.45)
            return (0...20).map { index in
                let t = CGFloat(index) / 20, m = 1 - t
                let a = m * m * m, b = 3 * m * m * t, c = 3 * m * t * t, d = t * t * t
                return CGPoint(x: a * start.x + b * c1.x + c * c2.x + d * end.point.x,
                               y: a * start.y + b * c1.y + c * c2.y + d * end.point.y)
            }
        }
        let left = side(-1), right = side(1)
        return [CGPoint(x: baseX - halfWidth, y: baseY - 6)] + left + [center] + right.reversed()
            + [CGPoint(x: baseX + halfWidth, y: baseY - 6)]
    }

    /// Bulle attirée (ou qui se détend) : contour, pointe de la notch.
    static func approach(notch: CGRect, center: CGPoint, strength s: CGFloat, phase: CGFloat) -> FerroShapes {
        let base = coneBase(notch: notch, toward: center)
        let toward = atan2(base.y - center.y, base.x - center.x)
        let positive = max(0, s)
        let outline = outline(center: center, radius: BubbleGeometry.radius, toward: toward, bulge: 0.16 * s,
                              spikes: spikeHeight * pow(positive, 1.3), phase: phase)
        let cone = cone(notch: notch, toward: center, length: coneLength * positive * positive,
                        halfWidth: coneHalfWidth * (0.6 + 0.4 * positive))
        return FerroShapes(center: center, radius: BubbleGeometry.radius, outline: outline, cone: cone, bridge: [],
                           swell: 0, contentScale: 1, contentOpacity: 1, rimOpacity: 1)
    }

    /// Aspiration (`t` de 0 à 1) depuis `from`, puis rebond de la notch (`t` au-delà de 1, en durées d'aspiration) :
    /// la bulle accélère vers la notch en s'étirant, rétrécit, ses pointes rentrent ; un col épais la relie à la
    /// notch, dont le bas gonfle puis rebondit.
    static func aspirate(notch: CGRect, from: CGPoint, t: CGFloat, phase: CGFloat) -> FerroShapes {
        let baseX = coneBase(notch: notch, toward: from).x
        guard t < 1 else {
            let settle = (t - 1) * CGFloat(aspirateDuration)
            let swell = settle < CGFloat(settleDuration) ? swellHeight * exp(-6 * settle) * cos(16 * settle) : 0
            return FerroShapes(center: CGPoint(x: baseX, y: notch.maxY), radius: 0, outline: [], cone: [], bridge: [],
                               swell: max(0, swell), contentScale: 0, contentOpacity: 0, rimOpacity: 0)
        }
        let t = max(t, 0)
        let travel = pow(t, 2.2)
        let inside = CGPoint(x: baseX, y: notch.maxY - 10)
        let center = CGPoint(x: from.x + (inside.x - from.x) * travel, y: from.y + (inside.y - from.y) * travel)
        let radius = BubbleGeometry.radius * pow(1 - t, 0.75)
        let toward = atan2(notch.maxY - center.y, baseX - center.x)
        let outline = outline(center: center, radius: radius, toward: toward, bulge: 0.16 + 0.55 * t,
                              spikes: spikeHeight * (1 - t) * (1 - t), phase: phase)
        let bridge = bridge(notch: notch, baseX: baseX, halfWidth: 12 + 40 * t, center: center, radius: radius,
                            spread: 0.5 + 0.6 * t)
        let arriving = max(0, (t - 0.55) / 0.45)
        return FerroShapes(center: center, radius: radius, outline: outline, cone: [], bridge: bridge,
                           swell: swellHeight * arriving * arriving, contentScale: radius / BubbleGeometry.radius,
                           contentOpacity: max(0, 1 - t / 0.35), rimOpacity: min(1, max(0, (0.85 - t) / 0.5)))
    }
}

/// Formes du retour aimanté, dans la fenêtre de la bulle (y vers le bas).
struct FerroShapes: Equatable {
    /// Disque de la bulle (le barillet est dessiné dessus).
    var center: CGPoint
    var radius: CGFloat
    /// Contour de la bulle, pointes comprises ; vide = plus de bulle.
    var outline: [CGPoint]
    /// Pointe de la notch vers la bulle (approche), col qui les relie (aspiration) ; vides = rien.
    var cone: [CGPoint]
    var bridge: [CGPoint]
    /// Renflement du bas de la notch, en points.
    var swell: CGFloat
    /// Barillet : il rapetisse avec la bulle et s'efface au début de l'aspiration.
    var contentScale: CGFloat
    var contentOpacity: CGFloat
    /// Bord de la bulle : il s'efface avant qu'elle se fonde dans la notch.
    var rimOpacity: CGFloat
}

/// Retour aimanté en cours dans la fenêtre de la bulle (y vers le bas). Formes recalculées à chaque image d'après
/// l'heure (pointes qui ondulent, détente, aspiration).
struct FerroState: Equatable {
    enum Mode: Equatable {
        /// La bulle suit la souris, attirée (`strength`).
        case approach
        /// Lâchée hors de portée d'aspiration : elle se détend depuis `from`.
        case relax(start: Date, from: CGFloat)
        /// Aspirée par la notch depuis `from`.
        case aspirate(start: Date, from: CGPoint)
    }

    /// Notch dans la fenêtre de la bulle ; son bas est `maxY`.
    var notch: CGRect
    var center: CGPoint
    var strength: CGFloat = 0
    var mode: Mode = .approach

    /// Aspiration et rebond finis : la bulle peut disparaître.
    static var aspirateTotal: TimeInterval { Ferro.aspirateDuration + Ferro.settleDuration }

    func shapes(at date: Date) -> FerroShapes {
        let phase = CGFloat(date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1000)) * 8
        switch mode {
        case .approach:
            return Ferro.approach(notch: notch, center: center, strength: strength, phase: phase)
        case .relax(let start, let s0):
            return Ferro.approach(notch: notch, center: center,
                                  strength: Ferro.relax(from: s0, t: date.timeIntervalSince(start)), phase: phase)
        case .aspirate(let start, let from):
            return Ferro.aspirate(notch: notch, from: from,
                                  t: CGFloat(max(0, date.timeIntervalSince(start)) / Ferro.aspirateDuration),
                                  phase: phase)
        }
    }
}
