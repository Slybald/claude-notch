import AppKit
import XCTest
@testable import ClaudeNotch

/// Onglet Mail : décodage de la réponse du script, états, autorisations, rythme de lecture. Mail n'est jamais
/// lancé ni interrogé (script factice) ; le seul vrai `osascript` lancé ici est celui de la garde « Mail fermé ».
final class MailTests: XCTestCase {
    private let sample: [(sender: String, subject: String, age: Int, id: String)] = [
        ("Camille Martin <camille@example.com>", "Facture de   septembre", 300, "<abc123@mail.example.com>"),
        ("\"Durand, Alex\" <alex@example.com>", "Réunion\njeudi", 120, "def456@mail.example.com"),
        ("newsletter@example.com", "", 7_200, "ghi789@example.com"),
    ]

    // MARK: - Décodage

    func testParsesCountersOnly() {
        XCTAssertEqual(MailScript.parse(MailRig.answer(unread: 7), now: MessagesFixtures.now),
                       .reading(MailReading(unread: 7, accounts: 1, messages: [])))
    }

    func testParsesNotRunning() {
        XCTAssertEqual(MailScript.parse("NOTRUNNING", now: MessagesFixtures.now), .notRunning)
    }

    func testParsesMessagesNewestFirstWithCleanNamesAndDates() throws {
        let now = MessagesFixtures.now
        guard case .reading(let reading)? = MailScript.parse(MailRig.answer(unread: 9, messages: sample), now: now) else {
            return XCTFail("réponse illisible")
        }
        XCTAssertEqual(reading.unread, 9)
        XCTAssertEqual(reading.messages.map { $0.sender }, ["Durand, Alex", "Camille Martin", "newsletter@example.com"],
                       "triés du plus récent au plus ancien, noms sans guillemets ni adresse")
        XCTAssertEqual(reading.messages.map { $0.subject }, ["Réunion jeudi", "Facture de septembre", ""],
                       "objet sur une ligne")
        XCTAssertEqual(reading.messages[0].date, now.addingTimeInterval(-120))
        XCTAssertEqual(reading.messages.map { $0.id }, ["def456@mail.example.com", "abc123@mail.example.com", "ghi789@example.com"],
                       "Message-ID sans chevrons")
    }

    func testRefusesUnreadableAnswers() {
        for output in ["", "OK", "OK\u{1F}x\u{1F}1", "OK\u{1F}1", "erreur", "OK\u{1F}1\u{1F}1\u{1E}seulement\u{1F}trois\u{1F}champs"] {
            let parsed = MailScript.parse(output, now: MessagesFixtures.now)
            if output.hasSuffix("champs") {
                XCTAssertEqual(parsed, .reading(MailReading(unread: 1, accounts: 1, messages: [])), "enregistrement bancal ignoré")
            } else {
                XCTAssertNil(parsed, output)
            }
        }
    }

    func testOpenLinkIsTheMessageURLMailUnderstands() {
        let message = MailMessage(id: "abc123@mail.example.com", sender: "x", subject: "y", date: .distantPast)
        XCTAssertEqual(message.openURL?.absoluteString, "message://%3Cabc123%40mail.example.com%3E")
        XCTAssertNil(MailMessage(id: "", sender: "", subject: "", date: .distantPast).openURL)
    }

    func testSenderNames() {
        XCTAssertEqual(MailScript.displayName(of: "Prénom Nom <a@b.c>"), "Prénom Nom")
        XCTAssertEqual(MailScript.displayName(of: "<a@b.c>"), "a@b.c")
        XCTAssertEqual(MailScript.displayName(of: "a@b.c"), "a@b.c")
        XCTAssertEqual(MailScript.displayName(of: "  \"Nom\" <a@b.c> "), "Nom")
    }

    // MARK: - Garde « Mail fermé » (vrai osascript)

