import AppKit
import SwiftUI
import XCTest
@testable import ClaudeNotch

/// Minuterie à la main pour `EarsTimer` : rien n'attend 4 s réelles, un test déclenche chaque tic.
final class FakeEarsTimer {
    final class Timer {
        let interval: TimeInterval
        let tolerance: TimeInterval
        let tick: () -> Void
        var cancelled = false
        init(interval: TimeInterval, tolerance: TimeInterval, tick: @escaping () -> Void) {
            self.interval = interval
            self.tolerance = tolerance
            self.tick = tick
        }
    }

    private(set) var created: [Timer] = []
    /// Timers créés et pas annulés.
    var active: [Timer] { created.filter { !$0.cancelled } }

    var timer: EarsTimer {
        EarsTimer { [self] interval, tolerance, tick in
            let timer = Timer(interval: interval, tolerance: tolerance, tick: tick)
            created.append(timer)
            return { timer.cancelled = true }
        }
    }

    func fire() { active.forEach { $0.tick() } }
}

/// Oreilles qui alternent : Claude, puis chaque onglet qui a des oreilles (voir `EarsRotation`).
final class EarsRotationTests: XCTestCase {
    private let media = ModuleEarsEntry(id: "media", ears: ModuleEars(symbol: "music.note", text: "", priority: 1, bars: true))
    private let coffee = ModuleEarsEntry(id: "quicksettings",
                                         ears: ModuleEars(symbol: "cup.and.saucer.fill", text: "1h00", priority: -10))
    private let timer = ModuleEarsEntry(id: "timer", ears: ModuleEars(symbol: "timer", text: "4:59", priority: 5))

    private func settle(_ seconds: TimeInterval = 0.3) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    private func ids(_ claude: NotchIndicator, _ modules: [ModuleEarsEntry], showEars: Bool = true,
                     alternate: Bool) -> [String] {
        EarsRotation.slots(claude: claude, modules: modules, showEars: showEars, alternate: alternate).map { $0.id }
    }

    // MARK: - Choix des contenus

    /// Claude (attend / travaille / vient de finir / rien) × 0, 1, 2 modules × réglage activé / désactivé.
    func testTruthTable() {
        // Les entrées sont dans l'ordre des onglets : lecteur avant minuteur.
        let rows: [(claude: NotchIndicator, modules: [ModuleEarsEntry], on: [String], off: [String])] = [
            (.attention, [], ["claude"], ["claude"]),
            (.attention, [media], ["claude"], ["claude"]),
            (.attention, [media, timer], ["claude"], ["claude"]),
            (.working, [], ["claude"], ["claude"]),
            (.working, [media], ["claude", "media"], ["claude"]),
            (.working, [media, timer], ["claude", "timer", "media"], ["claude"]),
            (.done, [], ["claude"], ["claude"]),
            (.done, [media], ["claude", "media"], ["claude"]),
            (.done, [media, timer], ["claude", "timer", "media"], ["claude"]),
            (.none, [], [], []),
            (.none, [media], ["media"], ["media"]),
            (.none, [media, timer], ["timer"], ["timer"]),
        ]
        for row in rows {
            XCTAssertEqual(ids(row.claude, row.modules, alternate: true), row.on, "\(row.claude) \(row.modules.map { $0.id }) on")
            XCTAssertEqual(ids(row.claude, row.modules, alternate: false), row.off, "\(row.claude) \(row.modules.map { $0.id }) off")
            for alternate in [true, false] {
                XCTAssertEqual(ids(row.claude, row.modules, showEars: false, alternate: alternate), [],
                               "oreilles désactivées : rien")
            }
        }
    }

    /// Claude + deux onglets au plus, à priorité égale l'ordre des onglets.
    func testAtMostThreeContentsAndTiesFollowTabOrder() {
        XCTAssertEqual(ids(.working, [media, coffee, timer], alternate: true), ["claude", "timer", "media"])
        XCTAssertEqual(ids(.none, [media, coffee, timer], alternate: true), ["timer"])
        let a = ModuleEarsEntry(id: "a", ears: ModuleEars(symbol: "a", text: "1"))
        let b = ModuleEarsEntry(id: "b", ears: ModuleEars(symbol: "b", text: "2"))
        XCTAssertEqual(ids(.working, [a, b], alternate: true), ["claude", "a", "b"])
        XCTAssertEqual(ids(.none, [a, b], alternate: true), ["a"])
        XCTAssertEqual(EarsRotation.maxSlots, 3)
    }

