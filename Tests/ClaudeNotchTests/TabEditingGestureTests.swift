import AppKit
import SwiftUI
import XCTest
@testable import ClaudeNotch

/// Gestes du mode édition, joués par des événements souris envoyés à la notch dépliée (fenêtre hors écran) :
/// appui long, glisser, « − », OK, clic hors de la barre.
final class TabEditingGestureTests: XCTestCase {
    private var notch: NotchHarness!
    private var window: NSPanel!

    override func setUp() {
        super.setUp()
        notch = NotchHarness(self)
        notch.model.isExpanded = true
        let hosting = FirstMouseHostingView(rootView: notch.root)
        hosting.sizingOptions = []
        hosting.frame = CGRect(origin: .zero, size: NotchController.panelSize)
        window = NSPanel(contentRect: hosting.frame, styleMask: [.borderless, .nonactivatingPanel],
                         backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.orderFrontRegardless()
        wait(0.6)
    }

    override func tearDown() {
        window.close()
        super.tearDown()
    }

    private func wait(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    // MARK: - Géométrie (fenêtre de 800 × 480, origine en bas à gauche)

    /// Bord gauche du contenu : panneau centré, rayon haut de 12 pt, marge de 14 pt.
    private var contentLeft: CGFloat {
        NotchController.panelSize.width / 2 - (notch.prefs.expandedWidth(compact: false) + 24) / 2 + 12 + 14
    }
    private var contentRight: CGFloat { NotchController.panelSize.width - contentLeft }
    /// Milieu de la ligne d'en-tête : sous la bande de 32 pt, ligne de 24 pt.
    private var headerY: CGFloat { NotchController.panelSize.height - 32 - 12 }

    private func tabCenter(_ index: Int) -> CGPoint {
        CGPoint(x: contentLeft + CGFloat(index) * (NotchTabBar.tabWidth + NotchTabBar.spacing)
                + NotchTabBar.tabWidth / 2, y: headerY)
    }

    /// « − » posé en haut à gauche de l'icône (décalé de -3, -4, cercle de 12 pt).
    private func hideBadge(_ index: Int) -> CGPoint {
        let left = contentLeft + CGFloat(index) * (NotchTabBar.tabWidth + NotchTabBar.spacing)
        return CGPoint(x: left + 3, y: headerY + 11 + 4 - 6)
    }

    private func send(_ type: NSEvent.EventType, _ point: CGPoint) {
        let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                                       timestamp: ProcessInfo.processInfo.systemUptime,
                                       windowNumber: window.windowNumber, context: nil, eventNumber: 0,
                                       clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1)
        window.sendEvent(event!)
    }

    private func click(_ point: CGPoint) {
        send(.leftMouseDown, point)
        wait(0.05)
        send(.leftMouseUp, point)
        wait(0.3)
    }

    private func longPress(_ point: CGPoint) {
        send(.leftMouseDown, point)
        wait(TabEditing.pressDuration + 0.25)
        send(.leftMouseUp, point)
        wait(0.4)
    }

    private func drag(from start: CGPoint, by dx: CGFloat) {
        send(.leftMouseDown, start)
        wait(0.05)
        let steps = 12
        for step in 1...steps {
            send(.leftMouseDragged, CGPoint(x: start.x + dx * CGFloat(step) / CGFloat(steps), y: start.y))
            wait(0.02)
        }
        send(.leftMouseUp, CGPoint(x: start.x + dx, y: start.y))
        wait(0.5)
    }

    private var shown: [String] { notch.registry.enabled.map { $0.id } }

    // MARK: - Gestes

    func testShortClickSelectsTabAndLongPressStartsEditing() {
        click(tabCenter(1))
        XCTAssertEqual(notch.model.selectedTab, shown[1], "clic simple : changement d'onglet")
        XCTAssertFalse(notch.model.isEditingTabs, "clic simple : pas de mode édition")
        longPress(tabCenter(2))
        XCTAssertTrue(notch.model.isEditingTabs, "appui long : mode édition")
    }

    func testDragMovesTabAndSavesOrder() {
        longPress(tabCenter(0))
        XCTAssertTrue(notch.model.isEditingTabs)
        let before = shown
        // Deux cases vers la droite.
        drag(from: tabCenter(0), by: 2 * (NotchTabBar.tabWidth + NotchTabBar.spacing))
        var expected = before
        expected.insert(expected.removeFirst(), at: 2)
        XCTAssertEqual(shown, expected, "onglet glissé de deux cases")
        XCTAssertEqual(Array(notch.prefs.tabOrder.prefix(3)), Array(expected.prefix(3)), "enregistré dans les réglages")
        XCTAssertTrue(notch.model.isEditingTabs, "le glisser ne sort pas du mode")
    }

    func testMinusHidesTab() {
        longPress(tabCenter(0))
        let before = shown
        click(hideBadge(1))
        XCTAssertEqual(shown, before.filter { $0 != before[1] }, "« − » masque l'onglet")
        XCTAssertEqual(notch.prefs.tabEnabled[before[1]], false)
        XCTAssertTrue(notch.model.isEditingTabs)
    }

    func testClickOnBarStaysAndClickElsewhereLeaves() {
        longPress(tabCenter(0))
        click(tabCenter(1))
        XCTAssertTrue(notch.model.isEditingTabs, "clic sur une icône : on reste dans le mode")
        // Dans le contenu de l'onglet (estompé, il ne prend plus les clics), sous la ligne d'en-tête.
        XCTAssertGreaterThan(notch.model.contentSize.height, 32 + 24 + 40, "panneau assez haut")
        click(CGPoint(x: NotchController.panelSize.width / 2, y: headerY - 40))
        XCTAssertFalse(notch.model.isEditingTabs, "clic sous la barre : sortie du mode")
    }

    func testDoneButtonLeaves() {
        longPress(tabCenter(0))
        click(CGPoint(x: contentRight - 20, y: headerY))
        XCTAssertFalse(notch.model.isEditingTabs, "OK : sortie du mode")
    }
}