    /// Le script commence par `application id … is not running` : fermé, il répond NOTRUNNING sans lancer Mail et
    /// sans autorisation. Sauté si Mail tourne (on ne l'interroge jamais en test).
    func testRealScriptDoesNotLaunchMailWhenItIsClosed() throws {
        let bundle = MailScript.bundleIdentifier
        try XCTSkipUnless(FileManager.default.isExecutableFile(atPath: "/usr/bin/osascript"), "osascript absent")
        try XCTSkipUnless(NSRunningApplication.runningApplications(withBundleIdentifier: bundle).isEmpty,
                          "Mail tourne : on ne l'interroge pas en test")
        let output = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", MailScript.source, "--", "0"]
        process.standardOutput = output
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        XCTAssertEqual(String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .newlines), "NOTRUNNING")
        XCTAssertTrue(NSRunningApplication.runningApplications(withBundleIdentifier: bundle).isEmpty, "Mail n'a pas été lancé")
    }

    // MARK: - Module : repos

    func testModuleIsOffByDefaultAndDoesNothingUntilStarted() {
        let rig = MailRig(self)
        let module = rig.makeModule()
        XCTAssertFalse(module.isEnabledByDefault)
        XCTAssertFalse(module.keepsRunningWhenCollapsed)
        XCTAssertNil(module.ears)
        XCTAssertTrue(rig.runner.calls.isEmpty)
        XCTAssertEqual(rig.schedule.pendingDelays, [])
    }

    func testMailIsNeverLaunchedWhenClosed() {
        let rig = MailRig(self)
        rig.running = false
        let module = rig.makeModule()
        module.start()
        XCTAssertEqual(module.state, .notRunning)
        XCTAssertTrue(rig.runner.calls.isEmpty, "Mail fermé : aucun script, donc aucun lancement")
        XCTAssertEqual(rig.schedule.pendingDelays, [], "aucun minuteur tant que Mail est fermé")
        module.tabAppeared()
        module.authorize()
        XCTAssertTrue(rig.runner.calls.isEmpty, "même sur un clic")
        XCTAssertEqual(module.state, .notRunning)
    }

    func testNotDeterminedAsksOnlyOnClick() {
        let rig = MailRig(self)
        rig.probeStatus = .notDetermined
        rig.runner.answers = [.success(MailRig.answer(unread: 2))]
        let module = rig.makeModule()
        module.start()
        module.tabAppeared()
        XCTAssertEqual(module.state, .needsPermission)
        XCTAssertTrue(rig.runner.calls.isEmpty, "ouvrir l'onglet ne fait pas apparaître la fenêtre de macOS")
        XCTAssertFalse(module.keepsRunningWhenCollapsed)

        module.authorize()
        XCTAssertEqual(rig.runner.calls.count, 1)
        XCTAssertEqual(rig.runner.calls.first?.timeout, 60, "le temps de répondre à la fenêtre")
        XCTAssertEqual(module.state, .ready)
        XCTAssertEqual(module.unread, 2)
        XCTAssertTrue(module.keepsRunningWhenCollapsed, "un script a réussi : il peut tourner replié")
    }

    func testDeniedNeverRunsAndDisarms() {
        let rig = MailRig(self)
        rig.probeStatus = .denied
        let module = rig.makeModule()
        module.start()
        XCTAssertEqual(module.state, .denied)
        XCTAssertTrue(rig.runner.calls.isEmpty)
        module.authorize()
        XCTAssertTrue(rig.runner.calls.isEmpty, "refusé : seul Réglages Système peut le changer")
        XCTAssertFalse(module.keepsRunningWhenCollapsed)
    }

    func testRevokedAfterSuccessGoesBackToDenied() {
        let rig = MailRig(self)
        rig.runner.answers = [.success(MailRig.answer(unread: 1)), .failure(.notAuthorized)]
        let module = rig.makeModule()
        module.start()
        XCTAssertEqual(module.state, .ready)
        module.refresh()
        XCTAssertEqual(module.state, .denied)
        XCTAssertFalse(module.keepsRunningWhenCollapsed, "désarmé")
        XCTAssertNil(module.ears)
    }

    // MARK: - Module : lecture

    func testCollapsedAsksCountersOnlyAndOpenTabAsksTheList() {
        let rig = MailRig(self)
        rig.runner.answers = [.success(MailRig.answer(unread: 3)), .success(MailRig.answer(unread: 3, messages: sample))]
        let module = rig.makeModule()
        module.start()
        XCTAssertEqual(rig.runner.calls.first?.arguments, ["0"], "replié : les compteurs seulement")
        XCTAssertEqual(rig.runner.calls.first?.timeout, 20)
        XCTAssertTrue(module.messages.isEmpty)
        module.tabAppeared()
        XCTAssertEqual(rig.runner.calls.last?.arguments, [String(MailModule.fetchLimit)])
        XCTAssertEqual(module.messages.count, 3)
        XCTAssertEqual(module.messages.first?.sender, "Durand, Alex")
        XCTAssertEqual(module.unread, 3)
    }

    func testListIsCappedAtEight() {
        let rig = MailRig(self)
        let many = (0..<12).map { (sender: "s\($0)", subject: "o\($0)", age: $0 * 60, id: "id\($0)@example.com") }
        rig.runner.answers = [.success(MailRig.answer(unread: 12, messages: many))]
        let module = rig.makeModule()
        module.tabAppeared()
        module.start()
        XCTAssertEqual(module.messages.count, MailModule.maxShown)
        XCTAssertEqual(module.messages.first?.sender, "s0", "les plus récents")
    }

    func testEarsAreALowPriorityBadge() {
        let rig = MailRig(self)
        rig.runner.answers = [.success(MailRig.answer(unread: 5))]
        let module = rig.makeModule()
        module.start()
        XCTAssertEqual(module.ears, ModuleEars(symbol: "envelope.fill", text: "5", priority: MailModule.earsPriority))
        XCTAssertLessThan(MailModule.earsPriority, MessagesModule.earsPriority, "après une conversation")
        module.showBadge = false
        XCTAssertNil(module.ears)
        XCTAssertFalse(module.keepsRunningWhenCollapsed)
    }

    func testNoUnreadMeansNoEars() {
        let rig = MailRig(self)
        rig.runner.answers = [.success(MailRig.answer(unread: 0))]
        let module = rig.makeModule()
        module.start()
        XCTAssertEqual(module.state, .ready)
        XCTAssertNil(module.ears)
        XCTAssertNil(module.makeCompactView())
    }

    func testMailWithoutAccountIsReported() {
        let rig = MailRig(self)
        rig.runner.answers = [.success(MailRig.answer(unread: 0, accounts: 0))]
        let module = rig.makeModule()
        module.start()
        XCTAssertEqual(module.state, .noAccount)
        XCTAssertEqual(rig.schedule.pendingDelays, [], "rien à relire en boucle")
    }

    func testTimeoutAndBrokenAnswersGiveFailedWithoutDisarming() {
        let rig = MailRig(self)
        rig.runner.answers = [.success(MailRig.answer(unread: 1)), .failure(.timedOut), .success("n'importe quoi")]
        let module = rig.makeModule()
        module.start()
        module.refresh()
        XCTAssertEqual(module.state, .failed)
        XCTAssertTrue(module.keepsRunningWhenCollapsed, "un délai dépassé n'est pas un refus")
        XCTAssertNil(module.ears)
        module.refresh()
        XCTAssertEqual(module.state, .failed)
    }

    func testNotRunningAnswerFromScriptWinsOverStaleData() {
        let rig = MailRig(self)
        rig.runner.answers = [.success(MailRig.answer(unread: 4)), .success("NOTRUNNING")]
        let module = rig.makeModule()
        module.start()
        module.refresh()
        XCTAssertEqual(module.state, .notRunning)
        XCTAssertEqual(module.unread, 0)
    }

    // MARK: - Module : rythme

    func testPollsEveryTwoMinutesOnlyWhileMailRunsAndAnswers() {
        let rig = MailRig(self)
        rig.runner.answers = [.success(MailRig.answer(unread: 1)), .success(MailRig.answer(unread: 2)), .success(MailRig.answer(unread: 2))]
        let module = rig.makeModule()
        module.start()
        XCTAssertEqual(rig.schedule.pendingDelays, [MailModule.pollInterval])
        XCTAssertEqual(MailModule.pollInterval, 120)
        rig.schedule.runPending()
        XCTAssertEqual(rig.runner.calls.count, 2)
        XCTAssertEqual(module.unread, 2)
        XCTAssertEqual(rig.schedule.pendingDelays, [120], "un seul rendez-vous à la fois")

        rig.running = false
        rig.schedule.runPending()
        XCTAssertEqual(module.state, .notRunning)
        XCTAssertEqual(rig.runner.calls.count, 2, "Mail fermé : pas de script")
        XCTAssertEqual(rig.schedule.pendingDelays, [], "ni de minuteur")
    }

    func testStopCancelsThePollAndIgnoresLateWork() {
        let rig = MailRig(self)
        rig.runner.answers = [.success(MailRig.answer(unread: 1)), .success(MailRig.answer(unread: 9))]
        let module = rig.makeModule()
        module.start()
        module.stop()
        XCTAssertEqual(rig.schedule.pendingDelays, [])
        module.refresh()
        XCTAssertEqual(rig.runner.calls.count, 1, "arrêté : plus de script")
    }

    func testMailLaunchAndQuitTriggerARead() {
        let rig = MailRig(self)
        rig.running = false
        let module = rig.makeModule()
        module.start()
        XCTAssertEqual(module.state, .notRunning)
        // Un autre programme qui se lance ou se ferme ne réveille rien.
        rig.workspace.post(name: NSWorkspace.didLaunchApplicationNotification, object: nil,
                           userInfo: [NSWorkspace.applicationUserInfoKey: NSRunningApplication.current])
        XCTAssertEqual(rig.schedule.pendingDelays, [])
        XCTAssertTrue(rig.runner.calls.isEmpty)
        module.stop()
        // Après l'arrêt, plus d'observateur.
        rig.workspace.post(name: NSWorkspace.didTerminateApplicationNotification, object: nil,
                           userInfo: [NSWorkspace.applicationUserInfoKey: NSRunningApplication.current])
        XCTAssertTrue(rig.runner.calls.isEmpty)
    }

    // MARK: - Registre

    func testRegistryOnlyRunsMailOnceReadAndKeepsItsBadgeLowPriority() {
        let rig = MailRig(self)
        rig.runner.answers = [.success(MailRig.answer(unread: 4)), .success(MailRig.answer(unread: 4))]
        let prefs = Preferences(defaults: makeEphemeralDefaults(self))
        prefs.tabEnabled["mail"] = true
        let registry = ModuleRegistry(modules: [FakeModule(id: "claude"), rig.makeModule()], prefs: prefs)
        XCTAssertFalse(registry.running.contains("mail"))
        XCTAssertTrue(rig.runner.calls.isEmpty, "activé mais jamais ouvert : aucun script")

        registry.setPanelOpen(true)
        XCTAssertEqual(rig.runner.calls.count, 1)
        registry.setPanelOpen(false)
        XCTAssertTrue(registry.running.contains("mail"), "un script a réussi : il continue replié")
        XCTAssertEqual(registry.moduleEars?.text, "4")
        let tabs = EarTabs.tabs(claude: .done, claudeEars: nil, modules: registry.earsEntries, showEars: true)
        XCTAssertEqual(tabs.map { $0.id }, ["claude", "mail"])

        registry.setEnabled("mail", false)
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        XCTAssertFalse(registry.running.contains("mail"))
        XCTAssertEqual(rig.schedule.pendingDelays, [], "arrêté : plus de minuteur")
    }

    // MARK: - Actions

    func testOpenActions() {
        let rig = MailRig(self)
        let module = rig.makeModule()
        module.openMail()
        module.openMessage(MailMessage(id: "abc@example.com", sender: "x", subject: "y", date: .distantPast))
        module.openMessage(MailMessage(id: "", sender: "x", subject: "y", date: .distantPast))
        module.openPrivacy(.automation)
        XCTAssertEqual(rig.opened.map { $0.absoluteString }, [
            MailScript.appURL.absoluteString, "message://%3Cabc%40example.com%3E", MailScript.appURL.absoluteString,
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation",
        ])
    }

    func testCompactViewShowsSenderNeverSubject() {
        let rig = MailRig(self)
        rig.runner.answers = [.success(MailRig.answer(unread: 3, messages: sample))]
        let module = rig.makeModule()
        module.tabAppeared()
        module.start()
        XCTAssertNotNil(module.makeCompactView())
        XCTAssertEqual(MailPanel.unreadText(1), "1 message non lu")
        XCTAssertEqual(MailPanel.unreadText(3), "3 messages non lus")
    }
}
