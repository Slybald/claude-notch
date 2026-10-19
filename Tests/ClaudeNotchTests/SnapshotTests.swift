import AppKit
import SwiftUI
import XCTest
@testable import ClaudeNotch

/// Rend la notch hors écran en PNG pour contrôle visuel.
/// Ne fait rien sans `CLAUDE_NOTCH_SNAPSHOT_DIR`.
final class SnapshotTests: XCTestCase {
    private var outputDir: URL? {
        ProcessInfo.processInfo.environment["CLAUDE_NOTCH_SNAPSHOT_DIR"].map { URL(fileURLWithPath: $0) }
    }

    func testRenderStates() throws {
        guard let outputDir else { throw XCTSkip("CLAUDE_NOTCH_SNAPSHOT_DIR non défini") }
        _ = NSApplication.shared
        let store = SessionStore()
        let context = ProcessContext(source: .cli, hostName: "iTerm2", hostBundleId: "com.googlecode.iterm2")
        func send(_ name: String, _ sid: String, _ extra: [String: Any] = [:]) {
            var raw: [String: Any] = ["hook_event_name": name, "session_id": sid, "cwd": "/Users/x/Projets/\(sid)"]
            raw.merge(extra) { $1 }
            store.handle(HookEvent(raw: raw), context: context)
        }
        send("SessionStart", "mon-app", ["source": "startup"])
        send("UserPromptSubmit", "mon-app", ["prompt": "Lance les tests puis corrige le parseur"])
        send("PreToolUse", "mon-app", ["tool_name": "TodoWrite", "tool_use_id": "t0", "tool_input": ["todos": [
            ["content": "Lancer les tests", "status": "completed", "activeForm": "Lancement des tests"],
            ["content": "Corriger le parseur", "status": "in_progress", "activeForm": "Correction du parseur"],
            ["content": "Relancer la suite", "status": "pending", "activeForm": "Relance"],
        ]]])
        send("PreToolUse", "mon-app", ["tool_name": "Bash", "tool_use_id": "t1",
                                       "tool_input": ["command": "npm test -- --watch=false"]])
        send("SubagentStart", "mon-app", ["agent_id": "a1"])
        send("SubagentStart", "mon-app", ["agent_id": "a2"])

        send("UserPromptSubmit", "api", ["prompt": "Supprime le dossier build"])
        send("PreToolUse", "api", ["tool_name": "Bash", "tool_use_id": "p1", "tool_input": ["command": "rm -rf build"]])
        send("PermissionRequest", "api", ["tool_name": "Bash", "tool_input": ["command": "rm -rf build"]])

        send("UserPromptSubmit", "site", ["prompt": "Mets à jour le README"])
        send("Stop", "site", ["last_assistant_message": "## **README à jour** : section installation réécrite."])

        let model = NotchViewModel()
        model.notchSize = CGSize(width: 185, height: 32)
        model.hasNotch = true
        let actions = NotchActions(activate: { _ in }, openDesktop: {}, clearEnded: {}, quit: {})
        let monitor = ClaudeMonitor()

        try render(NotchRootView(model: model, store: store, monitor: monitor, prefs: Preferences(), actions: actions),
                   name: "collapsed", to: outputDir)
        model.isExpanded = true
        try render(NotchRootView(model: model, store: store, monitor: monitor, prefs: Preferences(), actions: actions),
                   name: "expanded", to: outputDir)

        let empty = SessionStore()
        try render(NotchRootView(model: model, store: empty, monitor: monitor, prefs: Preferences(), actions: actions),
                   name: "empty", to: outputDir)
    }

    /// Fenêtre hors écran + rendu de l'arbre de calques (ScrollView compris, contrairement à ImageRenderer).
    private func render<V: View>(_ view: V, name: String, to dir: URL) throws {
        let size = CGSize(width: 640, height: 480)
        let hosting = NSHostingView(rootView: view.background(Color(white: 0.85)))
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
        // Le calque de NSHostingView est géométriquement retourné : on remet l'origine en haut.
        cg.translateBy(x: 0, y: size.height * scale)
        cg.scaleBy(x: scale, y: -scale)
        layer.render(in: cg)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { return XCTFail("PNG") }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try png.write(to: dir.appendingPathComponent("\(name).png"))
        window.close()
    }
}
