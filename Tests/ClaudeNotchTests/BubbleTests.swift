import CoreGraphics
import XCTest
@testable import ClaudeNotch

/// Notch détachée : machine à états, seuils de décollage et d'aimantation, écrans, barillet, goutte, réglages.
/// Logique pure, sans fenêtre.
final class BubbleTests: XCTestCase {
    /// MacBook Pro 14" : encoche de 185 × 32 pt au milieu, barre des menus de 37 pt.
    private static let builtin = ScreenCandidate(
        name: "Écran Retina intégré", frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 945), safeAreaTop: 32,
        auxiliaryLeftWidth: 663.5, auxiliaryRightWidth: 663.5, isBuiltin: true)
    /// Écran externe à droite, plus haut.
    private static let external = ScreenCandidate(
        name: "DELL U2720Q", frame: CGRect(x: 1512, y: -200, width: 2560, height: 1440),
        visibleFrame: CGRect(x: 1512, y: -200, width: 2560, height: 1415))
    private static let notch = CGRect(x: 663.5, y: 950, width: 185, height: 32)

    // MARK: - États

    func testPhaseTransitions() {
        XCTAssertEqual(BubblePhase.attached.next(.grab), .detaching)
        XCTAssertEqual(BubblePhase.detaching.next(.release(detached: false)), .attached, "relâché avant le seuil")
        XCTAssertEqual(BubblePhase.detaching.next(.release(detached: true)), .bubble)
        XCTAssertEqual(BubblePhase.bubble.next(.open), .bubblePanel)
        XCTAssertEqual(BubblePhase.bubblePanel.next(.close), .bubble)
        XCTAssertEqual(BubblePhase.bubble.next(.reattach), .reattaching)
        XCTAssertEqual(BubblePhase.bubblePanel.next(.reattach), .reattaching, "menu « … » du panneau de la bulle")
        XCTAssertEqual(BubblePhase.reattaching.next(.merged), .attached)
        for phase in [BubblePhase.attached, .detaching, .bubble, .bubblePanel, .reattaching] {
            XCTAssertEqual(phase.next(.reset), .attached, "\(phase)")
        }
        // Sans effet hors de leur état.
        XCTAssertEqual(BubblePhase.attached.next(.open), .attached)
        XCTAssertEqual(BubblePhase.attached.next(.reattach), .attached)
        XCTAssertEqual(BubblePhase.bubble.next(.grab), .bubble, "pas de second décollage")
        XCTAssertEqual(BubblePhase.reattaching.next(.open), .reattaching)
        XCTAssertEqual(BubblePhase.detaching.next(.open), .detaching)
    }

    /// La notch ne s'ouvre pas tant que la bulle la remplace ; le décollage en cours n'est pas encore une bulle.
    func testDetachedPhases() {
        XCTAssertEqual([BubblePhase.attached, .detaching, .bubble, .bubblePanel, .reattaching].map(\.isDetached),
                       [false, false, true, true, true])
    }

    // MARK: - Seuils et écrans

    func testDetachProgress() {
        XCTAssertEqual(Goo.progress(distance: 0), 0)
        XCTAssertEqual(Goo.progress(distance: BubbleGeometry.detachDistance / 2), 0.5, accuracy: 0.001)
        XCTAssertEqual(Goo.progress(distance: BubbleGeometry.detachDistance), 1)
        XCTAssertEqual(Goo.progress(distance: 1000), 1)
        XCTAssertEqual(Goo.progress(distance: -5), 0)
    }

    func testMagnetThreshold() {
        let dock = BubbleGeometry.dockPoint(notch: Self.notch)
        XCTAssertTrue(BubbleGeometry.isNearNotch(center: dock, notch: Self.notch))
        // Juste sous la notch, le plus haut que l'écran visible le permet.
        let highest = BubbleGeometry.clamp(CGPoint(x: Self.notch.midX, y: 2000),
                                           visibleFrames: [Self.builtin.visibleFrame])
        XCTAssertTrue(BubbleGeometry.isNearNotch(center: highest, notch: Self.notch))
        let edge = BubbleGeometry.radius + BubbleGeometry.magnetGap
        XCTAssertTrue(BubbleGeometry.isNearNotch(center: CGPoint(x: Self.notch.midX, y: Self.notch.minY - edge + 1),
                                                 notch: Self.notch))
        XCTAssertFalse(BubbleGeometry.isNearNotch(center: CGPoint(x: Self.notch.midX, y: Self.notch.minY - edge - 1),
                                                  notch: Self.notch))
        XCTAssertFalse(BubbleGeometry.isNearNotch(center: CGPoint(x: 200, y: 500), notch: Self.notch))
        // Aimantée : tirée vers la notch ; loin : inchangée.
        let near = CGPoint(x: Self.notch.midX + 40, y: dock.y - 10)
        let pulled = BubbleGeometry.magnetized(center: near, notch: Self.notch)
        XCTAssertLessThan(hypot(pulled.x - dock.x, pulled.y - dock.y), hypot(near.x - dock.x, near.y - dock.y))
        XCTAssertEqual(BubbleGeometry.magnetized(center: CGPoint(x: 200, y: 500), notch: Self.notch),
                       CGPoint(x: 200, y: 500))
    }

    func testClampToVisibleScreens() {
        let frames = [Self.builtin.visibleFrame, Self.external.visibleFrame]
        let inset = BubbleGeometry.radius + BubbleGeometry.screenInset
        XCTAssertEqual(BubbleGeometry.clamp(CGPoint(x: 700, y: 500), visibleFrames: frames), CGPoint(x: 700, y: 500))
        // Sous la barre des menus : redescend sous le haut de l'écran visible.
        XCTAssertEqual(BubbleGeometry.clamp(CGPoint(x: 700, y: 970), visibleFrames: frames),
                       CGPoint(x: 700, y: 945 - inset))
        // Hors de tout écran à gauche.
        XCTAssertEqual(BubbleGeometry.clamp(CGPoint(x: -300, y: 400), visibleFrames: frames), CGPoint(x: inset, y: 400))
        // Sur l'écran externe, plus bas que l'écran intégré : reste sur l'externe.
        XCTAssertEqual(BubbleGeometry.clamp(CGPoint(x: 2000, y: -100), visibleFrames: frames), CGPoint(x: 2000, y: -100))
        // Sous l'écran intégré, à côté de l'externe : le plus proche est l'externe.
        let below = BubbleGeometry.clamp(CGPoint(x: 1490, y: -100), visibleFrames: frames)
        XCTAssertEqual(below, CGPoint(x: 1512 + inset, y: -100))
        XCTAssertEqual(BubbleGeometry.clamp(CGPoint(x: 5, y: 5), visibleFrames: []), CGPoint(x: 5, y: 5))
    }

    func testPanelFrameStaysOnScreen() {
        let visible = Self.builtin.visibleFrame
        let size = CGSize(width: 560, height: 400)
        let middle = BubbleGeometry.panelFrame(size: size, bubble: CGPoint(x: 700, y: 600), visible: visible)
        XCTAssertEqual(middle.midX, 700)
        XCTAssertEqual(middle.maxY, 600 + BubbleGeometry.radius, "le haut au niveau du haut de la bulle")
        // Bulle en bas à droite : le panneau remonte et rentre dans l'écran.
        let corner = BubbleGeometry.panelFrame(size: size, bubble: CGPoint(x: 1450, y: 90), visible: visible)
        XCTAssertTrue(visible.contains(corner), "\(corner)")
    }

    // MARK: - Position par écran

    func testPositionIsRememberedPerScreen() throws {
        let screens = [Self.builtin, Self.external]
        let saved = try XCTUnwrap(BubblePlacement.save(center: CGPoint(x: 2100, y: 300), screens: screens))
        XCTAssertEqual(saved.label, "DELL U2720Q")
        XCTAssertEqual(saved.offset, [588, 500], "décalage depuis l'origine de l'écran")
        let onBuiltin = try XCTUnwrap(BubblePlacement.save(center: CGPoint(x: 400, y: 300), screens: screens))
        let positions = [saved.label: saved.offset, onBuiltin.label: onBuiltin.offset]

        // Dernier écran branché : sa position.
        let back = try XCTUnwrap(BubblePlacement.restore(screens: screens, notchScreen: 0, notch: Self.notch,
                                                         lastScreen: "DELL U2720Q", saved: positions))
        XCTAssertEqual(back.screen, 1)
        XCTAssertEqual(back.center, CGPoint(x: 2100, y: 300))
        // L'écran externe a bougé dans l'arrangement : la bulle reste au même endroit de cet écran.
        var moved = Self.external
        moved.frame.origin = CGPoint(x: -2560, y: 0)
        moved.visibleFrame.origin = CGPoint(x: -2560, y: 0)
        let follow = try XCTUnwrap(BubblePlacement.restore(screens: [Self.builtin, moved], notchScreen: 0,
                                                           notch: Self.notch, lastScreen: "DELL U2720Q",
                                                           saved: positions))
        XCTAssertEqual(follow.center, CGPoint(x: -2560 + 588, y: 500))
        // Écran débranché : celui de la notch, avec sa propre position.
        let unplugged = try XCTUnwrap(BubblePlacement.restore(screens: [Self.builtin], notchScreen: 0,
                                                              notch: Self.notch, lastScreen: "DELL U2720Q",
                                                              saved: positions))
        XCTAssertEqual(unplugged.screen, 0)
        XCTAssertEqual(unplugged.center, CGPoint(x: 400, y: 300))
        // Rien de rangé : sous la notch, à droite, dans l'écran visible.
        let fresh = try XCTUnwrap(BubblePlacement.restore(screens: [Self.builtin], notchScreen: 0, notch: Self.notch,
                                                          lastScreen: nil, saved: [:]))
        XCTAssertEqual(fresh.center, BubblePlacement.defaultCenter(notch: Self.notch))
        XCTAssertTrue(Self.builtin.visibleFrame.contains(fresh.center))
        // Valeur abîmée dans les réglages : ignorée.
        let broken = try XCTUnwrap(BubblePlacement.restore(screens: [Self.builtin], notchScreen: 0, notch: Self.notch,
                                                           lastScreen: nil,
                                                           saved: ["Écran Retina intégré": [.nan, 3]]))
        XCTAssertEqual(broken.center, fresh.center)
        // Position rangée hors de l'écran visible (Dock agrandi depuis) : ramenée dedans.
        let clamped = try XCTUnwrap(BubblePlacement.restore(screens: [Self.builtin], notchScreen: 0, notch: Self.notch,
                                                            lastScreen: nil,
                                                            saved: ["Écran Retina intégré": [5, 5]]))
        XCTAssertEqual(clamped.center, BubbleGeometry.clamp(CGPoint(x: 5, y: 5),
                                                            visibleFrames: [Self.builtin.visibleFrame]))
        XCTAssertNil(BubblePlacement.restore(screens: [], notchScreen: 0, notch: Self.notch, lastScreen: nil, saved: [:]))
    }

    func testPreferencesPersistBubble() {
        let defaults = makeEphemeralDefaults(self)
        let prefs = Preferences(defaults: defaults)
        XCTAssertTrue(prefs.allowsDetach, "activé par défaut")
        XCTAssertFalse(prefs.bubbleReturnsOnRelaunch)
        XCTAssertFalse(prefs.bubbleDetached)
        XCTAssertNil(prefs.bubbleScreen)
        XCTAssertEqual(prefs.bubblePositions, [:])

        prefs.allowsDetach = false
        prefs.bubbleReturnsOnRelaunch = true
        prefs.bubbleDetached = true
        prefs.bubbleScreen = "DELL U2720Q"
        prefs.bubblePositions = ["DELL U2720Q": [588, 500], "Écran Retina intégré": [400, 300]]
        let reread = Preferences(defaults: defaults)
        XCTAssertFalse(reread.allowsDetach)
        XCTAssertTrue(reread.bubbleReturnsOnRelaunch)
        XCTAssertTrue(reread.bubbleDetached)
        XCTAssertEqual(reread.bubbleScreen, "DELL U2720Q")
        XCTAssertEqual(reread.bubblePositions["DELL U2720Q"], [588, 500])

        // « Rétablir les réglages par défaut » : les réglages reviennent, pas l'état ni les positions de la bulle.
        reread.resetNotchSettings()
        XCTAssertTrue(reread.allowsDetach)
        XCTAssertFalse(reread.bubbleReturnsOnRelaunch)
        XCTAssertTrue(reread.bubbleDetached)
        XCTAssertEqual(reread.bubblePositions.count, 2)
    }

    // MARK: - Barillet

    func testRevolverGeometry() {
        for count in 4...10 {
            let revolver = Revolver(count: count, turn: 0)
            let center = CGPoint(x: 74, y: 74)
            let top = revolver.position(of: 0, center: center)
            XCTAssertEqual(top.x, 74, accuracy: 0.001, "onglet actif en haut (\(count))")
            XCTAssertEqual(top.y, 74 - Revolver.ringRadius, accuracy: 0.001)
            // Sens horaire : le suivant est à droite du haut.
            XCTAssertGreaterThan(revolver.position(of: 1, center: center).x, 74)
            // Les chambres ne se touchent pas et restent dans la bulle.
            let chamber = Revolver.chamberDiameter(count: count)
            let a = revolver.position(of: 0, center: center), b = revolver.position(of: 1, center: center)
            XCTAssertGreaterThan(hypot(a.x - b.x, a.y - b.y), chamber + 2, "\(count) onglets")
            XCTAssertLessThan(Revolver.ringRadius + chamber / 2, BubbleGeometry.radius - 4)
            XCTAssertGreaterThan(Revolver.ringRadius - chamber / 2, Revolver.hubRadius, "le moyeu ne touche pas")
        }
        XCTAssertEqual(Revolver.chamberDiameter(count: 4), 28)
        XCTAssertLessThan(Revolver.chamberDiameter(count: 10), 28)
    }

    func testRevolverTurnsByDetents() {
        var revolver = Revolver(count: 6, turn: 0)
        XCTAssertEqual(revolver.activeIndex, 0)
        revolver.rotate(by: 1)
        XCTAssertEqual(revolver.activeIndex, 1)
        XCTAssertEqual(revolver.angle(of: 1), 0, accuracy: 1e-9, "l'onglet 1 est en haut")
        revolver.rotate(by: -3)
        XCTAssertEqual(revolver.turn, -2)
        XCTAssertEqual(revolver.activeIndex, 4, "tour négatif ramené dans les onglets")
        revolver.rotate(by: 14)
        XCTAssertEqual(revolver.activeIndex, 0)
        XCTAssertEqual(revolver.rotation, -Double(revolver.turn) * revolver.step, accuracy: 1e-9)

        // Clic sur une chambre : le plus court chemin.
        let still = Revolver(count: 6, turn: 0)
        XCTAssertEqual(still.steps(toTop: 0), 0)
        XCTAssertEqual(still.steps(toTop: 1), 1)
        XCTAssertEqual(still.steps(toTop: 5), -1)
        XCTAssertEqual(still.steps(toTop: 3), 3, "à égalité : sens horaire")
        XCTAssertEqual(Revolver(count: 6, turn: -2).steps(toTop: 3), -1)
        XCTAssertEqual(Revolver(count: 7, turn: 0).steps(toTop: 4), -3)
        XCTAssertEqual(Revolver(count: 0, turn: 3).steps(toTop: 0), 0)
        XCTAssertEqual(Revolver(count: 0, turn: 3).activeIndex, 0)
    }

    func testRevolverZones() {
        let revolver = Revolver(count: 8, turn: 0)
        let center = CGPoint(x: 74, y: 74)
        XCTAssertEqual(revolver.zone(at: center, center: center), .hub)
        XCTAssertEqual(revolver.zone(at: revolver.position(of: 3, center: center), center: center), .chamber(3))
        XCTAssertEqual(Revolver(count: 8, turn: 3).zone(at: CGPoint(x: 74, y: 74 - Revolver.ringRadius), center: center),
                       .chamber(3), "la chambre du haut après trois crans")
        XCTAssertEqual(revolver.zone(at: CGPoint(x: 74, y: 3), center: center), .rim)
        XCTAssertEqual(revolver.zone(at: CGPoint(x: 2, y: 2), center: center), .outside)
    }

    func testScrollAccumulatesToDetents() {
        var scroll = RevolverScroll()
        // Trackpad : 28 pt par cran, le reste attend.
        XCTAssertEqual(scroll.add(deltaX: 0, deltaY: -10, precise: true), 0)
        XCTAssertEqual(scroll.add(deltaX: 0, deltaY: -10, precise: true), 0)
        XCTAssertEqual(scroll.add(deltaX: 0, deltaY: -10, precise: true), 1)
        XCTAssertEqual(scroll.add(deltaX: 0, deltaY: -60, precise: true), 2)
        // Demi-tour : le reste dans l'autre sens est oublié.
        XCTAssertEqual(scroll.add(deltaX: 0, deltaY: 20, precise: true), 0)
        XCTAssertEqual(scroll.add(deltaX: 0, deltaY: 10, precise: true), -1)
        // Molette : une ligne = un cran, quelle que soit sa taille.
        scroll.reset()
        XCTAssertEqual(scroll.add(deltaX: 0, deltaY: -0.1, precise: false), 1)
        XCTAssertEqual(scroll.add(deltaX: 0, deltaY: 3, precise: false), -1)
        // Glisser horizontal sur le trackpad.
        scroll.reset()
        XCTAssertEqual(scroll.add(deltaX: 30, deltaY: 2, precise: true), 1)
        XCTAssertEqual(scroll.add(deltaX: 0, deltaY: 0, precise: true), 0)
    }

    func testCircularDragTurnsByDetents() {
        let step = 2 * Double.pi / 6
        var drag = RevolverDrag(startAngle: 0, step: step)
        XCTAssertEqual(drag.move(to: step * 0.4), 0)
        XCTAssertEqual(drag.move(to: step * 0.6), -1, "sens horaire : l'onglet de gauche monte")
        XCTAssertEqual(drag.move(to: step * 1.4), 0)
        XCTAssertEqual(drag.move(to: step * 0.2), 1, "retour en arrière")
        // Plus d'un demi-tour, à travers ±π.
        var long = RevolverDrag(startAngle: 0, step: step)
        var total = 0
        for index in 1...24 { total += long.move(to: Double(index) * step / 4) }
        XCTAssertEqual(total, -6, "un tour complet = six crans")
        // À travers ±π (atan2) : 63° parcourus, pas un tour à l'envers.
        var wrap = RevolverDrag(startAngle: .pi - 0.3, step: step)
        XCTAssertEqual(wrap.move(to: -.pi + 0.8), -1)
        var none = RevolverDrag(startAngle: 0, step: 0)
        XCTAssertEqual(none.move(to: 1), 0)
    }

    // MARK: - Goutte

    func testNeckThinsUntilItSnaps() {
        func middle(_ p: CGFloat) -> CGFloat { Goo.neckRadius(t: 0.5, progress: p, start: 30, end: 40) }
        XCTAssertGreaterThan(middle(0.1), middle(0.5))
        XCTAssertGreaterThan(middle(0.5), middle(0.9))
        XCTAssertEqual(middle(1), Goo.neckFloor, accuracy: 0.001, "au seuil, le col est au plus fin, encore visible")
        XCTAssertGreaterThanOrEqual(Goo.neckFloor, Goo.blur * 0.7, "plus fin, le seuil l'effacerait avant la rupture")
        // Pincé au milieu, épais aux bouts.
        XCTAssertLessThan(Goo.neckRadius(t: 0.5, progress: 0.6, start: 30, end: 30),
                          Goo.neckRadius(t: 0.05, progress: 0.6, start: 30, end: 30))
        XCTAssertGreaterThan(Goo.dropRadius(progress: 1), Goo.dropRadius(progress: 0))
        XCTAssertEqual(Goo.dropRadius(progress: 1), BubbleGeometry.radius * 0.72, accuracy: 0.001,
                       "au seuil, la goutte a la taille de la bulle à son apparition (échelle 0,72)")
    }

    func testGooStagesFollowTheDrop() {
        let panel = CGRect(x: 100, y: -20, width: 540, height: 320)
        let notch = CGRect(x: 277, y: -20, width: 185, height: 52)
        let handle = CGPoint(x: 620, y: 290)
        let state = GooState(panel: panel, notch: notch, handle: handle, drop: CGPoint(x: 660, y: 360))
        let shapes = state.shapes(at: Date())
        XCTAssertEqual(shapes.drop.center, CGPoint(x: 660, y: 360))
        XCTAssertEqual(shapes.neck.count, Goo.neckCount)
        assertEqual(shapes.neck.last?.center ?? .zero, shapes.drop.center, "le col finit sur la goutte")
        XCTAssertTrue(shapes.body.insetBy(dx: -1, dy: -1).contains(shapes.neck[0].center), "et part du corps")
        // Le corps se replie vers la notch quand la goutte s'éloigne.
        let far = GooState(panel: panel, notch: notch, handle: handle, drop: CGPoint(x: 700, y: 400)).shapes(at: Date())
        XCTAssertLessThan(far.body.width, shapes.body.width)

        // Décollé : plus de goutte, le corps rentre dans la notch.
        let start = Date()
        var snap = state
        snap.mode = .snap(start: start)
        XCTAssertEqual(snap.shapes(at: start).drop.radius, 0)
        let done = snap.shapes(at: start.addingTimeInterval(Goo.snapDuration))
        assertEqual(done.body, notch)
        XCTAssertTrue(done.neck.allSatisfy { $0.radius == 0 })

        // Abandonné : la goutte revient à la poignée et disparaît, le corps redevient le panneau.
        var cancel = state
        cancel.mode = .cancel(start: start, from: state.drop, progress: state.progress)
        let back = cancel.shapes(at: start.addingTimeInterval(Goo.cancelDuration))
        XCTAssertEqual(back.drop.radius, 0, accuracy: 0.001)
        XCTAssertEqual(back.body, panel)

        // Rattachement : la goutte monte dans la notch et s'y fond.
        var merge = state
        merge.mode = .merge(start: start, from: CGPoint(x: 370, y: 200))
        let first = merge.shapes(at: start)
        XCTAssertEqual(first.drop.radius, BubbleGeometry.radius, accuracy: 0.001)
        let last = merge.shapes(at: start.addingTimeInterval(Goo.mergeDuration))
        XCTAssertEqual(last.drop.radius, 0, accuracy: 0.001)
        XCTAssertEqual(last.body.width, notch.width, accuracy: 0.001)

        // Détachement par le menu : la goutte va seule jusqu'au seuil.
        var auto = state
        auto.drop = handle
        auto.mode = .autoPull(start: start, to: CGPoint(x: handle.x, y: handle.y + BubbleGeometry.detachDistance))
        XCTAssertEqual(auto.shapes(at: start).drop.center, handle)
        let arrived = auto.shapes(at: start.addingTimeInterval(Goo.autoPullDuration))
        XCTAssertEqual(arrived.drop.center.y, handle.y + BubbleGeometry.detachDistance, accuracy: 0.001)
        XCTAssertEqual(arrived.drop.center.x, handle.x, accuracy: 0.001)
        XCTAssertEqual(arrived.drop.radius, Goo.dropRadius(progress: 1), accuracy: 0.001)
    }

    private func assertEqual(_ a: CGPoint, _ b: CGPoint, _ message: String = "", line: UInt = #line) {
        XCTAssertEqual(a.x, b.x, accuracy: 0.001, message, line: line)
        XCTAssertEqual(a.y, b.y, accuracy: 0.001, message, line: line)
    }

    private func assertEqual(_ a: CGRect, _ b: CGRect, line: UInt = #line) {
        assertEqual(a.origin, b.origin, line: line)
        XCTAssertEqual(a.width, b.width, accuracy: 0.001, line: line)
        XCTAssertEqual(a.height, b.height, accuracy: 0.001, line: line)
    }

    func testGooCoordinates() {
        let local = GooCoordinates(CGRect(x: 100, y: 500, width: 400, height: 300))
        XCTAssertEqual(local.point(CGPoint(x: 150, y: 790)), CGPoint(x: 50, y: 10), "y vers le bas depuis le haut")
        // Forme collée en haut de l'écran : prolongée au-dessus de la fenêtre.
        let body = local.body(CGRect(x: 200, y: 700, width: 100, height: 70))
        XCTAssertEqual(body.minX, 100)
        XCTAssertLessThan(body.minY, 0)
        XCTAssertEqual(body.maxY, 100, "bas de la forme : 800 − 700")
    }
}
