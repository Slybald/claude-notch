import AppKit
import SwiftUI
import XCTest
@testable import ClaudeNotch

/// Rendus PNG de « Répondre depuis la notch » (permission, question, plan, message, retours, plein écran,
/// réglages). Ne fait rien sans `CLAUDE_NOTCH_SNAPSHOT_DIR`. Données fictives, aucun hook réel.
final class ClaudeSnapshotTests: XCTestCase {
    private var outputDir: URL? {
        ProcessInfo.processInfo.environment["CLAUDE_NOTCH_SNAPSHOT_DIR"].map { URL(fileURLWithPath: $0) }
    }

    /// Notch dépliée sur l'onglet Claude, avec son propre `ReplyCenter` et des réglages jetables.
    private final class Scene {
        let prefs: Preferences
        let replies: ReplyCenter
        let store = SessionStore()
        let claude: ClaudeModule
        let registry: ModuleRegistry
        let model = NotchViewModel()
        private let context = ProcessContext(source: .cli, hostName: "iTerm2", hostBundleId: "com.googlecode.iterm2")

        init(_ testCase: XCTestCase) {
            _ = NSApplication.shared
            prefs = Preferences(defaults: makeEphemeralDefaults(testCase))
            prefs.replyFromNotch = true
            replies = ReplyCenter(prefs: prefs)
            let config = FileManager.default.temporaryDirectory.appendingPathComponent("claude-notch-no-config")
            claude = ClaudeModule(store: store, monitor: ClaudeMonitor(), tools: ToolsFeed(paths: LayoutTests.absentPaths),
                                  prefs: prefs, hooks: HookSetup(installer: HookInstaller(configDirectory: config,
                                                                                        bundledHook: nil)),
                                  replies: replies)
            registry = ModuleRegistry(modules: ModuleRegistry.standardModules(claude: claude), prefs: prefs)
            model.notchSize = CGSize(width: 185, height: 32)
            model.hasNotch = true
            model.isExpanded = true
        }

        var root: NotchRootView {
            NotchRootView(model: model, store: store, registry: registry, prefs: prefs, actions: NotchActions())
        }

        func send(_ name: String, _ sid: String, _ extra: [String: Any] = [:]) {
            store.send(name, sid, extra, context: context)
        }

        /// Session en attente : événements relayés (carte de session) et requête tenue (carte de réponse).
        @discardableResult
        func ask(_ sid: String, prompt: String, tool: String, input: [String: Any]) -> ReplyCenter.Request {
            send("UserPromptSubmit", sid, ["prompt": prompt])
            send("PreToolUse", sid, ["tool_name": tool, "tool_use_id": "t-\(sid)", "tool_input": input])
            let event: [String: Any] = ["tool_name": tool, "tool_input": input]
            send("PermissionRequest", sid, event)
            replies.hold(HookEvent(raw: event.merging(["hook_event_name": "PermissionRequest", "session_id": sid]) { $1 })) { _ in }
            return replies.requests.last!
        }

        func working(_ sid: String) {
            send("UserPromptSubmit", sid, ["prompt": "Lance les tests"])
            send("PreToolUse", sid, ["tool_name": "Bash", "tool_use_id": "w-\(sid)",
                                     "tool_input": ["command": "swift test --parallel"]])
        }

        func done(_ sid: String, _ message: String) {
            send("UserPromptSubmit", sid, ["prompt": "Mets à jour le README"])
            send("Stop", sid, ["last_assistant_message": message])
        }
    }

