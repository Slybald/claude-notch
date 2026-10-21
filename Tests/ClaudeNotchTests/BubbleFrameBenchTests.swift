import AppKit
import SwiftUI
import XCTest
@testable import ClaudeNotch

/// Banc du temps par image de la bulle, hors écran (fenêtres jamais affichées). Mesure le coût sur le fil principal
/// d'une image : mise à jour SwiftUI, mise en page, liste d'affichage envoyée à RenderBox (`CATransaction.flush`). Le
/// dessin lui-même (flou de la goutte compris) part au GPU, en dehors du fil principal : sonde faite, les vues sont
/// des `RBDrawingLayer`. Ne fait rien sans `CLAUDE_NOTCH_BENCH` (nom du rapport), écrit dans `CLAUDE_NOTCH_BENCH_OUT`.
final class BubbleFrameBenchTests: XCTestCase {
    private static var enabled: Bool { ProcessInfo.processInfo.environment["CLAUDE_NOTCH_BENCH"] != nil }

    /// MacBook Pro 14" : écran 1512 × 982 pt, encoche 185 × 32.
    private static let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
    private static let notch = CGRect(x: 663.5, y: 950, width: 185, height: 32)

    /// Vue dans une fenêtre jamais affichée.
    private final class Offscreen<V: View> {
        let hosting: NSHostingView<V>
        let window: NSWindow

        init(_ view: V, size: CGSize) {
            hosting = NSHostingView(rootView: view)
            hosting.sizingOptions = []
            hosting.frame = CGRect(origin: .zero, size: size)
            window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = hosting
        }

        /// Une image : nouvelle vue (ou nil : l'état observé a changé), mise en page, envoi. En millisecondes.
        @discardableResult
        func frame(_ view: V? = nil) -> Double {
            let start = CACurrentMediaTime()
            if let view { hosting.rootView = view }
            hosting.layoutSubtreeIfNeeded()
            hosting.layer?.displayIfNeeded()
            CATransaction.flush()
            return (CACurrentMediaTime() - start) * 1000
        }

        deinit { window.close() }
    }

    private struct Stats: CustomStringConvertible {
        let samples: [Double]
        var median: Double { samples.sorted()[samples.count / 2] }
        var p95: Double { samples.sorted()[min(samples.count - 1, Int(Double(samples.count) * 0.95))] }
        var max: Double { samples.max() ?? 0 }
        var description: String { String(format: "médiane %.2f ms, p95 %.2f ms, max %.2f ms", median, p95, max) }
    }

    private func report(_ part: String, _ lines: [String]) {
        let text = lines.joined(separator: "\n")
        print("\n=== Banc de la bulle ===\n" + text + "\n")
        if let dir = ProcessInfo.processInfo.environment["CLAUDE_NOTCH_BENCH_OUT"] {
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            let name = ProcessInfo.processInfo.environment["CLAUDE_NOTCH_BENCH"] ?? "bench"
            try? text.write(toFile: dir + "/bench-\(name)-\(part).txt", atomically: true, encoding: .utf8)
        }
    }

    /// Panneau déplié du MacBook (largeur des réglages par défaut) et poignée de son coin bas droit.
    private func pullGeometry(_ prefs: Preferences) -> (panel: CGRect, handle: CGPoint) {
        let width = prefs.expandedWidth(compact: false) - 24
        let panel = CGRect(x: Self.notch.midX - width / 2, y: Self.screen.maxY - 360, width: width, height: 360)
        return (panel, CGPoint(x: panel.maxX - 10, y: panel.minY + 6))
    }

    /// Une image de goutte par position de souris le long d'un glisser de 0 à 200 pt (décollage à 120), à la taille de
    /// la fenêtre de la goutte que `BubbleController.beginPull` ouvre.
    func testGooFrameTime() throws {
        guard Self.enabled else { throw XCTSkip("CLAUDE_NOTCH_BENCH non défini") }
        _ = NSApplication.shared
        let notch = NotchHarness(self)
        let (panel, handle) = pullGeometry(notch.prefs)
        let frame = BubbleController.gooFrame(
            covering: BubbleController.pullCover(panel: panel, notch: Self.notch, handle: handle),
            screenTop: Self.screen.maxY)
        let local = GooCoordinates(frame)
        var state = GooState(panel: local.body(panel), notch: local.body(Self.notch), handle: local.point(handle),
                             drop: local.point(handle))
        let start = Date()
        let view = { (date: Date) in GooCanvas(shapes: state.shapes(at: date), color: .black) }
        let t0 = CACurrentMediaTime()
        let bench = Offscreen(view(start), size: frame.size)
        let first = bench.frame() + (CACurrentMediaTime() - t0) * 1000
        for _ in 0..<10 { bench.frame(view(start)) }
        var times: [Double] = []
        for step in 0..<120 {
            let distance = CGFloat(step) * 200 / 119
            state.drop = local.point(CGPoint(x: handle.x + distance * 0.45, y: handle.y - distance * 0.89))
            times.append(bench.frame(view(start)))
        }
        report("goutte", [
            String(format: "Fenêtre de la goutte : %.0f × %.0f pt", frame.width, frame.height),
            String(format: "Goutte, première image (fenêtre neuve) : %.2f ms", first),
            "Goutte, une image du glisser : \(Stats(samples: times))",
        ])
    }

    /// Le décollage, pièce par pièce : phase publiée, réglage rangé, notch qui se replie, bulle affichée pour la première
    /// fois (fenêtre neuve) ou préparée d'avance.
    func testDetachHitch() throws {
        guard Self.enabled else { throw XCTSkip("CLAUDE_NOTCH_BENCH non défini") }
        _ = NSApplication.shared
        let notch = NotchHarness(self, store: .working(2))
        notch.model.isExpanded = true
        notch.model.selectedTab = "claude"
        let notchBench = Offscreen(notch.root, size: NotchController.panelSize)
        for _ in 0..<5 { notchBench.frame(notch.root) }
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        notchBench.frame()
        notch.model.gooActive = true
        let fade = notchBench.frame()
        notch.model.bubble = .bubble
        let phase = notchBench.frame()
        notch.prefs.bubbleDetached = true
        let saved = notchBench.frame()
        notch.model.isExpanded = false
        let collapse = notchBench.frame()

        let bubble = BubbleModel()
        let root = BubbleRootView(model: notch.model, bubble: bubble, store: notch.store, registry: notch.registry,
                                  prefs: notch.prefs, actions: NotchActions(), input: BubbleInput())
        let side = BubbleController.bubbleWindowSize
        let t0 = CACurrentMediaTime()
        let bubbleBench = Offscreen(root, size: side)
        let cold = bubbleBench.frame() + (CACurrentMediaTime() - t0) * 1000
        var warm: [Double] = []
        for step in 0..<30 {
            bubble.scale = 0.72 + 0.28 * CGFloat(step) / 29
            warm.append(bubbleBench.frame())
        }
        report("decollage", [
            String(format: "Décollage, notch qui s'efface sous la goutte : %.2f ms", fade),
            String(format: "Décollage, phase publiée (notch redessinée) : %.2f ms", phase),
            String(format: "Décollage, réglage « bulle détachée » rangé (notch redessinée) : %.2f ms", saved),
            String(format: "Décollage, notch qui se replie : %.2f ms", collapse),
            String(format: "Bulle, première image (fenêtre et vue neuves) : %.2f ms", cold),
            "Bulle déjà prête, une image du rebond : \(Stats(samples: warm))",
        ])
    }
}
