import AppKit
import SwiftUI
import XCTest
@testable import ClaudeNotch

/// La notch repliée et ses intercalaires face à l'encoche physique : la partie centrale couvre exactement l'encoche
/// (largeur, hauteur), les intercalaires la prolongent sans marche ni jour, et rien ne dépasse du côté sans intercalaire.
/// Logique pure d'abord, puis la silhouette réellement dessinée, mesurée pixel par pixel dans un rendu hors écran.
final class EarTabsGeometryTests: XCTestCase {
    /// Encoches testées. `measured` : celle de ce Mac (MacBook Pro 14", 1512 − 2 × 663,5 = 185 × 32, relevée avec
    /// `NSScreen.auxiliaryTopLeftArea` / `auxiliaryTopRightArea` et `/state`). La virtuelle : 200 pt, hauteur de la barre des menus.
    private static let measured = CGSize(width: 185, height: 32)
    private static let notches: [(size: CGSize, hasNotch: Bool)] = [
        (measured, true),
        (CGSize(width: 178, height: 38), true),
        (CGSize(width: 186.5, height: 33), true),
        (CGSize(width: 200, height: 24), false),
    ]

    // MARK: - Logique pure

    private func tabs(_ count: Int) -> [EarTab] {
        EarTabs.tabs(claude: .none, claudeEars: nil, modules: (0..<count).map {
            ModuleEarsEntry(id: "m\($0)", ears: ModuleEars(symbol: "circle", text: "\($0)", priority: 100 - $0))
        }, showEars: true)
    }

    /// Le premier intercalaire de chaque côté a exactement la hauteur de la notch (aucune marche entre elles), puis
    /// l'escalier descend vers l'extérieur sans passer sous la hauteur de l'icône.
    func testFirstTabHasTheNotchHeightThenStepsDown() {
        for (size, _) in Self.notches {
            for mode in [EarTabsMode.visible, .retracted] {
                let layout = EarTabsLayout(tabs: tabs(6), notch: size, mode: mode)
                for side in [layout.left, layout.right] {
                    XCTAssertEqual(side[0].height, size.height, "\(size) \(mode) : rang 0 de la hauteur de la notch")
                    XCTAssertEqual(side[0].frame.maxY, size.height, accuracy: 0.001)
                    for (near, far) in zip(side, side.dropFirst()) {
                        XCTAssertLessThan(far.height, near.height, "\(size) rang \(far.rank)")
                    }
                    XCTAssertGreaterThanOrEqual(side.last!.height, 16, "assez haut pour l'icône")
                }
            }
        }
    }

    // MARK: - Silhouette dessinée

    private static let band = CGSize(width: 800, height: 70)
    private static let scale: CGFloat = 4
    private static let wallpaper = Color(red: 0.36, green: 0.52, blue: 0.74)

    /// Ce que la notch dessine : un point (origine au centre haut de l'encoche, x vers la droite, y vers le bas, en points)
    /// est « couvert » quand son pixel n'a pas la couleur du fond.
    private struct Silhouette {
        let bitmap: NSBitmapImageRep
        let background: NSColor

        func covered(_ x: CGFloat, _ y: CGFloat) -> Bool {
            let px = Int(((EarTabsGeometryTests.band.width / 2 + x) * EarTabsGeometryTests.scale).rounded(.down))
            let py = Int((y * EarTabsGeometryTests.scale).rounded(.down))
            guard px >= 0, py >= 0, px < bitmap.pixelsWide, py < bitmap.pixelsHigh,
                  let color = bitmap.colorAt(x: px, y: py)?.usingColorSpace(.deviceRGB) else { return false }
            func differs(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) > 0.04 }
            return differs(color.redComponent, background.redComponent) || differs(color.greenComponent, background.greenComponent)
                || differs(color.blueComponent, background.blueComponent)
        }