    func testRenderReplyStates() throws {
        guard let outputDir else { throw XCTSkip("CLAUDE_NOTCH_SNAPSHOT_DIR non défini") }

        // Permission : la commande complète, le motif facultatif, Refuser / Autoriser.
        let permission = Scene(self)
        permission.ask("api", prompt: "Nettoie le build", tool: "Bash",
                       input: ["command": "rm -rf build && swift build -c release", "description": "Rebuild propre"])
        permission.working("mon-app")
        try render(permission.root, name: "reply-permission", to: outputDir)

        // Commande longue : coupée, avec l'invitation à la lire dans la session.
        let long = Scene(self)
        long.ask("infra", prompt: "Déploie", tool: "Bash", input: ["command": (1...9).map {
            "kubectl --context prod-\($0) rollout restart deployment/api-\($0) --namespace services"
        }.joined(separator: " && \\\n")])
        try render(long.root, name: "reply-permission-long", to: outputDir)

        // Questions : choix unique déjà fait, multiple, texte libre.
        let question = Scene(self)
        let request = question.ask("site", prompt: "Choisis le thème", tool: "AskUserQuestion", input: ["questions": [
            ["question": "Quelle couleur d'accent ?", "header": "Couleur", "multiSelect": false,
             "options": [["label": "Orange", "description": "celle de Claude"], ["label": "Bleu", "description": "plus calme"]]],
            ["question": "Quelles pages ?", "header": "Pages", "multiSelect": true,
             "options": [["label": "Accueil"], ["label": "Blog"], ["label": "Contact"]]],
        ]])
        question.claude.drafts.choices[ReplyDrafts.key(request.id, 0)] = ["Bleu"]
        question.claude.drafts.choices[ReplyDrafts.key(request.id, 1)] = ["Accueil", "Contact"]
        try render(question.root, name: "reply-question", to: outputDir)

        // Plan à valider.
        let plan = Scene(self)
        plan.ask("api", prompt: "Prépare la migration", tool: "ExitPlanMode", input: [
            "plan": "# Migration de la base\n\n**Contexte :** passer de SQLite à Postgres.\n\n1. Ajouter le pilote\n"
                + "2. Écrire le script de migration\n3. Lancer les tests d'intégration\n4. Mettre à jour le README",
            "planFilePath": "/tmp/plan.md"])
        try render(plan.root, name: "reply-plan", to: outputDir)

        // Message : attente connectée (session au repos), et une autre session avec un message en file.
        let message = Scene(self)
        message.done("site", "README à jour : section installation réécrite.")
        message.working("api")
        message.replies.wait(sessionId: "site", pid: nil) { _ in }
        message.claude.drafts.composing = "site"
        message.claude.drafts.texts["site"] = "Ajoute aussi une section FAQ"
        message.replies.send("Ensuite, lance les tests d'intégration", to: "api")
        try render(message.root, name: "reply-message", to: outputDir)

        // Pas d'attente connectée : le message partira à la fin du tour.
        let queued = Scene(self)
        queued.working("api")
        queued.claude.drafts.composing = "api"
        try render(queued.root, name: "reply-message-queued", to: outputDir)

        // Retours : décision prise, et une demande que la notch ne tient plus (« Réponds dans iTerm2 »).
        let notices = Scene(self)
        let done = notices.ask("api", prompt: "Supprime le cache", tool: "Bash", input: ["command": "rm -rf .cache"])
        notices.claude.decide(done, .allow)
        notices.send("UserPromptSubmit", "site", ["prompt": "Publie"])
        notices.send("PreToolUse", "site", ["tool_name": "Bash", "tool_use_id": "p", "tool_input": ["command": "npm publish"]])
        notices.send("PermissionRequest", "site", ["tool_name": "Bash", "tool_input": ["command": "npm publish"]])
        try render(notices.root, name: "reply-notices", to: outputDir)

        // Plein écran, mode compact : la demande sous la ligne de session.
        let compact = Scene(self)
        compact.ask("api", prompt: "Nettoie", tool: "Bash", input: ["command": "rm -rf build"])
        compact.working("mon-app")
        compact.model.isFullScreen = true
        try render(compact.root, name: "reply-fullscreen-compact", to: outputDir)

        // Réglage coupé : aucune carte de réponse, la notch ne fait que suivre.
        let off = Scene(self)
        off.ask("api", prompt: "Nettoie", tool: "Bash", input: ["command": "rm -rf build"])
        off.prefs.replyFromNotch = false
        try render(off.root, name: "reply-off", to: outputDir)

        // Réglages › Claude, réponse activée, hooks à mettre à jour.
        let settings = Scene(self)
        try render(SettingsView(prefs: settings.prefs, registry: settings.registry, updater: Updater(),
                                selection: .module("claude")),
                   name: "reply-settings", to: outputDir, size: SettingsWindow.size, background: nil)
    }

    /// Fenêtre hors écran + rendu de l'arbre de calques, comme SnapshotTests.
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
