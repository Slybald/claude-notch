import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let core = AppCore()

    func applicationDidFinishLaunching(_ notification: Notification) {
        if isAnotherInstanceRunning() {
            NSApp.terminate(nil)
            return
        }
        core.start()
    }

    private func isAnotherInstanceRunning() -> Bool {
        guard let bundleId = Bundle.main.bundleIdentifier else { return false }
        let me = ProcessInfo.processInfo.processIdentifier
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
            .contains { $0.processIdentifier != me && !$0.isTerminated }
    }
}

/// Assemble le serveur de hooks, la surveillance des processus, l'état des sessions et la notch.
final class AppCore {
    let store = SessionStore()
    let monitor = ClaudeMonitor()
    let prefs = Preferences.shared
    private var server: HookServer?
    private var notch: NotchController?

    func start() {
        let store = self.store
        let server = HookServer { event, context in
            DispatchQueue.main.async { store.handle(event, context: context) }
        }
        server.stateProvider = { [weak self] in self?.debugState() ?? [:] }
        server.onFailure = { error in
            // Port déjà pris : une autre instance tourne, inutile de rester.
            NSLog("ClaudeNotch : serveur de hooks indisponible (%@), arrêt.", String(describing: error))
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
        do {
            try server.start()
        } catch {
            NSLog("ClaudeNotch : impossible d'ouvrir le port %d (%@).", Int(HookServer.defaultPort), String(describing: error))
            NSApp.terminate(nil)
            return
        }
        self.server = server

        monitor.start()
        store.start()

        let notch = NotchController(store: store, monitor: monitor, prefs: prefs)
        notch.start()
        self.notch = notch
    }

    /// Instantané lisible de l'état, servi par `GET /state` (diagnostic local).
    func debugState() -> [String: Any] {
        let sessions: [[String: Any]] = store.sortedSessions.map { session in
            var item: [String: Any] = [
                "id": session.id,
                "project": session.projectName,
                "source": session.source == .desktop ? "desktop" : "cli",
                "phase": String(describing: session.phase),
                "status": [session.status.label, session.status.detail].compactMap { $0 }.joined(separator: " · "),
                "inTurn": session.inTurn,
                "toolCount": session.toolCount,
                "agents": session.activeAgents.count,
                "tasks": "\(session.completedTaskCount)/\(session.tasks.count)",
            ]
            item["host"] = session.hostName
            item["hostBundleId"] = session.hostBundleId
            item["pid"] = session.claudePid.map { Int($0) }
            item["title"] = session.title
            item["desktopSessionId"] = session.desktopSessionId
            item["currentTask"] = session.currentTask?.subject
            return item
        }
        var state: [String: Any] = [
            "sessions": sessions,
            "indicator": String(describing: store.indicator),
            "desktopRunning": monitor.desktopRunning,
            "desktopFrontmost": monitor.desktopFrontmost,
            "cliPids": monitor.cliPids.map { Int($0) }.sorted(),
            "desktopPids": monitor.desktopPids.map { Int($0) }.sorted(),
            "untrackedCli": monitor.cliPids.subtracting(store.trackedPids).count,
        ]
        state["ears"] = store.earsText
        state["notch"] = notch?.debugInfo
        return state
    }
}
