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
        let noTools = ToolsFeed(paths: LayoutTests.absentPaths)
        func root(_ store: SessionStore, _ tools: ToolsFeed) -> NotchRootView {
            NotchRootView(model: model, store: store, monitor: monitor, prefs: Preferences(), tools: tools,
                          actions: actions)
        }

        try render(root(store, noTools), name: "collapsed", to: outputDir)
        model.isExpanded = true
        try render(root(store, noTools), name: "expanded", to: outputDir)

        let empty = SessionStore()
        try render(root(empty, noTools), name: "empty", to: outputDir)

        // Section outils : fichiers récents (dont un supprimé), git avec deux dépôts à traiter, usage du jour.
        let fixtures = try ToolsFixtures()
        defer { fixtures.remove() }
        try fixtures.writeSample(now: Date())
        let tools = ToolsFeed(paths: fixtures.paths) { !$0.hasSuffix("old-config.ts") }
        tools.refreshNow()

        model.toolsPane = nil
        try render(root(store, tools), name: "tools", to: outputDir)
        model.toolsPane = .files
        try render(root(store, tools), name: "tools-files", to: outputDir)
        model.toolsPane = .git
        try render(root(store, tools), name: "tools-git", to: outputDir)
        model.toolsPane = nil
        try render(root(empty, tools), name: "tools-no-session", to: outputDir)

        // Beaucoup de sessions et volet ouvert : la liste rétrécit, tout tient dans le panneau.
        for index in 0..<5 {
            send("UserPromptSubmit", "projet-\(index)", ["prompt": "Tâche \(index)"])
        }
        model.toolsPane = .files
        try render(root(store, tools), name: "tools-crowded", to: outputDir)

        // Git propre et usage seul.
        try fixtures.writeSample(now: Date(), gitClean: true)
        try FileManager.default.removeItem(at: fixtures.paths.files)
        tools.refreshNow()
        model.toolsPane = nil
        try render(root(empty, tools), name: "tools-git-clean", to: outputDir)

        // Autres données (lecture seule) : `CLAUDE_NOTCH_TOOLS_DIR` = dossier contenant files.jsonl, state.json
        // et today.json, ou `standard` pour les vrais fichiers partagés de l'utilisateur.
        if let dir = ProcessInfo.processInfo.environment["CLAUDE_NOTCH_TOOLS_DIR"] {
            let base = URL(fileURLWithPath: dir)
            let real = ToolsFeed(paths: dir == "standard" ? .standard : ToolsFeed.Paths(
                files: base.appendingPathComponent("files.jsonl"), gitState: base.appendingPathComponent("state.json"),
                usage: base.appendingPathComponent("today.json")))
            real.refreshNow()
            print("TOOLS \(real.debugSummary)")
            for (pane, name) in [(nil, "tools-real"), (ToolsPane.files, "tools-real-files"), (.git, "tools-real-git")] {
                model.toolsPane = pane
                try render(root(store, real), name: name, to: outputDir)
            }
        }

        // Fenêtre de premier lancement : installation normale, depuis le DMG, mise à jour en erreur.
        // 32 pt en haut : la place de la barre de titre transparente de la vraie fenêtre.
        func onboarding(_ view: OnboardingView, _ name: String) throws {
            try render(view.padding(.top, 32).background(Color.black), name: name, to: outputDir,
                       size: CGSize(width: 470, height: 640))
        }
        try onboarding(OnboardingView(mode: .install, inApplications: true, launchAtLogin: true,
                                      onInstall: { _ in nil }, onClose: {}), "onboarding")
        try onboarding(OnboardingView(mode: .install, inApplications: false, launchAtLogin: true,
                                      onInstall: { _ in nil }, onClose: {}), "onboarding-dmg")
        let error = HookInstaller.Failure.invalidSettings("« , » ou « } » attendu, ligne 3, colonne 8")
        try onboarding(OnboardingView(mode: .update, inApplications: true, launchAtLogin: false,
                                      error: error.localizedDescription, onInstall: { _ in nil }, onClose: {}),
                       "onboarding-error")
    }

    /// Fenêtre hors écran + rendu de l'arbre de calques (ScrollView compris, contrairement à ImageRenderer).
    private func render<V: View>(_ view: V, name: String, to dir: URL,
                                 size: CGSize = CGSize(width: 640, height: 480)) throws {
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
