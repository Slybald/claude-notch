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

    /// Tous les intercalaires, à tout rang, ont exactement la hauteur de la notch : même haut, même bas, aucune marche
    /// ni décalage vertical entre eux (la superposition de l'éventail est seulement horizontale).
    func testEveryTabHasTheNotchHeight() {
        for (size, _) in Self.notches {
            for mode in [EarTabsMode.visible, .retracted] {
                let layout = EarTabsLayout(tabs: tabs(6), notch: size, mode: mode)
                for item in layout.items {
                    XCTAssertEqual(item.height, size.height, "\(size) \(mode) rang \(item.rank)")
                    XCTAssertEqual(item.frame.minY, 0)
                    XCTAssertEqual(item.frame.maxY, size.height, accuracy: 0.001)
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
        func extent(row y: CGFloat, toward sign: CGFloat, from start: CGFloat = 0) -> CGFloat? {
            let step = 1 / EarTabsGeometryTests.scale
            guard covered(start, y) else { return nil }
            var x: CGFloat = start
            while abs(x) < 399, covered(x + sign * step, y) { x += sign * step }
            return x + sign * step
        }
    }

    private func render(_ root: some View, background: Color = Color(red: 1, green: 0, blue: 1), size: CGSize = band,
                        scale: CGFloat = scale) throws -> NSBitmapImageRep {
        let hosting = NSHostingView(rootView: root.background(background))
        hosting.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        hosting.layoutSubtreeIfNeeded()
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

    private enum Tabs { case claudeOnly, claudeAndTimer, six }

    private func scene(_ tabs: Tabs, notch: CGSize, hasNotch: Bool, mode: EarTabsMode = .visible,
                       hovered: String? = nil) -> Scene {
        let harness = NotchHarness(self, store: .working(2))
        harness.prefs.earTabsMode = mode
        harness.model.notchSize = notch
        harness.model.hasNotch = hasNotch
        harness.model.hoveredTab = hovered
        let timer = FakeModule(id: "timer", ears: ModuleEars(symbol: "timer", text: "4:59", priority: 5), keepsRunning: true)
        let others = [("media", "music.note", "", 1), ("messages", "message.fill", "3", 0), ("mail", "envelope.fill", "12", -1),
                      ("quicksettings", "cup.and.saucer.fill", "1h00", -10)].map { id, symbol, text, priority in
            FakeModule(id: id, ears: ModuleEars(symbol: symbol, text: text, priority: priority, bars: id == "media"),
                       keepsRunning: true)
        }
        let modules: [FakeModule] = tabs == .claudeOnly ? [] : tabs == .claudeAndTimer ? [timer] : [timer] + others
        let registry = ModuleRegistry(modules: [harness.claude] + modules, prefs: harness.prefs)
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

    /// Éventail au repos (six intercalaires) : la base est continue de la tranche la plus à gauche à la plus à droite, au
    /// même niveau que le bas de la notch, et rien ne dépasse dessous (ni ombre, ni marche) ni au-dessus ; ouverts ou non,
    /// toutes tailles d'encoche. Seuls les deux coins extérieurs sont arrondis.
    func testFanBaseIsContinuousAndFlushWithTheNotch() throws {
        for (size, hasNotch) in Self.notches {
            for mode in [EarTabsMode.visible, .retracted] {
                let fan = scene(.six, notch: size, hasNotch: hasNotch, mode: mode)
                let layout = fan.registry.earLayout(claude: fan.harness.store.indicator, claudeEars: fan.harness.store.ears,
                                                    notch: size)
                let sil = try silhouette(fan)
                let label = "\(size) \(mode)"
                XCTAssertEqual(layout.left.count, 3, label)
                let left = layout.left.last!.frame.minX + EarTabs.restRadius + 0.5
                let right = layout.right.last!.frame.maxX - EarTabs.restRadius - 0.5
                var bad: [String] = []
                for x in stride(from: left, through: right, by: 0.5) {
                    if !sil.covered(x, size.height - 0.3) { bad.append("base (\(x))") }
                    if sil.covered(x, size.height + 0.4) { bad.append("sous la base (\(x))") }
                    if !sil.covered(x, 0.3) { bad.append("haut (\(x))") }
                }
                XCTAssertTrue(bad.isEmpty, "\(label) : " + bad.prefix(6).joined(separator: " "))
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

    // MARK: - Le bord extérieur est celui de la notch

    private enum Element {
        case move(CGPoint), line(CGPoint), quad(CGPoint, CGPoint), close
    }

    private func elements(_ path: Path, origin: CGPoint) -> [Element] {
        func at(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x - origin.x, y: p.y - origin.y) }
        var out: [Element] = []
        path.forEach { element in
            switch element {
            case .move(let p): out.append(.move(at(p)))
            case .line(let p): out.append(.line(at(p)))
            case .quadCurve(let p, let c): out.append(.quad(at(p), at(c)))
            case .curve: XCTFail("courbe cubique : la notch n'utilise que des quadratiques")
            case .closeSubpath: out.append(.close)
            }
        }
        return out
    }

    private func assertSame(_ a: Element, _ b: Element, _ label: String, file: StaticString = #filePath, line: UInt = #line) {
        func same(_ p: CGPoint, _ q: CGPoint) -> Bool { abs(p.x - q.x) < 0.001 && abs(p.y - q.y) < 0.001 }
        switch (a, b) {
        case let (.move(p), .move(q)), let (.line(p), .line(q)):
            XCTAssertTrue(same(p, q), "\(label) : \(p) et non \(q)", file: file, line: line)
        case let (.quad(p, c), .quad(q, d)):
            XCTAssertTrue(same(p, q) && same(c, d), "\(label) : courbe \(p) / \(c) et non \(q) / \(d)", file: file, line: line)
        default:
            XCTFail("\(label) : \(a) et non \(b)", file: file, line: line)
        }
    }

    /// Le bord extérieur d'un intercalaire (évasement du haut, arête, coin du bas) est le bord gauche de `NotchShape` :
    /// mêmes points, mêmes points de contrôle, à toute largeur de tranche (même une languette de 8 pt) et toute hauteur
    /// d'encoche. Déployé : même évasement, coin du bas au rayon de la carte. L'autre côté en est le miroir.
    func testOuterEdgePathIsTheNotchsPath() {
        let top = NotchShape.collapsedTopRadius
        for (size, _) in Self.notches {
            for (bottom, height) in [(EarTabs.restRadius, size.height), (EarTabs.cardRadius, size.height + 80)] {
                let notchRect = CGRect(x: 40, y: 0, width: size.width + 2 * top, height: height)
                let reference = elements(NotchShape(topRadius: top, bottomRadius: bottom).path(in: notchRect),
                                         origin: CGPoint(x: notchRect.minX + top, y: 0))
                XCTAssertEqual(NotchShape(topRadius: top, bottomRadius: bottom).path(in: notchRect).boundingRect.minX,
                               notchRect.minX, accuracy: 0.001)
                // Une carte déployée n'est jamais plus étroite que sa tranche de repos ni que ses deux rayons.
                let widths = bottom == EarTabs.restRadius ? [EarTabs.sliverWidth, EarTabs.sliceWidth, 36.5, EarTabs.cardWidth]
                                                          : [EarTabs.sliceWidth, 36.5, EarTabs.cardWidth]
                for width in widths {
                    let rect = CGRect(x: -150 - width, y: 0, width: width, height: height)
                    let shape = EarTabShape(side: .left, outerRadius: bottom, overlap: EarTabs.overlap, overlapHeight: size.height)
                    let left = elements(shape.path(in: rect), origin: CGPoint(x: rect.minX, y: 0))
                    let label = "\(size) rayon \(bottom) largeur \(width)"
                    // move (pointe de l'évasement), évasement, arête, coin bas : les quatre premiers éléments.
                    for index in 0..<4 { assertSame(left[index], reference[index], "\(label) élément \(index)") }

                    let rightShape = EarTabShape(side: .right, outerRadius: bottom, overlap: EarTabs.overlap, overlapHeight: size.height)
                    let right = elements(rightShape.path(in: rect), origin: CGPoint(x: rect.maxX, y: 0))
                    func mirrored(_ e: Element) -> Element {
                        func m(_ p: CGPoint) -> CGPoint { CGPoint(x: -p.x, y: p.y) }
                        switch e {
                        case .move(let p): return .move(m(p))
                        case .line(let p): return .line(m(p))
                        case .quad(let p, let c): return .quad(m(p), m(c))
                        case .close: return .close
                        }
                    }
                    for index in 0..<4 { assertSame(right[index], mirrored(left[index]), "\(label) côté droit, élément \(index)") }
                }
            }
        }
    }

    /// Ligne par ligne, de combien le bord extérieur dépasse son arête (évasement du haut) puis rentre (coin du bas).
    private func outline(_ sil: Silhouette, side sign: CGFloat, height: CGFloat, from start: CGFloat = 0) -> [CGFloat] {
        let rows = Array(stride(from: CGFloat(0.25), through: height - 0.25, by: 0.25))
        let edge = rows.map { abs(sil.extent(row: $0, toward: sign, from: start) ?? .nan) }
        let body = edge[edge.count / 2]
        return edge.map { $0 - body }
    }

    /// Le bord extérieur DESSINÉ (pixels) a le profil de la notch : on rend `NotchShape` seule, aux rayons de la notch
    /// repliée, et on compare ligne par ligne avec le bord extérieur de l'intercalaire, à toute taille d'encoche : évasement
    /// du haut, arête, coin du bas. Sur une vraie encoche, le bas seulement (la forme repliée n'a pas d'évasement).
    func testRenderedOuterEdgeHasTheNotchsProfile() throws {
        let top = NotchShape.collapsedTopRadius, bottom = NotchShape.collapsedBottomRadius
        for (size, hasNotch) in Self.notches {
            let reference = Silhouette(
                bitmap: try render(NotchShape(topRadius: top, bottomRadius: bottom).fill(Color.black)
                    .frame(width: 60, height: size.height)
                    .frame(width: Self.band.width, height: Self.band.height, alignment: .top)),
                background: NSColor(red: 1, green: 0, blue: 1, alpha: 1))
            let wanted = outline(reference, side: -1, height: size.height)
            for (name, tabs, sign) in [("gauche", Tabs.claudeOnly, CGFloat(-1)), ("droite", .claudeAndTimer, 1)] {
                let sil = try silhouette(scene(tabs, notch: size, hasNotch: hasNotch))
                let drawn = outline(sil, side: sign, height: size.height)
                XCTAssertEqual(drawn.count, wanted.count)
                var bad: [String] = []
                for (index, (a, b)) in zip(drawn, wanted).enumerated() where !(abs(a - b) <= 0.4) {
                    bad.append("y=\(0.25 * CGFloat(index + 1)) : \(a) au lieu de \(b)")
                }
                XCTAssertTrue(bad.isEmpty, "\(size) bord \(name) : " + bad.prefix(6).joined(separator: " ; "))
                // Il y a bien un évasement (le bord dépasse son arête en haut) et un coin arrondi (il rentre en bas).
                XCTAssertGreaterThan(drawn.first ?? 0, top * 0.5, "\(size) bord \(name) : pas d'évasement")
                XCTAssertLessThan(drawn.last ?? 0, -bottom * 0.5, "\(size) bord \(name) : coin du bas non arrondi")
            }
        }
    }

    /// Aucun jour dans l'éventail : de l'arête extérieure du dernier intercalaire à celle de la notch, chaque ligne est
    /// dessinée en entier (hors coin du bas extérieur), au repos de 1 à 3 par côté, rétractés et avec un intercalaire déployé.
    func testFanHasNoGapBetweenSlices() throws {
        for (size, hasNotch) in Self.notches {
            for (tabs, mode, hovered) in [(Tabs.claudeOnly, EarTabsMode.visible, String?.none),
                                          (.claudeAndTimer, .visible, nil), (.six, .visible, nil), (.six, .retracted, nil),
                                          (.six, .visible, "media"), (.six, .visible, "claude")] {
                let fan = scene(tabs, notch: size, hasNotch: hasNotch, mode: mode, hovered: hovered)
                let layout = fan.registry.earLayout(claude: fan.harness.store.indicator, claudeEars: fan.harness.store.ears,
                                                    notch: size)
                let sil = try silhouette(fan)
                let label = "\(size) \(tabs) \(mode) survol : \(hovered ?? "aucun")"
                for items in [layout.left, layout.right] {
                    guard let last = items.last else { continue }
                    // Déployé, un intercalaire ne s'étend plus loin que son rang au repos.
                    let outer = items.map { $0.id == hovered ? layout.cardFrame($0, height: size.height) : $0.frame }
                        .map { last.side == .left ? $0.minX : $0.maxX }
                        .reduce(last.side == .left ? CGFloat.greatestFiniteMagnitude : -.greatestFiniteMagnitude) {
                            last.side == .left ? min($0, $1) : max($0, $1)
                        }
                    let sign: CGFloat = last.side == .left ? 1 : -1
                    var gaps: [String] = []
                    for y in stride(from: CGFloat(0.3), through: size.height - 0.3, by: 0.5) {
                        let corner = y > size.height - EarTabs.restRadius ? EarTabs.restRadius + 0.5 : 0.5
                        for step in stride(from: corner, through: abs(outer) - size.width / 2 - 0.5, by: 0.5) {
                            let x = outer + sign * step
                            if !sil.covered(x, y) { gaps.append("(\(x), \(y))") }
                        }
                    }
                    XCTAssertTrue(gaps.isEmpty, "\(label) côté \(last.side) : jour en " + gaps.prefix(6).joined(separator: " "))
                }
            }
        }
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
            ("eventail", scene(.six, notch: Self.measured, hasNotch: true)),
            ("eventail-retractes", scene(.six, notch: Self.measured, hasNotch: true, mode: .retracted)),
            ("eventail-ouvert-rang-1", scene(.six, notch: Self.measured, hasNotch: true, hovered: "media")),
            ("eventail-virtuel", scene(.six, notch: CGSize(width: 200, height: 24), hasNotch: false)),
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
