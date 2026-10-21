import AppKit
import SwiftUI
import XCTest
@testable import ClaudeNotch

/// Rendus PNG de la notch détachée : poignée de l'angle, étapes de la goutte, bulle en barillet (4 à 10 onglets,
/// activités), panneau de la bulle, réglage. Fenêtres jamais affichées. Ne fait rien sans `CLAUDE_NOTCH_SNAPSHOT_DIR`.
final class BubbleSnapshotTests: XCTestCase {
    private static let wallpaper = Color(red: 0.36, green: 0.52, blue: 0.74)

    private static let symbols: [(String, String, String)] = [
        ("claude", "Claude", "sparkle"), ("media", "Lecteur", "play.circle"),
        ("quicksettings", "Réglages rapides", "switch.2"), ("shelf", "Étagère", "tray"),
        ("clipboard", "Presse-papiers", "doc.on.clipboard"), ("timer", "Minuteur", "timer"),
        ("notes", "Notes", "note.text"), ("codex", "Codex", "chevron.left.forwardslash.chevron.right"),
        ("messages", "Messages", "message"), ("mail", "Mail", "envelope"),
    ]

    private func tabs(_ count: Int) -> [RevolverBubble.Tab] {
        Self.symbols.prefix(count).map { RevolverBubble.Tab(id: $0.0, title: $0.1, symbol: $0.2) }
    }

    private static let claudeWorking = EarTab(id: "claude", kind: .claude(.working), priority: 100, text: "2",
                                              bars: false, isAlert: false)
    private static let timer = EarTab(id: "timer", kind: .module(ModuleEars(symbol: "timer", text: "24:59", priority: 5)),
                                      priority: 5, text: "24:59", bars: false, isAlert: false)