    func testSlotsCarryTheirContent() {
        let slots = EarsRotation.slots(claude: .done, modules: [timer], showEars: true, alternate: true)
        XCTAssertEqual(slots, [.claude(.done), .module(id: "timer", ears: timer.ears)])
    }

    /// Le registre fournit les oreilles des modules qui tournent, et applique l'onglet Claude et le réglage.
    func testRegistrySlots() {
        let prefs = Preferences(defaults: makeEphemeralDefaults(self))
        let player = FakeModule(id: "media", ears: media.ears, keepsRunning: true)
        let minuteur = FakeModule(id: "timer", ears: timer.ears, keepsRunning: true)
        let sleeping = FakeModule(id: "notes", ears: ModuleEars(symbol: "note", text: "!", priority: 9))
        let registry = ModuleRegistry(modules: [FakeModule(id: "claude"), player, minuteur, sleeping], prefs: prefs)
        registry.reconcile()
        XCTAssertEqual(registry.earsEntries.map { $0.id }, ["media", "timer"], "seuls les modules qui tournent")
        XCTAssertEqual(registry.moduleEars, timer.ears)

        XCTAssertEqual(registry.earsSlots(claude: .working).map { $0.id }, ["claude", "timer", "media"])
        XCTAssertEqual(registry.earsSlots(claude: .attention).map { $0.id }, ["claude"])
        XCTAssertEqual(registry.earsSlots(claude: .none).map { $0.id }, ["timer"])

        prefs.alternateEars = false
        XCTAssertEqual(registry.earsSlots(claude: .working).map { $0.id }, ["claude"], "règle d'avant l'alternance")
        prefs.alternateEars = true

        registry.setEnabled("claude", false)
        XCTAssertEqual(registry.earsSlots(claude: .working).map { $0.id }, ["timer"], "sans onglet Claude : le module seul")

        prefs.showEars = false
        XCTAssertEqual(registry.earsSlots(claude: .working), [])
    }

    func testAlternateEarsPreference() {
        let defaults = makeEphemeralDefaults(self)
        let prefs = Preferences(defaults: defaults)
        XCTAssertTrue(prefs.alternateEars, "activé par défaut")
        prefs.alternateEars = false
        XCTAssertEqual(defaults.object(forKey: "appearance.alternateEars") as? Bool, false)
        XCTAssertFalse(Preferences(defaults: defaults).alternateEars)
    }

    // MARK: - Largeur

    func testSideWidthIsTheLargestInPlayAndConstant() {
        XCTAssertEqual(EarsRotation.sideWidth([]), 0)
        let slots = EarsRotation.slots(claude: .working, modules: [media, timer], showEars: true, alternate: true)
        XCTAssertEqual(EarsRotation.sideWidth(slots), NotchController.earWidth)
        for slot in slots {
            XCTAssertEqual(EarsRotation.sideWidth([slot]), EarsRotation.sideWidth(slots), "\(slot.id) : même largeur")
        }
    }

    /// La forme mesurée par la vue ne bouge pas d'un intercalaire à l'autre (survol et forme stables).
    func testShapeWidthStaysTheSameWhileRotating() {
        let fake = FakeEarsTimer()
        let notch = NotchHarness(self, store: .working(1))
        notch.model.earsTimer = fake.timer
        let long = FakeModule(id: "fake", ears: ModuleEars(symbol: "timer", text: "Terminé", priority: 5), keepsRunning: true)
        let registry = ModuleRegistry(modules: [notch.claude, long], prefs: notch.prefs)
        let root = NotchRootView(model: notch.model, store: notch.store, registry: registry, prefs: notch.prefs,
                                 actions: NotchActions())
        let window = host(root)
        defer { window.close() }

        settle(0.6)
        let expected: CGFloat = 185 + 2 * NotchController.earWidth + 12
        XCTAssertEqual(fake.active.count, 1)
        XCTAssertEqual(notch.model.contentSize.width, expected, accuracy: 1, "phase Claude")
        for step in 1...3 {
            fake.fire()
            settle(0.6)
            XCTAssertEqual(notch.model.earsStep, step)
            XCTAssertEqual(notch.model.contentSize.width, expected, accuracy: 1, "intercalaire \(step)")
            XCTAssertEqual(notch.model.contentSize.height, 32, accuracy: 1)
        }
    }

    // MARK: - Timer

