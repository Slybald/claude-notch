import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Créé après la migration : les préférences lisent le LaunchAgent à leur création.
    private lazy var core = AppCore()

    func applicationDidFinishLaunching(_ notification: Notification) {
        if isAnotherInstanceRunning() {
            NSApp.terminate(nil)
            return
        }
        replaceLegacyInstance()
        AppIdentity.migrateLegacyInstall()
        core.start()
        HookSetup.shared.showOnboardingIfNeeded()
    }

    /// Une instance de cette version tourne déjà : elle suffit.
    private func isAnotherInstanceRunning() -> Bool {
        let me = ProcessInfo.processInfo.processIdentifier
        let ids = Set([AppIdentity.bundleId, Bundle.main.bundleIdentifier].compactMap { $0 })
        return ids.contains { id in
            NSRunningApplication.runningApplications(withBundleIdentifier: id)
                .contains { $0.processIdentifier != me && !$0.isTerminated }
        }
    }

    /// L'ancienne version (local.claudenotch) cède la place : elle tient le port des hooks.
    private func replaceLegacyInstance() {
        let legacy = NSRunningApplication.runningApplications(withBundleIdentifier: AppIdentity.legacyBundleId)
            .filter { !$0.isTerminated }
        guard !legacy.isEmpty else { return }
        legacy.forEach { $0.terminate() }
        let deadline = Date().addingTimeInterval(3)
        while legacy.contains(where: { !$0.isTerminated }), Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        legacy.filter { !$0.isTerminated }.forEach { $0.forceTerminate() }
    }
}

/// Assemble le serveur de hooks, la surveillance des processus, l'état des sessions et la notch.
final class AppCore {
    let store = SessionStore()
    let monitor = ClaudeMonitor()
    let prefs = Preferences.shared
    let tools: ToolsFeed
    let activityLog: ActivityLog
    let jobs = JobRunner()
    let updater = Updater.shared
    private var server: HookServer?
    private var notch: NotchController?

    init(tools: ToolsFeed = ToolsFeed(), activityLog: ActivityLog = ActivityLog()) {
        self.tools = tools
        self.activityLog = activityLog
    }

    /// Chaque événement met à jour les sessions puis, au besoin, les registres CF1 / CF2 (cwd de la session connu).
    static func hookHandler(store: SessionStore, log: ActivityLog) -> HookServer.Handler {
        { event, context in
            DispatchQueue.main.async {
                store.handle(event, context: context)
                log.record(event, session: event.sessionId.flatMap { store.sessions[$0] })
            }
        }
    }

    func start() {
        let server = HookServer(handler: Self.hookHandler(store: store, log: activityLog))
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
        jobs.start()
        updater.isBusy = { [store] in store.hasBusySessions }
        updater.start()

        let notch = NotchController(store: store, monitor: monitor, prefs: prefs, tools: tools)
        notch.start()
        self.notch = notch
        MainMenu.install(openSettings: { [weak notch] in notch?.openSettings() })
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
        state["sessionTimer"] = store.isTicking
        state["notch"] = notch?.debugInfo
        var tools = self.tools.debugSummary
        tools["filesLogged"] = activityLog.filesLogged
        tools["permissionsLogged"] = activityLog.permissionsLogged
        tools["failedWrites"] = activityLog.failedWrites
        tools["logDirectory"] = activityLog.directory.path
        state["tools"] = tools
        state["jobs"] = jobs.debugSummary
        state["version"] = updater.currentVersion
        state["updater"] = updater.debugSummary
        return state
    }
}
