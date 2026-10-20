import AppKit
import SwiftUI
import XCTest
@testable import ClaudeNotch

/// Mise en page et rendus PNG de l'onglet « Réglages rapides », sur des doubles.
/// Rendus : `CLAUDE_NOTCH_SNAPSHOT_DIR=/dossier swift test --filter QuickSettingsSnapshotTests`.
final class QuickSettingsSnapshotTests: XCTestCase {
    private var outputDir: URL? {
        ProcessInfo.processInfo.environment["CLAUDE_NOTCH_SNAPSHOT_DIR"].map { URL(fileURLWithPath: $0) }
    }

    private struct Scene {
        let harness: NotchHarness
        let registry: ModuleRegistry
        let root: NotchRootView
    }

    private func scene(_ fixture: QuickSettingsFixture, expanded: Bool = true, fullScreen: Bool = false) -> Scene {
        let harness = NotchHarness(self)
        let registry = ModuleRegistry(modules: [harness.claude, fixture.module], prefs: harness.prefs)
        harness.model.isExpanded = expanded
        harness.model.selectedTab = "quicksettings"
        harness.model.isFullScreen = fullScreen
        let root = NotchRootView(model: harness.model, store: harness.store, registry: registry, prefs: harness.prefs,
                                 actions: NotchActions())
        return Scene(harness: harness, registry: registry, root: root)
    }

    // MARK: - États

    /// Tout éteint, un Mac portable sur batterie.
    private func idleFixture() -> QuickSettingsFixture {
        let f = QuickSettingsFixture(self)
        f.wifi.power = true
        f.power.lowPower = false
        f.battery.iops = [QSFakeBattery.mac(percent: 78)]
        f.module.prefs.focusOnShortcut = "Concentration activer"
        f.module.prefs.focusOffShortcut = "Concentration désactiver"
        f.startAndShow()
        return f
    }

    /// Tout actif : caféine, économie d'énergie, Concentration, en charge, AirPods.
    private func busyFixture() -> QuickSettingsFixture {
        let f = QuickSettingsFixture(self)
        f.power.lowPower = true
        f.battery.iops = [QSFakeBattery.mac(percent: 64, pluggedIn: true, charging: true, minutes: 72)]
        f.battery.pmset = [FakeBatteryFixtures.pods, FakeBatteryFixtures.case]
        f.module.prefs.focusOnShortcut = "Concentration activer"
        f.module.prefs.focusOffShortcut = "Concentration désactiver"
        f.startAndShow()
        f.module.toggleFocus()
        f.module.startCaffeine(until: f.now.addingTimeInterval(72 * 60))
        f.module.applyScene(.autonomy)
        f.module.startCaffeine(until: f.now.addingTimeInterval(72 * 60))
        return f
    }

    private func errorFixture() -> QuickSettingsFixture {
        let f = idleFixture()
        f.wifi.failure = QuickSettingsFailure(.denied)
        f.module.toggleWiFi()
        return f
    }

    private func desktopFixture() -> QuickSettingsFixture {
        let f = QuickSettingsFixture(self)
        f.wifi.power = nil
        f.bluetooth.power = nil
        f.power.supported = false
        f.battery.iops = []
        f.startAndShow()
        return f
    }

    // MARK: - Mise en page (toujours exécutée)

    /// Le pire cas (toutes les tuiles, deux accessoires, un message d'erreur avec action) tient dans le panneau, à
    /// chaque largeur.
    func testTabFitsInThePanelInTheWorstCase() {
        for size in PanelSize.allCases {
            let f = busyFixture()
            f.wifi.failure = QuickSettingsFailure(.failed, "Operation not permitted by the system")
            f.module.toggleWiFi()
            XCTAssertNotNil(f.module.issue)
            let scene = scene(f)
            scene.harness.prefs.panelSize = size
            let measured = measure(scene)
            XCTAssertEqual(measured.width, size.width + 24, accuracy: 1, size.rawValue)
            XCTAssertLessThanOrEqual(measured.height, 461, size.rawValue)
            XCTAssertGreaterThan(measured.height, 200, size.rawValue)
        }
    }

    func testCompactModeFitsAndKeepsItsWidth() {
        let f = busyFixture()
        let scene = scene(f, fullScreen: true)
        let measured = measure(scene)
        XCTAssertEqual(measured.width, Preferences.compactPanelWidth + 24, accuracy: 1)
        XCTAssertLessThanOrEqual(measured.height, 461)
    }