    func testShouldRotateRule() {
        let one = EarsRotation.slots(claude: .working, modules: [], showEars: true, alternate: true)
        let two = EarsRotation.slots(claude: .working, modules: [media], showEars: true, alternate: true)
        let three = EarsRotation.slots(claude: .working, modules: [media, timer], showEars: true, alternate: true)
        XCTAssertFalse(EarsRotation.shouldRotate(slots: [], expanded: false, shown: true))
        XCTAssertFalse(EarsRotation.shouldRotate(slots: one, expanded: false, shown: true), "un seul contenu")
        XCTAssertTrue(EarsRotation.shouldRotate(slots: two, expanded: false, shown: true))
        XCTAssertTrue(EarsRotation.shouldRotate(slots: three, expanded: false, shown: true))
        XCTAssertFalse(EarsRotation.shouldRotate(slots: two, expanded: true, shown: true), "panneau ouvert")
        XCTAssertFalse(EarsRotation.shouldRotate(slots: two, expanded: false, shown: false), "notch masquée")
    }

    /// Un seul timer de 4 s (tolérance 1 s), annulé à l'arrêt ; chaque tic avance d'un intercalaire.
    func testSingleTimerStartsAndStops() {
        let fake = FakeEarsTimer()
        let model = NotchViewModel()
        model.earsTimer = fake.timer
        XCTAssertFalse(model.isRotatingEars)
        XCTAssertTrue(fake.created.isEmpty, "rien tant qu'on ne demande pas")

        model.setEarsRotation(true)
        model.setEarsRotation(true)
        XCTAssertEqual(fake.created.count, 1, "jamais deux timers")
        XCTAssertEqual(fake.created[0].interval, 4)
        XCTAssertEqual(fake.created[0].tolerance, 1)
        XCTAssertTrue(model.isRotatingEars)

        fake.fire()
        fake.fire()
        XCTAssertEqual(model.earsStep, 2)

        model.setEarsRotation(false)
        model.setEarsRotation(false)
        XCTAssertTrue(fake.active.isEmpty)
        XCTAssertFalse(model.isRotatingEars)
        XCTAssertEqual(model.earsStep, 0, "repart de Claude")

        model.setEarsRotation(true)
        XCTAssertEqual(fake.created.count, 2)
        XCTAssertEqual(fake.active.count, 1)
    }

    func testSystemTimerUsesToleranceAndCancels() {
        var fired = 0
        let cancel = EarsTimer.system.every(0.05, 0.01) { fired += 1 }
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        cancel()
        let count = fired
        XCTAssertGreaterThan(count, 0)
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        XCTAssertEqual(fired, count, "annulé : plus aucun tic")
    }

    /// Chaîne complète dans la vraie vue : le timer existe seulement notch repliée avec au moins 2 contenus.
    func testViewCreatesAndStopsTheTimerAtTheRightMoments() {
        let fake = FakeEarsTimer()
        let notch = NotchHarness(self, store: .working(1))
        notch.model.earsTimer = fake.timer
        let player = FakeModule(id: "fake", ears: ModuleEars(symbol: "music.note", text: "", priority: 1, bars: true),
                                keepsRunning: true)
        let registry = ModuleRegistry(modules: [notch.claude, player], prefs: notch.prefs)
        let root = NotchRootView(model: notch.model, store: notch.store, registry: registry, prefs: notch.prefs,
                                 actions: NotchActions())
        let window = host(root)
        defer { window.close() }

        func expect(_ active: Int, _ created: Int, _ message: String, line: UInt = #line) {
            settle()
            XCTAssertEqual(fake.active.count, active, "\(message) : timers actifs", line: line)
            XCTAssertEqual(fake.created.count, created, "\(message) : timers créés", line: line)
        }
        expect(1, 1, "replié, Claude au travail + lecture")

        notch.model.isExpanded = true
        expect(0, 1, "panneau ouvert")
        notch.model.isExpanded = false
        expect(1, 2, "replié de nouveau")

        notch.prefs.alternateEars = false
        expect(0, 2, "réglage désactivé : Claude seul")
        notch.prefs.alternateEars = true
        expect(1, 3, "réglage réactivé")

        player.ears = nil
        expect(0, 3, "plus qu'un contenu")
        player.ears = ModuleEars(symbol: "music.note", text: "", priority: 1, bars: true)
        expect(1, 4, "la lecture reprend")

        notch.model.isShown = false
        expect(0, 4, "notch masquée")
        notch.model.isShown = true
        expect(1, 5, "notch de retour")

        notch.prefs.showEars = false
        expect(0, 5, "oreilles masquées")
        notch.prefs.showEars = true
        expect(1, 6, "oreilles de retour")

        // Claude attend l'utilisateur : alerte, seul, pas d'alternance.
        notch.store.send("PermissionRequest", "s0", ["tool_name": "Bash", "tool_input": ["command": "npm test"]])
        XCTAssertEqual(notch.store.indicator, .attention)
        expect(0, 6, "Claude attend")
        XCTAssertEqual(registry.earsSlots(claude: notch.store.indicator).map { $0.id }, ["claude"])
    }

