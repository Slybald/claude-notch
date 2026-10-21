import AppKit
import SwiftUI
import XCTest
@testable import ClaudeNotch

/// Mode édition des onglets dans la notch : règles pures, stockage partagé avec Réglages › Onglets, sorties du mode.
final class TabEditingTests: XCTestCase {
    private func settle() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }

    // MARK: - Règles pures

    func testMoveKeepsHiddenTabsInTheirSlots() {
        // b masqué : a, c, d se redistribuent dans leurs cases, b ne bouge pas.
        let order = ["a", "b", "c", "d"]
        let shown = ["a", "c", "d"]
        XCTAssertEqual(TabEditing.move("d", to: 0, order: order, enabled: shown), ["d", "b", "a", "c"])
        XCTAssertEqual(TabEditing.move("a", to: 2, order: order, enabled: shown), ["c", "b", "d", "a"])
        XCTAssertEqual(TabEditing.move("c", to: 1, order: order, enabled: shown), order, "même place")
        XCTAssertEqual(TabEditing.move("a", to: 99, order: order, enabled: shown), ["c", "b", "d", "a"], "borné")
        XCTAssertEqual(TabEditing.move("a", to: -3, order: order, enabled: shown), order, "borné")
        XCTAssertEqual(TabEditing.move("b", to: 0, order: order, enabled: shown), order, "onglet masqué : rien")
    }

    func testLastShownTabCannotBeHidden() {
        XCTAssertTrue(TabEditing.canHide("a", enabled: ["a", "b"]))
        XCTAssertFalse(TabEditing.canHide("a", enabled: ["a"]), "dernier onglet")
        XCTAssertFalse(TabEditing.canHide("c", enabled: ["a", "b"]), "déjà masqué")
    }

    func testDropIndexAndShift() {
        let slot: CGFloat = 29
        XCTAssertEqual(TabEditing.dropIndex(from: 1, translation: 10, slot: slot, count: 4), 1, "moins d'une demi-case")
        XCTAssertEqual(TabEditing.dropIndex(from: 1, translation: 15, slot: slot, count: 4), 2)
        XCTAssertEqual(TabEditing.dropIndex(from: 1, translation: -40, slot: slot, count: 4), 0)
        XCTAssertEqual(TabEditing.dropIndex(from: 1, translation: 500, slot: slot, count: 4), 3, "borné à droite")
        XCTAssertEqual(TabEditing.dropIndex(from: 1, translation: -500, slot: slot, count: 4), 0, "borné à gauche")
        // L'onglet 1 glisse vers 3 : 2 et 3 reculent d'une case, 0 ne bouge pas.
        XCTAssertEqual((0..<4).map { TabEditing.shift($0, from: 1, to: 3) }, [0, 0, -1, -1])
        // L'onglet 3 glisse vers 0 : 0, 1, 2 avancent.
        XCTAssertEqual((0..<4).map { TabEditing.shift($0, from: 3, to: 0) }, [1, 1, 1, 0])
        XCTAssertEqual((0..<4).map { TabEditing.shift($0, from: 2, to: 2) }, [0, 0, 0, 0])
    }

    // MARK: - Stockage partagé avec les réglages

    private func registry(_ ids: [String] = ["a", "b", "c", "d"]) -> (ModuleRegistry, Preferences, [FakeModule]) {
        let prefs = Preferences(defaults: makeEphemeralDefaults(self))
        let modules = ids.map { FakeModule(id: $0) }
        return (ModuleRegistry(modules: modules, prefs: prefs), prefs, modules)
    }

    func testMoveFromNotchIsSavedLikeSettings() {
        let (registry, prefs, _) = registry()
        registry.hideTab("b")
        settle()
        registry.moveTab("d", to: 0)
        XCTAssertEqual(prefs.tabOrder, ["d", "b", "a", "c"], "même clé que Réglages › Onglets")
        settle()
        XCTAssertEqual(registry.enabled.map { $0.id }, ["d", "a", "c"])
        XCTAssertEqual(registry.ordered.map { $0.id }, ["d", "b", "a", "c"], "liste des réglages à jour")
    }

    func testHideStopsModuleAndKeepsOneTab() {
        let (registry, prefs, modules) = registry(["a", "b"])
        registry.setPanelOpen(true)
        XCTAssertTrue(modules[0].isRunning)
        XCTAssertTrue(registry.hideTab("a"))
        XCTAssertEqual(prefs.tabEnabled["a"], false, "même clé que l'interrupteur des réglages")
        settle()
        XCTAssertFalse(modules[0].isRunning, "un onglet masqué arrête son module")
        XCTAssertFalse(registry.hideTab("b"), "le dernier onglet reste")
        XCTAssertNotEqual(prefs.tabEnabled["b"], false)
        XCTAssertEqual(registry.hidden.map { $0.id }, ["a"])
    }

    func testShowPutsTabBackAtTheEnd() {
        let (registry, prefs, modules) = registry()
        registry.setPanelOpen(true)
        registry.hideTab("a")
        settle()
        registry.showTab("a")
        settle()
        XCTAssertEqual(registry.enabled.map { $0.id }, ["b", "c", "d", "a"], "en bout de barre, là où est le « + »")
        XCTAssertEqual(prefs.tabEnabled["a"], true)
        XCTAssertTrue(modules[0].isRunning, "son module redémarre")
        XCTAssertTrue(registry.hidden.isEmpty)
        registry.showTab("a")
        registry.showTab("inconnu")
        XCTAssertEqual(prefs.tabOrder, ["b", "c", "d", "a"], "rien pour un onglet déjà affiché ou inconnu")
    }

    /// Les réglages changent pendant le mode édition : la notch suit, et l'inverse.
    func testSettingsAndNotchStayInSync() {
        let (registry, prefs, _) = registry()
        registry.setEnabled("c", false) // interrupteur de Réglages › Onglets
        settle()
        XCTAssertEqual(registry.hidden.map { $0.id }, ["c"], "proposé par le « + » de la notch")
        registry.move(from: IndexSet(integer: 3), to: 0) // glisser dans les réglages
        settle()
        XCTAssertEqual(registry.enabled.map { $0.id }, ["d", "a", "b"])
        // Deux gestes dans la notch avant que le registre se relise : chacun part des réglages, pas d'un ordre périmé.
        registry.moveTab("b", to: 0)
        registry.moveTab("a", to: 0)
        XCTAssertEqual(prefs.tabOrder, ["a", "b", "d", "c"])
        settle()
        XCTAssertEqual(registry.ordered.map { $0.id }, ["a", "b", "d", "c"])
    }
}
