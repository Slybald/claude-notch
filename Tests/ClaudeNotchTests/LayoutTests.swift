import AppKit
import SwiftUI
import XCTest
@testable import ClaudeNotch

/// La vue doit remonter la taille réelle de la forme : le contrôleur s'en sert pour les zones de survol.
final class LayoutTests: XCTestCase {
    func testContentSizeIsReported() {
        _ = NSApplication.shared
        let store = SessionStore()
        store.handle(HookEvent(raw: ["hook_event_name": "UserPromptSubmit", "session_id": "s", "cwd": "/p", "prompt": "x"]),
                     context: ProcessContext())
        let model = NotchViewModel()
        model.notchSize = CGSize(width: 185, height: 32)
        let actions = NotchActions(activate: { _ in }, openDesktop: {}, clearEnded: {}, quit: {})
        let root = NotchRootView(model: model, store: store, monitor: ClaudeMonitor(), prefs: Preferences(),
                                 tools: ToolsFeed(paths: Self.absentPaths), actions: actions)
        let hosting = FirstMouseHostingView(rootView: root)
        hosting.sizingOptions = []
        hosting.frame = CGRect(x: 0, y: 0, width: 640, height: 480)
        let window = NSPanel(contentRect: hosting.frame, styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))

        // Replié avec oreilles : notch + 2 × 36 + 2 × 6 de rayon haut.
        XCTAssertEqual(model.contentSize.width, 185 + 72 + 12, accuracy: 1)
        XCTAssertEqual(model.contentSize.height, 32, accuracy: 1)

        model.isExpanded = true
        RunLoop.main.run(until: Date().addingTimeInterval(1.0))
        XCTAssertEqual(model.contentSize.width, NotchController.expandedWidth + 24, accuracy: 1)
        XCTAssertGreaterThan(model.contentSize.height, 80)

        model.isExpanded = false
        RunLoop.main.run(until: Date().addingTimeInterval(1.0))
        XCTAssertEqual(model.contentSize.width, 185 + 72 + 12, accuracy: 1)
        XCTAssertEqual(model.contentSize.height, 32, accuracy: 1)
        window.close()
    }

    static let absentPaths: ToolsFeed.Paths = {
        let missing = URL(fileURLWithPath: "/nonexistent/claude-notch")
        return ToolsFeed.Paths(files: missing.appendingPathComponent("files.jsonl"),
                               gitState: missing.appendingPathComponent("state.json"),
                               usage: missing.appendingPathComponent("today.json"))
    }()

    /// Section outils : comptée dans la taille remontée (zone de survol) et jamais plus haute que le panneau.
    func testToolsSectionFitsInPanel() throws {
        _ = NSApplication.shared
        let fixtures = try ToolsFixtures()
        defer { fixtures.remove() }
        try fixtures.writeSample(now: Date())
        let tools = ToolsFeed(paths: fixtures.paths) { _ in true }
        tools.refreshNow()
        XCTAssertTrue(tools.hasContent)

        func store(sessions: Int) -> SessionStore {
            let store = SessionStore()
            for index in 0..<sessions {
                let sid = "s\(index)"
                store.handle(HookEvent(raw: ["hook_event_name": "UserPromptSubmit", "session_id": sid,
                                             "cwd": "/p/\(sid)", "prompt": "x"]), context: ProcessContext())
                store.handle(HookEvent(raw: ["hook_event_name": "PreToolUse", "session_id": sid, "cwd": "/p/\(sid)",
                                             "tool_name": "Bash", "tool_use_id": "t\(index)",
                                             "tool_input": ["command": "npm test"]]), context: ProcessContext())
            }
            return store
        }

        // Une session : la section ouverte agrandit la forme, donc la zone de survol.
        let few = store(sessions: 1)
        let base = measure(few, ToolsFeed(paths: Self.absentPaths), pane: nil)
        let closed = measure(few, tools, pane: nil)
        let files = measure(few, tools, pane: .files)
        let git = measure(few, tools, pane: .git)
        XCTAssertEqual(closed.width, NotchController.expandedWidth + 24, accuracy: 1)
        XCTAssertGreaterThan(closed.height, base.height + 40)
        XCTAssertGreaterThan(files.height, closed.height + 80)
        XCTAssertGreaterThan(git.height, closed.height + 30)

        // Beaucoup de sessions : la liste cède la place, le tout reste sous 460 pt (fenêtre de 480 moins l'ombre).
        let many = store(sessions: 8)
        let crowdedBase = measure(many, ToolsFeed(paths: Self.absentPaths), pane: nil)
        XCTAssertEqual(crowdedBase.height, 32 + 10 + 296 + 14, accuracy: 1, "sans outils : liste à 296 comme avant")
        for pane in [nil, ToolsPane.files, ToolsPane.git] {
            let size = measure(many, tools, pane: pane)
            XCTAssertLessThanOrEqual(size.height, 461, "volet \(String(describing: pane))")
            XCTAssertGreaterThan(size.height, crowdedBase.height)
        }
    }

    private func measure(_ store: SessionStore, _ tools: ToolsFeed, pane: ToolsPane?) -> CGSize {
        let model = NotchViewModel()
        model.notchSize = CGSize(width: 185, height: 32)
        model.isExpanded = true
        model.toolsPane = pane
        let actions = NotchActions(activate: { _ in }, openDesktop: {}, clearEnded: {}, quit: {})
        let root = NotchRootView(model: model, store: store, monitor: ClaudeMonitor(), prefs: Preferences(),
                                 tools: tools, actions: actions)
        let hosting = FirstMouseHostingView(rootView: root)
        hosting.sizingOptions = []
        hosting.frame = CGRect(x: 0, y: 0, width: 640, height: 480)
        let window = NSPanel(contentRect: hosting.frame, styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        window.close()
        return model.contentSize
    }

    /// Diagnostic : contexte résolu pour un vrai processus (`CLAUDE_NOTCH_PROBE_PID`).
    func testProbeRealProcess() throws {
        guard let raw = ProcessInfo.processInfo.environment["CLAUDE_NOTCH_PROBE_PID"] else {
            throw XCTSkip("CLAUDE_NOTCH_PROBE_PID non défini")
        }
        let context = ProcessInspector.context(for: HookHeaders(["x-claude-ppid": raw]))
        print("PROBE pid=\(context.claudePid.map(String.init) ?? "-") source=\(context.source) "
              + "host=\(context.hostName ?? "-") bundle=\(context.hostBundleId ?? "-")")
        let chain = ProcessInspector.ancestors(of: pid_t(raw) ?? 0)
        print("PROBE chain: " + chain.map { "\($0.pid) \($0.name)" }.joined(separator: " / "))
    }
}