        /// Bord de ce qui touche le centre sur la ligne `y`, vers la gauche (−1) ou la droite (+1), au pas d'un pixel.
        func extent(row y: CGFloat, toward sign: CGFloat) -> CGFloat? {
            let step = 1 / EarTabsGeometryTests.scale
            guard covered(0, y) else { return nil }
            var x: CGFloat = 0
            while abs(x) < 399, covered(x + sign * step, y) { x += sign * step }
            return x + sign * step
        }
    }

    private func render(_ root: some View, background: Color = Color(red: 1, green: 0, blue: 1)) throws -> NSBitmapImageRep {
        let size = Self.band
        let hosting = NSHostingView(rootView: root.background(background))
        hosting.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        hosting.layoutSubtreeIfNeeded()
        let scale = Self.scale
        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0))
        let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap)).cgContext
        context.translateBy(x: 0, y: size.height * scale)
        context.scaleBy(x: scale, y: -scale)
        try XCTUnwrap(hosting.layer).render(in: context)
        window.close()
        return bitmap
    }

    private func silhouette(_ scene: Scene) throws -> Silhouette {
        Silhouette(bitmap: try render(scene.root), background: NSColor(red: 1, green: 0, blue: 1, alpha: 1))
    }

    private struct Scene {
        let harness: NotchHarness
        let registry: ModuleRegistry
        var root: NotchRootView {
            NotchRootView(model: harness.model, store: harness.store, registry: registry, prefs: harness.prefs,
                          actions: NotchActions())
        }
    }

    private enum Tabs { case claudeOnly, claudeAndTimer }

    private func scene(_ tabs: Tabs, notch: CGSize, hasNotch: Bool, mode: EarTabsMode = .visible,
                       hovered: String? = nil) -> Scene {
        let harness = NotchHarness(self, store: .working(2))
        harness.prefs.earTabsMode = mode
        harness.model.notchSize = notch
        harness.model.hasNotch = hasNotch
        harness.model.hoveredTab = hovered
        let timer = FakeModule(id: "timer", ears: ModuleEars(symbol: "timer", text: "4:59", priority: 5), keepsRunning: true)
        let registry = ModuleRegistry(modules: [harness.claude] + (tabs == .claudeAndTimer ? [timer] : []),
                                      prefs: harness.prefs)
        registry.reconcile()
        return Scene(harness: harness, registry: registry)
    }

    /// Toute l'encoche est couverte, au pixel près (coins bas compris : pas de jour entre la notch et un intercalaire), et
    /// la forme continue au-delà de chaque bord sur toute la hauteur de l'encoche : pas de marche.
    func testNotchIsCoveredAndTabsContinueItWithoutStep() throws {
        for (size, hasNotch) in Self.notches {
            // « timer » déployé n'a pas de contenu (carte basse), « claude » liste ses sessions (carte haute).
            for (mode, hovered) in [(EarTabsMode.visible, String?.none), (.retracted, nil), (.visible, "timer"),
                                    (.visible, "claude")] {
                let sil = try silhouette(scene(.claudeAndTimer, notch: size, hasNotch: hasNotch, mode: mode, hovered: hovered))
                let label = "\(size) \(mode) survol : \(hovered ?? "aucun")"
                var uncovered: [String] = []
                for y in stride(from: CGFloat(0.3), through: size.height - 0.3, by: 0.5) {
                    for x in stride(from: -size.width / 2 + 0.3, through: size.width / 2 - 0.3, by: 0.5) where !sil.covered(x, y) {
                        uncovered.append("(\(x), \(y))")
                    }
                    for x in [-size.width / 2 - 0.5, size.width / 2 + 0.5] where !sil.covered(x, y) {
                        uncovered.append("marche (\(x), \(y))")
                    }
                }
                XCTAssertTrue(uncovered.isEmpty, "\(label) : points de l'encoche ou de son prolongement non dessinés : "
                              + uncovered.prefix(6).joined(separator: " "))
            }
        }
    }

    /// Côté sans intercalaire, sur une vraie encoche : le noir s'arrête au bord de l'encoche (pas d'évasement qui la
    /// déborde), sur toute la hauteur au-dessus de l'arrondi du bas.
    func testNothingSticksOutOfTheNotchOnTheSideWithoutTab() throws {
        for (size, hasNotch) in Self.notches where hasNotch {
            let sil = try silhouette(scene(.claudeOnly, notch: size, hasNotch: true))
            // SwiftUI aligne le cadre sur les pixels de la fenêtre : sur un écran 1× (CI), une encoche de largeur impaire
            // centrée glisse d'un demi-point (93 au lieu de 92,5). Ce décalage est borné par un demi-pixel de l'écran.
            let shift = try XCTUnwrap(sil.extent(row: 0.25, toward: 1)) - size.width / 2
            let backing = NSScreen.main?.backingScaleFactor ?? 1
            XCTAssertLessThanOrEqual(abs(shift), 0.5 / backing + 0.01, "\(size) : bord droit décalé de \(shift)")
            var outside: [String] = []
            for y in stride(from: CGFloat(0.25), through: 40, by: 0.5) {
                for x in stride(from: size.width / 2 + shift + 0.4, through: size.width / 2 + 10, by: 0.5) where sil.covered(x, y) {
                    outside.append("(\(x), \(y))")
                }
            }
            XCTAssertTrue(outside.isEmpty, "\(size) : du noir hors de l'encoche, côté libre : " + outside.prefix(6).joined(separator: " "))
            for y in stride(from: CGFloat(0.25), through: size.height - 10, by: 1) {
                XCTAssertEqual(sil.extent(row: y, toward: 1) ?? 0, size.width / 2 + shift, accuracy: 0.3, "\(size) ligne \(y)")
            }
        }
    }

    /// La taille mesurée de la forme repliée est celle de l'encoche (elle était de 12 pt plus large avec les évasements).
    func testCollapsedShapeMeasuresTheNotch() throws {
        let scene = scene(.claudeAndTimer, notch: Self.measured, hasNotch: true)
        _ = try silhouette(scene)
        XCTAssertEqual(scene.harness.model.contentSize, Self.measured)
    }

    // MARK: - Rendus PNG (CLAUDE_NOTCH_SNAPSHOT_DIR)

    /// Rendus sur fond de bureau, avec l'encoche physique en contour (cyan) : `geometry-<état>.png`, 300 × 40 pt à 4×.
    func testRenderGeometryOverlay() throws {
        guard let dir = TimerNotesSnapshot.outputDirectory else { throw XCTSkip("CLAUDE_NOTCH_SNAPSHOT_DIR non défini") }
        let cases: [(String, Scene)] = [
            ("deux-intercalaires", scene(.claudeAndTimer, notch: Self.measured, hasNotch: true)),
            ("un-intercalaire", scene(.claudeOnly, notch: Self.measured, hasNotch: true)),
            ("retractes", scene(.claudeAndTimer, notch: Self.measured, hasNotch: true, mode: .retracted)),
            ("deploye", scene(.claudeAndTimer, notch: Self.measured, hasNotch: true, hovered: "claude")),
            ("encoche-virtuelle", scene(.claudeAndTimer, notch: CGSize(width: 200, height: 24), hasNotch: false)),
            ("encoche-haute", scene(.claudeAndTimer, notch: CGSize(width: 178, height: 38), hasNotch: true)),
        ]
        for (name, scene) in cases {
            let bitmap = try render(scene.root, background: Self.wallpaper)
            let size = scene.harness.model.notchSize
            let s = Self.scale
            let crop = CGRect(x: (Self.band.width / 2 - 150) * s, y: 0, width: 300 * s, height: 40 * s)
            let out = try XCTUnwrap(NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: Int(crop.width), pixelsHigh: Int(crop.height), bitsPerSample: 8,
                samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
            NSGraphicsContext.saveGraphicsState()
            defer { NSGraphicsContext.restoreGraphicsState() }
            let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: out))
            NSGraphicsContext.current = context
            context.cgContext.draw(try XCTUnwrap(bitmap.cgImage).cropping(to: crop)!, in: CGRect(origin: .zero, size: crop.size))
            // Encoche physique : contour de 1 px autour de [−l/2, l/2] × [0, h] (origine en bas à gauche dans ce contexte).
            context.cgContext.setStrokeColor(NSColor.cyan.cgColor)
            context.cgContext.setLineWidth(1)
            context.cgContext.stroke(CGRect(x: (150 - size.width / 2) * s, y: crop.height - size.height * s,
                                            width: size.width * s, height: size.height * s - 0.5))
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try XCTUnwrap(out.representation(using: .png, properties: [:])).write(to: dir.appendingPathComponent("geometry-\(name).png"))
        }
    }
}