    /// Le texte du résumé compact et celui des tuiles ne dépendent que de l'état du module.
    func testEarsOfTheCollapsedNotchShowTheCaffeine() {
        let f = QuickSettingsFixture(self)
        f.startAndShow()
        f.module.startCaffeine(until: f.now.addingTimeInterval(3600))
        let scene = scene(f, expanded: false)
        scene.registry.reconcile()
        XCTAssertEqual(scene.registry.moduleEars?.text, "1h00")
    }

    // MARK: - Rendus PNG

    func testRenderStates() throws {
        guard let outputDir else { throw XCTSkip("CLAUDE_NOTCH_SNAPSHOT_DIR non défini") }
        try render(scene(idleFixture()).root, name: "qs-idle", to: outputDir)
        try render(scene(busyFixture()).root, name: "qs-busy", to: outputDir)
        try render(scene(errorFixture()).root, name: "qs-error", to: outputDir)

        // Scène Autonomie appliquée : économie d'énergie, Bluetooth coupé, caféine arrêtée.
        let autonomy = idleFixture()
        autonomy.module.prefs.autonomyBluetoothOff = true
        autonomy.module.startCaffeine(until: autonomy.now.addingTimeInterval(3600))
        autonomy.module.applyScene(.autonomy)
        QuickSettingsFixture.settle()
        try render(scene(autonomy).root, name: "qs-scene-autonomy", to: outputDir)
        try render(scene(desktopFixture()).root, name: "qs-desktop", to: outputDir)
        try render(scene(busyFixture(), fullScreen: true).root, name: "qs-fullscreen", to: outputDir)
        try render(scene(desktopFixture(), fullScreen: true).root, name: "qs-fullscreen-desktop", to: outputDir)

        // Oreilles de la notch repliée : caféine seule.
        let ears = QuickSettingsFixture(self)
        ears.startAndShow()
        ears.module.startCaffeine(until: ears.now.addingTimeInterval(72 * 60))
        let collapsed = scene(ears, expanded: false)
        collapsed.registry.reconcile()
        try render(collapsed.root, name: "qs-collapsed-ears", to: outputDir)

        // Accent clair (ambre) : le texte sur la couleur d'accent reste lisible. Réglages partagés remis en état.
        let original = Preferences.shared.accentHex
        Preferences.shared.accentHex = "F5B83D"
        defer {
            Preferences.shared.accentHex = original
            UserDefaults.standard.removeObject(forKey: "appearance.accent")
        }
        try render(scene(busyFixture()).root, name: "qs-busy-amber", to: outputDir)
        Preferences.shared.accentHex = "4C8DFF"
        try render(scene(busyFixture()).root, name: "qs-busy-blue", to: outputDir)
        Preferences.shared.accentHex = original
    }

    func testRenderSettings() throws {
        guard let outputDir else { throw XCTSkip("CLAUDE_NOTCH_SNAPSHOT_DIR non défini") }
        let f = busyFixture()
        let harness = NotchHarness(self)
        let registry = ModuleRegistry(modules: [harness.claude, f.module], prefs: harness.prefs)
        let view = SettingsView(prefs: harness.prefs, registry: registry, updater: Updater(),
                                selection: .module("quicksettings"))
        try render(view, name: "qs-settings", to: outputDir, size: SettingsWindow.size, background: nil)
    }

    // MARK: - Outils

    private func measure(_ scene: Scene, settle: TimeInterval = 0.5) -> CGSize {
        let hosting = FirstMouseHostingView(rootView: scene.root)
        hosting.sizingOptions = []
        hosting.frame = CGRect(origin: .zero, size: NotchController.panelSize)
        let window = NSPanel(contentRect: hosting.frame, styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(settle))
        window.close()
        return scene.harness.model.contentSize
    }

    /// Fenêtre hors écran + rendu de l'arbre de calques (même méthode que SnapshotTests).
    private func render<V: View>(_ view: V, name: String, to dir: URL, size: CGSize = NotchController.panelSize,
                                 background: Color? = Color(white: 0.85)) throws {
        let hosting = NSHostingView(rootView: view.background(background ?? Color(nsColor: .windowBackgroundColor)))
        hosting.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        hosting.layoutSubtreeIfNeeded()

        let scale: CGFloat = 2
        guard let layer = hosting.layer,
              let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale),
                                            pixelsHigh: Int(size.height * scale), bitsPerSample: 8,
                                            samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            return XCTFail("rendu impossible")
        }
        let cg = context.cgContext
        cg.translateBy(x: 0, y: size.height * scale)
        cg.scaleBy(x: scale, y: -scale)
        layer.render(in: cg)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { return XCTFail("PNG") }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try png.write(to: dir.appendingPathComponent("\(name).png"))
        window.close()
    }
}
