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
        let root = NotchRootView(model: model, store: store, monitor: ClaudeMonitor(), prefs: Preferences(), actions: actions)
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