    func testRenderHandle() throws {
        guard let dir = TimerNotesSnapshot.outputDirectory else { throw XCTSkip("CLAUDE_NOTCH_SNAPSHOT_DIR non défini") }
        let notch = NotchHarness(self)
        notch.model.isExpanded = true
        notch.model.selectedTab = "timer"
        try TimerNotesSnapshot.render(notch.root, "bubble-handle", dir, background: Self.wallpaper)

        // Poignée agrandie : au repos, puis allumée (survol, appui).
        func corner(lit: Bool, pressed: Bool) -> some View {
            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color.black)
                DetachGrip(lit: lit, pressed: pressed).frame(width: DetachHandle.size, height: DetachHandle.size)
            }
            .frame(width: 70, height: 70)
            .scaleEffect(2.5)
            .frame(width: 180, height: 180)
        }
        let zoom = HStack(spacing: 30) {
            corner(lit: false, pressed: false)
            corner(lit: true, pressed: false)
            corner(lit: true, pressed: true)
        }
        .padding(20)
        try TimerNotesSnapshot.render(zoom, "bubble-handle-zoom", dir, size: CGSize(width: 640, height: 220),
                                      background: Self.wallpaper)
    }

    /// Étapes du décollage (la goutte s'étire, le col s'amincit, se rompt) puis du rattachement.
    func testRenderGooStages() throws {
        guard let dir = TimerNotesSnapshot.outputDirectory else { throw XCTSkip("CLAUDE_NOTCH_SNAPSHOT_DIR non défini") }
        let size = CGSize(width: 800, height: 560)
        let panel = CGRect(x: 130, y: -20, width: 540, height: 340)
        let notch = CGRect(x: 307.5, y: -20, width: 185, height: 52)
        let handle = CGPoint(x: 650, y: 300)
        let direction = CGPoint(x: 0.45, y: 0.89)
        func drop(_ distance: CGFloat) -> CGPoint {
            CGPoint(x: handle.x + direction.x * distance, y: handle.y + direction.y * distance)
        }
        let start = Date()
        var stages: [(String, GooShapes)] = []
        for (name, distance) in [("1", 15.0), ("2", 55.0), ("3", 95.0), ("4", 117.0)] {
            let state = GooState(panel: panel, notch: notch, handle: handle, drop: drop(CGFloat(distance)))
            stages.append(("bubble-goo-\(name)-pull", state.shapes(at: start)))
        }
        var snap = GooState(panel: panel, notch: notch, handle: handle, drop: drop(120))
        snap.mode = .snap(start: start)
        stages.append(("bubble-goo-5-snap", snap.shapes(at: start.addingTimeInterval(Goo.snapDuration * 0.25))))
        var overlap = snap
        overlap.mode = .snap(start: start)
        stages.append(("bubble-goo-6-snap-overlap", overlap.shapes(at: start.addingTimeInterval(0.02))))
        for (name, shapes) in stages {
            let view = ZStack(alignment: .topLeading) {
                // Bande de la barre des menus, pour situer la notch.
                Color.black.opacity(0.25).frame(height: 32)
                GooCanvas(shapes: shapes, color: .black)
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            try TimerNotesSnapshot.render(view, name, dir, size: size, background: Self.wallpaper)
        }
    }

    /// Retour aimanté : approche (la bulle se tend et se hérisse, la notch pointe vers elle), contact, aspiration,
    /// rebond de la notch ; détente quand on la lâche dans le champ. Puis une notch teintée (dégradé du col).
    func testRenderFerroStages() throws {
        guard let dir = TimerNotesSnapshot.outputDirectory else { throw XCTSkip("CLAUDE_NOTCH_SNAPSHOT_DIR non défini") }
        let screenNotch = CGRect(x: 663.5, y: 950, width: 185, height: 32)
        let field = Ferro.fieldFrame(notch: screenNotch)
        let local = GooCoordinates(field)
        let notch = local.rect(screenNotch)
        let start = Date()
        func scene(_ state: FerroState, _ date: Date, fill: Color = .black) -> some View {
            let shapes = state.shapes(at: date)
            return ZStack(alignment: .topLeading) {
                Color.black.opacity(0.25).frame(height: 37)
                NotchShape(topRadius: 0, bottomRadius: 9).fill(Color.black)
                    .frame(width: notch.width, height: notch.height)
                    .position(x: notch.midX, y: notch.midY)
                FerroCanvas(shapes: shapes, notch: notch, notchColor: .black, fill: fill)
                if !shapes.outline.isEmpty {
                    RevolverBubble(tabs: tabs(6), turn: 0, activity: [], claudeEars: nil, fill: fill,
                                   nearNotch: state.strength > 0.5, outline: BubbleRootView.outline(shapes),
                                   contentScale: shapes.contentScale, contentOpacity: Double(shapes.contentOpacity),
                                   rimOpacity: Double(shapes.rimOpacity))
                        .position(shapes.center)
                }
            }
            .frame(width: field.width, height: field.height, alignment: .topLeading)
        }
        func approach(_ gap: CGFloat, dx: CGFloat = 40) -> FerroState {
            let wanted = CGPoint(x: screenNotch.midX + dx, y: screenNotch.minY - BubbleGeometry.radius - gap)
            let pulled = Ferro.attract(wanted, notch: screenNotch)
            return FerroState(notch: notch, center: local.point(pulled.center), strength: pulled.strength)
        }
        var stages: [(String, FerroState, Date)] = []
        for (name, gap) in [("1", 140.0), ("2", 95.0), ("3", 60.0), ("4", 34.0)] as [(String, CGFloat)] {
            stages.append(("bubble-ferro-\(name)-approach", approach(gap), start))
        }
        let captured = approach(30)
        for (name, t) in [("5", 0.2), ("6", 0.5), ("7", 0.8), ("8", 0.97), ("9", 1.08), ("10", 1.45)] {
            var state = captured
            state.mode = .aspirate(start: start, from: captured.center)
            stages.append(("bubble-ferro-\(name)-aspirate", state, start.addingTimeInterval(t * Ferro.aspirateDuration)))
        }
        var relax = approach(50)
        relax.mode = .relax(start: start, from: relax.strength)
        stages.append(("bubble-ferro-11-relax", relax, start.addingTimeInterval(0.24)))
        for (name, state, date) in stages {
            try TimerNotesSnapshot.render(scene(state, date), name, dir, size: field.size, background: Self.wallpaper)
        }
        let tinted = Color(red: 0.12, green: 0.16, blue: 0.32)
        var aspirating = captured
        aspirating.mode = .aspirate(start: start, from: captured.center)
        try TimerNotesSnapshot.render(scene(aspirating, start.addingTimeInterval(0.4 * Ferro.aspirateDuration),
                                            fill: tinted),
                                      "bubble-ferro-12-tinted", dir, size: field.size, background: Self.wallpaper)
    }

    /// Barillet de 4 à 10 onglets ; activités (anneau, pastille, points sur les chambres) ; aimantée par la notch.
    func testRenderRevolver() throws {
        guard let dir = TimerNotesSnapshot.outputDirectory else { throw XCTSkip("CLAUDE_NOTCH_SNAPSHOT_DIR non défini") }
        let side = BubbleController.bubbleWindowSize.width
        func bubble(_ count: Int, turn: Int = 0, activity: [EarTab] = [], near: Bool = false) -> some View {
            RevolverBubble(tabs: tabs(count), turn: turn, activity: activity, claudeEars: nil, fill: .black,
                           nearNotch: near)
                .frame(width: side, height: side)
        }
        let gallery = VStack(spacing: 10) {
            HStack(spacing: 10) {
                bubble(4)
                bubble(6, activity: [Self.timer])
                bubble(8, turn: 5, activity: [Self.claudeWorking, Self.timer])
                bubble(10, turn: 2, activity: [Self.claudeWorking])
            }
            HStack(spacing: 10) {
                bubble(5, turn: -1)
                bubble(7, turn: 3, activity: [Self.timer])
                bubble(9, turn: 8)
                bubble(6, turn: 1, near: true)
            }
        }
        .padding(10)
        try TimerNotesSnapshot.render(gallery, "bubble-revolver", dir,
                                      size: CGSize(width: 4 * side + 50, height: 2 * side + 30),
                                      background: Self.wallpaper)
        for count in [4, 6, 8, 10] {
            try TimerNotesSnapshot.render(bubble(count, activity: count == 8 ? [Self.claudeWorking, Self.timer] : []),
                                          "bubble-revolver-\(count)", dir, size: CGSize(width: side, height: side),
                                          background: Self.wallpaper)
        }
    }

    /// La bulle ouverte en panneau (onglet Minuteur), puis la vraie racine de la fenêtre en bulle.
    func testRenderBubbleWindow() throws {
        guard let dir = TimerNotesSnapshot.outputDirectory else { throw XCTSkip("CLAUDE_NOTCH_SNAPSHOT_DIR non défini") }
        let notch = NotchHarness(self, store: .working(2))
        let bubble = BubbleModel()
        notch.model.selectedTab = "timer"
        notch.model.bubble = .bubblePanel
        var actions = NotchActions()
        actions.reattach = {}
        actions.backToRevolver = {}
        func root() -> BubbleRootView {
            BubbleRootView(model: notch.model, bubble: bubble, store: notch.store, registry: notch.registry,
                           prefs: notch.prefs, actions: actions, input: BubbleInput())
        }
        let margin = BubbleGeometry.panelMargin
        let panelSize = CGSize(width: notch.prefs.expandedWidth(compact: false) + 2 * margin, height: 360)
        bubble.layout(center: CGPoint(x: panelSize.width / 2, y: margin + BubbleGeometry.radius), window: panelSize)
        try TimerNotesSnapshot.render(root(), "bubble-panel", dir, size: panelSize, background: Self.wallpaper)

        notch.model.bubble = .bubble
        let side = BubbleController.bubbleWindowSize
        bubble.layout(center: CGPoint(x: side.width / 2, y: side.height / 2), window: side)
        bubble.turn = 0
        notch.model.selectedTab = notch.registry.enabled.first?.id ?? "claude"
        try TimerNotesSnapshot.render(root(), "bubble-window", dir, size: side, background: Self.wallpaper)
    }

    /// Réglages › Général, défilé jusqu'en bas : la section « Bulle ».
    func testRenderSettings() throws {
        guard let dir = TimerNotesSnapshot.outputDirectory else { throw XCTSkip("CLAUDE_NOTCH_SNAPSHOT_DIR non défini") }
        let notch = NotchHarness(self)
        let view = SettingsView(prefs: notch.prefs, registry: notch.registry, updater: Updater(), selection: .general)
        try EarTabsSnapshotTests.renderScrolledToBottom(view, "bubble-settings-general", dir)
    }
}