    /// Sans Claude actif : le module seul, pas d'alternance, pas de timer.
    func testNoTimerWithoutClaudeActivity() {
        let fake = FakeEarsTimer()
        let notch = NotchHarness(self)
        notch.model.earsTimer = fake.timer
        let player = FakeModule(id: "fake", ears: ModuleEars(symbol: "music.note", text: "", priority: 1, bars: true),
                                keepsRunning: true)
        let registry = ModuleRegistry(modules: [notch.claude, player], prefs: notch.prefs)
        let root = NotchRootView(model: notch.model, store: notch.store, registry: registry, prefs: notch.prefs,
                                 actions: NotchActions())
        let window = host(root)
        defer { window.close() }
        settle()
        XCTAssertEqual(registry.earsSlots(claude: notch.store.indicator).map { $0.id }, ["fake"])
        XCTAssertTrue(fake.created.isEmpty)
    }

    // MARK: - Diagnostic

    func testStateListsTheSlotsByIdentifier() throws {
        _ = NSApplication.shared
        let prefs = Preferences(defaults: makeEphemeralDefaults(self))
        let controller = NotchController(store: .working(1), monitor: ClaudeMonitor(), prefs: prefs,
                                         tools: ToolsFeed(paths: LayoutTests.absentPaths))
        let info = controller.debugInfo
        XCTAssertEqual(info["earsSlots"] as? [String], ["claude"])
        XCTAssertEqual(info["earsRotating"] as? Bool, false)
    }

    // MARK: - Aide

    /// La vue dans un panneau hors écran ; l'appelant le ferme.
    private func host(_ root: NotchRootView) -> NSPanel {
        let hosting = FirstMouseHostingView(rootView: root)
        hosting.sizingOptions = []
        hosting.frame = CGRect(origin: .zero, size: NotchController.panelSize)
        let window = NSPanel(contentRect: hosting.frame, styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.orderFrontRegardless()
        return window
    }
}

/// Rendus PNG de la notch repliée qui alterne : phase Claude, phase lecture (pochette et égaliseur), minuteur.
/// Ne fait rien sans `CLAUDE_NOTCH_SNAPSHOT_DIR`.
final class EarsRotationSnapshotTests: XCTestCase {
    private func wait(until condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(3)
        while !condition(), Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
    }

    func testRenderRotation() throws {
        guard let dir = TimerNotesSnapshot.outputDirectory else { throw XCTSkip("CLAUDE_NOTCH_SNAPSHOT_DIR non défini") }
        let fake = try FakeAdapter(self, lines: [StreamLines.full(title: "Lumières de la ville", artist: "Les Fictifs",
                                                                  artwork: StreamLines.artwork())])
        let media = MediaModule(defaults: makeEphemeralDefaults(self), adapter: fake.adapter,
                                calendar: FakeCalendar(.notDetermined))
        let timers = FakeEarsTimer()
        let pair = TimerNotesSnapshot.scene(self, replacing: media, expanded: false, store: .working(2))
        pair.0.model.earsTimer = timers.timer
        wait { pair.1.moduleEars?.image != nil }
        XCTAssertNotNil(pair.1.moduleEars?.image)
        addTeardownBlock { media.stop() }

        let size = CGSize(width: 360, height: 60)
        try TimerNotesSnapshot.render(TimerNotesSnapshot.root(pair), "ears-rotation-1-claude", dir, size: size)
        XCTAssertEqual(timers.active.count, 1)
        timers.fire()
        try TimerNotesSnapshot.render(TimerNotesSnapshot.root(pair), "ears-rotation-2-lecture", dir, size: size)

        // Sans Claude actif : la lecture seule, comme avant l'alternance.
        let idle = TimerNotesSnapshot.scene(self, replacing: media, expanded: false, store: SessionStore())
        try TimerNotesSnapshot.render(TimerNotesSnapshot.root(idle), "ears-rotation-0-lecture-seule", dir, size: size)
    }
}
