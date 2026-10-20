import Foundation
import XCTest
@testable import ClaudeNotch

/// « Répondre depuis la notch » : décisions, échéances, attentes, file, troncature. Sans réseau ni vraie session.
final class ClaudeReplyTests: XCTestCase {
    private var prefs: Preferences!
    private var replies: ReplyCenter!
    private var now = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUp() {
        prefs = Preferences(defaults: makeEphemeralDefaults(self))
        prefs.replyFromNotch = true
        replies = ReplyCenter(prefs: prefs)
        replies.clock = { [unowned self] in self.now }
    }

    /// Réponse reçue par le « hook » : nil tant qu'il attend, `.some(nil)` pour un 204.
    private final class Box<T> {
        var replies: [T?] = []
        var last: T?? { replies.last }
    }

    private func permission(_ sid: String = "s1", tool: String = "Bash",
                            input: [String: Any] = ["command": "rm -rf build", "description": "Supprime build"])
        -> HookEvent {
        HookEvent(raw: ["hook_event_name": "PermissionRequest", "session_id": sid, "tool_name": tool,
                        "tool_input": input])
    }

    @discardableResult
    private func hold(_ event: HookEvent) -> (ReplyCenter.Request, Box<Data>) {
        let box = Box<Data>()
        replies.hold(event) { box.replies.append($0) }
        return (replies.requests.last!, box)
    }

    private func decision(_ data: Data??) throws -> [String: Any] {
        let data = try XCTUnwrap(try XCTUnwrap(data))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let output = try XCTUnwrap(object["hookSpecificOutput"] as? [String: Any])
        XCTAssertEqual(output["hookEventName"] as? String, "PermissionRequest")
        return try XCTUnwrap(output["decision"] as? [String: Any])
    }

    // MARK: - Réglage

    func testDisabledHandsBackAtOnce() {
        prefs.replyFromNotch = false
        let held = Box<Data>()
        replies.hold(permission()) { held.replies.append($0) }
        XCTAssertEqual(held.replies.count, 1)
        XCTAssertNil(held.replies[0], "204 tout de suite : le terminal garde la main")
        XCTAssertTrue(replies.requests.isEmpty)

        let waited = Box<String>()
        replies.wait(sessionId: "s1", pid: nil) { waited.replies.append($0) }
        XCTAssertEqual(waited.replies.count, 1)
        XCTAssertNil(waited.replies[0])
        XCTAssertNil(replies.send("bonjour", to: "s1"))
    }

    func testTurningOffReleasesEverything() {
        let (_, held) = hold(permission())
        let waited = Box<String>()
        replies.wait(sessionId: "s2", pid: nil) { waited.replies.append($0) }
        replies.send("en file", to: "s3")
        XCTAssertEqual(replies.queued["s3"], ["en file"])

        prefs.replyFromNotch = false
        XCTAssertEqual(held.replies.count, 1)
        XCTAssertNil(held.replies[0])
        XCTAssertEqual(waited.replies.count, 1)
        XCTAssertNil(waited.replies[0])
        XCTAssertTrue(replies.requests.isEmpty)
        XCTAssertTrue(replies.waiting.isEmpty)
        XCTAssertTrue(replies.queued.isEmpty)
    }

    // MARK: - Permissions

    func testAllowAndDenyOutputs() throws {
        let (request, box) = hold(permission())
        guard case .permission(let summary) = request.kind else { return XCTFail("permission attendue") }
        XCTAssertEqual(summary.detail, "rm -rf build", "la commande complète, pas sa description")
        XCTAssertEqual(summary.note, "Supprime build")

        // Une décision d'un autre type est refusée, la demande reste tenue.
        XCTAssertFalse(replies.decide(request, .approvePlan))
        XCTAssertFalse(replies.decide(request, .answer(["x": "y"])))
        XCTAssertTrue(box.replies.isEmpty)

        XCTAssertTrue(replies.decide(request, .allow))
        XCTAssertEqual(try decision(box.last) as NSDictionary, ["behavior": "allow"])
        XCTAssertTrue(replies.requests.isEmpty)
        XCTAssertEqual(replies.notices["s1"]?.text, "Autorisé")
        XCTAssertFalse(replies.decide(request, .allow), "une seule réponse par demande")
        XCTAssertEqual(box.replies.count, 1)
        XCTAssertEqual(replies.notices["s1"]?.tone, .warning)

        let (second, denied) = hold(permission())
        XCTAssertTrue(replies.decide(second, .deny("  Pas en prod\u{1B}[31m \n")))
        XCTAssertEqual(try decision(denied.last) as NSDictionary, ["behavior": "deny", "message": "Pas en prod[31m"])

        let (third, silent) = hold(permission())
        XCTAssertTrue(replies.decide(third, .deny("")))
        XCTAssertEqual(try decision(silent.last)["message"] as? String, ReplyCenter.defaultDenyMessage)
    }

    func testQuestionAnswersKeepOriginalInput() throws {
        let questions: [[String: Any]] = [
            ["question": "Which color do you prefer?", "header": "Color", "multiSelect": false,
             "options": [["label": "Red", "description": "warm"], ["label": "Blue", "description": "cold"]]],
            ["question": "Which animals?", "header": "Animals", "multiSelect": true,
             "options": [["label": "Cats"], ["label": "Dogs"], ["label": "Birds"]]],
        ]
        let (request, box) = hold(permission(tool: "AskUserQuestion", input: ["questions": questions]))
        guard case .question(let parsed) = request.kind else { return XCTFail("question attendue") }
        XCTAssertEqual(parsed.map(\.text), ["Which color do you prefer?", "Which animals?"])
        XCTAssertEqual(parsed[0].options, [.init(label: "Red", detail: "warm"), .init(label: "Blue", detail: "cold")])
        XCTAssertTrue(parsed[1].multiSelect)

        // Toutes les questions doivent avoir une réponse.
        XCTAssertFalse(replies.decide(request, .answer(["Which color do you prefer?": "Blue"])))
        XCTAssertFalse(replies.decide(request, .allow))
        XCTAssertTrue(box.replies.isEmpty)

        let multi = ReplyCenter.answer(selected: ["Cats", "Birds"], other: " Hamsters ")
        XCTAssertEqual(multi, "Cats, Birds, Hamsters")
        XCTAssertTrue(replies.decide(request, .answer(["Which color do you prefer?": "Blue", "Which animals?": multi])))
        let result = try decision(box.last)
        XCTAssertEqual(result["behavior"] as? String, "allow")
        let input = try XCTUnwrap(result["updatedInput"] as? [String: Any])
        XCTAssertEqual((input["questions"] as? [[String: Any]])?.count, 2, "entrée d'origine renvoyée")
        XCTAssertEqual(input["answers"] as? [String: String],
                       ["Which color do you prefer?": "Blue", "Which animals?": "Cats, Birds, Hamsters"])
        XCTAssertEqual(replies.notices["s1"]?.text, "Réponse envoyée")
    }

    func testQuestionWithoutQuestionsIsNotHeld() {
        let box = Box<Data>()
        replies.hold(permission(tool: "AskUserQuestion", input: ["questions": []])) { box.replies.append($0) }
        XCTAssertEqual(box.replies.count, 1)
        XCTAssertNil(box.replies[0])
    }

    func testPlanApprovalSetsModeAndRevisionDenies() throws {
        let input: [String: Any] = ["plan": "# Plan\n\n**Contexte :** créer `a.txt`.\n\n\n1. Écrire le fichier",
                                    "planFilePath": "/tmp/plan.md"]
        let (request, box) = hold(permission(tool: "ExitPlanMode", input: input))
        guard case .plan(let preview) = request.kind else { return XCTFail("plan attendu") }
        XCTAssertEqual(preview, "Plan\n\nContexte : créer `a.txt`.\n\n1. Écrire le fichier")
        XCTAssertFalse(replies.decide(request, .allow), "allow seul serait ignoré par Claude")

        XCTAssertTrue(replies.decide(request, .approvePlan))
        let approved = try decision(box.last)
        XCTAssertEqual(approved["behavior"] as? String, "allow")
        XCTAssertEqual(approved["updatedInput"] as? NSDictionary, input as NSDictionary)
        XCTAssertEqual(approved["updatedPermissions"] as? [NSDictionary],
                       [["type": "setMode", "mode": "acceptEdits", "destination": "session"]])

        let (second, revised) = hold(permission(tool: "ExitPlanMode", input: input))
        XCTAssertTrue(replies.decide(second, .revisePlan("Ajoute des tests")))
        XCTAssertEqual(try decision(revised.last) as NSDictionary, ["behavior": "deny", "message": "Ajoute des tests"])
    }

    // MARK: - Échéances

    func testGraceDelayWithoutCard() {
        let (_, box) = hold(permission())
        now += 3.9
        replies.expire()
        XCTAssertTrue(box.replies.isEmpty)
        now += 0.1
        replies.expire()
        XCTAssertEqual(box.replies.count, 1)
        XCTAssertNil(box.replies[0], "204 : le terminal garde la main")
        XCTAssertNil(replies.notices["s1"], "carte jamais vue : rien à signaler")
    }

    func testEngagedCardWaitsUnderHookTimeout() {
        let (request, box) = hold(permission())
        now += 2
        replies.engage(request.id)
        now += 500
        replies.expire()
        XCTAssertTrue(box.replies.isEmpty)
        now = request.received.addingTimeInterval(ReplyCenter.engagedDelay)
        replies.expire()
        XCTAssertEqual(box.replies.count, 1)
        XCTAssertNil(box.replies[0])
        XCTAssertEqual(replies.notices["s1"]?.tone, .warning)
        XCTAssertLessThan(ReplyCenter.engagedDelay, 600, "sous le timeout du hook")
    }

    // MARK: - Fin de la demande sans clic

    func testReleasedWhenTheToolRunsOrTheTurnMoves() {
        let (_, box) = hold(permission())
        // Autre session, autre commande : rien.
        replies.observe(HookEvent(raw: ["hook_event_name": "PostToolUse", "session_id": "s2", "tool_name": "Bash",
                                        "tool_input": ["command": "rm -rf build", "description": "Supprime build"]]))
        replies.observe(HookEvent(raw: ["hook_event_name": "PostToolUse", "session_id": "s1", "tool_name": "Bash",
                                        "tool_input": ["command": "ls"]]))
        XCTAssertTrue(box.replies.isEmpty)
        // Oui au terminal : l'outil a tourné.
        replies.observe(HookEvent(raw: ["hook_event_name": "PostToolUse", "session_id": "s1", "tool_name": "Bash",
                                        "tool_input": ["command": "rm -rf build", "description": "Supprime build"]]))
        XCTAssertEqual(box.replies.count, 1)
        XCTAssertNil(box.replies[0])

        let (_, stopped) = hold(permission())
        replies.observe(HookEvent(raw: ["hook_event_name": "Stop", "session_id": "s1"]))
        XCTAssertEqual(stopped.replies.count, 1)

        let (request, closed) = hold(permission())
        replies.engage(request.id)
        replies.connectionClosed(request.id)
        XCTAssertTrue(closed.replies.isEmpty, "connexion fermée : plus personne à qui répondre")
        XCTAssertTrue(replies.requests.isEmpty)
        XCTAssertEqual(replies.notices["s1"]?.tone, .info)
    }

    // MARK: - Messages

    func testOneWaiterPerSessionAndFIFOQueue() {
        let first = Box<String>()
        let second = Box<String>()
        replies.wait(sessionId: "s1", pid: nil) { first.replies.append($0) }
        XCTAssertEqual(replies.waiting, ["s1"])
        replies.wait(sessionId: "s1", pid: nil) { second.replies.append($0) }
        XCTAssertEqual(first.replies.count, 1)
        XCTAssertNil(first.replies[0], "la nouvelle attente ferme l'ancienne (204)")

        XCTAssertEqual(replies.send("  Lance les tests  ", to: "s1"), .delivered)
        XCTAssertEqual(second.replies, ["Lance les tests"])
        XCTAssertTrue(replies.waiting.isEmpty)

        // Sans attente : en file, dans l'ordre, remis aux attentes suivantes.
        XCTAssertEqual(replies.send("un", to: "s1"), .queued)
        XCTAssertEqual(replies.send("deux", to: "s1"), .queued)
        XCTAssertNil(replies.send(" \n\t ", to: "s1"), "message vide")
        XCTAssertEqual(replies.queued["s1"], ["un", "deux"])
        let third = Box<String>()
        replies.wait(sessionId: "s1", pid: nil) { third.replies.append($0) }
        XCTAssertEqual(third.replies, ["un"])
        XCTAssertTrue(replies.waiting.isEmpty, "remise immédiate : l'attente est consommée")
        let fourth = Box<String>()
        replies.wait(sessionId: "s1", pid: nil) { fourth.replies.append($0) }
        XCTAssertEqual(fourth.replies, ["deux"])
        XCTAssertNil(replies.queued["s1"])

        let fifth = Box<String>()
        replies.wait(sessionId: "s1", pid: nil) { fifth.replies.append($0) }
        replies.connectionClosed(UUID())
        XCTAssertEqual(replies.waiting, ["s1"], "identifiant inconnu : rien")
    }

    func testQueueIsBoundedAndCanBeDropped() {
        for index in 0..<ReplyCenter.maxQueuedPerSession {
            XCTAssertEqual(replies.send("m\(index)", to: "s1"), .queued)
        }
        XCTAssertNil(replies.send("de trop", to: "s1"))
        XCTAssertEqual(replies.queued["s1"]?.count, ReplyCenter.maxQueuedPerSession)
        replies.dropQueue("s1")
        XCTAssertNil(replies.queued["s1"])
    }

    func testSessionEndClosesWaiterAndQueue() {
        let waited = Box<String>()
        replies.wait(sessionId: "s1", pid: nil) { waited.replies.append($0) }
        replies.send("x", to: "s2")
        replies.observe(HookEvent(raw: ["hook_event_name": "SessionEnd", "session_id": "s1"]))
        replies.observe(HookEvent(raw: ["hook_event_name": "SessionEnd", "session_id": "s2"]))
        XCTAssertEqual(waited.replies.count, 1)
        XCTAssertNil(waited.replies[0])
        XCTAssertTrue(replies.waiting.isEmpty)
        XCTAssertTrue(replies.queued.isEmpty)
    }

    /// Claude meurt (plantage) : son attente orpheline est fermée par kqueue, sans scrutation.
    func testWaiterClosedWhenClaudeProcessExits() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["30"]
        try process.run()
        let waited = Box<String>()
        replies.wait(sessionId: "s1", pid: process.processIdentifier) { waited.replies.append($0) }
        replies.send("perdu", to: "s9")
        XCTAssertEqual(replies.waiting, ["s1"])
        process.terminate()
        let deadline = Date().addingTimeInterval(5)
        while waited.replies.isEmpty, Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        XCTAssertEqual(waited.replies.count, 1)
        XCTAssertNil(waited.replies[0])
        XCTAssertTrue(replies.waiting.isEmpty)

        // PID déjà mort : l'attente est refusée tout de suite.
        process.waitUntilExit()
        let late = Box<String>()
        replies.wait(sessionId: "s1", pid: process.processIdentifier) { late.replies.append($0) }
        XCTAssertEqual(late.replies.count, 1)
        XCTAssertNil(late.replies[0])
    }

    func testSanitizeRemovesControlsAndCapsSize() {
        XCTAssertEqual(ReplyCenter.sanitize("a\u{1B}[2J\u{7}b\r\nc\rd\u{2028}e\tf\u{0}"), "a[2Jb\nc\nd\ne\tf")
        XCTAssertEqual(ReplyCenter.sanitize("  \n "), "")

        let long = String(repeating: "é日本😀x", count: 400)
        let capped = ReplyCenter.sanitize(long)
        XCTAssertLessThanOrEqual(capped.utf8.count, ReplyCenter.maxMessageBytes)
        XCTAssertGreaterThan(capped.utf8.count, ReplyCenter.maxMessageBytes - 12)
        XCTAssertTrue(capped.hasSuffix("…"))
        XCTAssertTrue(long.hasPrefix(String(capped.dropLast())), "aucun caractère coupé")
        XCTAssertEqual(replies.send(long, to: "s1"), .queued)
        XCTAssertEqual(replies.queued["s1"]?.first, capped)
    }

    func testDebugInfoHasCountsOnly() {
        hold(permission())
        replies.send("secret", to: "s1")
        let info = replies.debugInfo
        XCTAssertEqual(info["pending"] as? Int, 1)
        XCTAssertEqual(info["queued"] as? Int, 1)
        let text = String(describing: info)
        XCTAssertFalse(text.contains("secret") || text.contains("rm -rf"), "aucun contenu dans /state")
    }

    // MARK: - Session

    /// Le message réveille Claude comme un `<task-notification>` : la carte montre le message, pas « agent ».
    func testNotchMessagePromptAndResolvedAttention() {
        let store = SessionStore()
        let prompt = "<task-notification>\n<summary>\(HookInstaller.rewakeSummary)</summary>\n</task-notification>\n"
            + "<system-reminder>\n\(HookInstaller.rewakeMessage)  Lance les tests\nsuite\n</system-reminder>"
        store.send("UserPromptSubmit", "s1", ["prompt": prompt])
        XCTAssertEqual(store.sessions["s1"]?.lastPrompt, "Lance les tests")
        store.send("UserPromptSubmit", "s2", ["prompt": "<task-notification>\n<summary>Agent fini</summary>"])
        XCTAssertEqual(store.sessions["s2"]?.lastPrompt, "résultat d'un agent en arrière-plan")

        store.send("PreToolUse", "s1", ["tool_name": "Bash", "tool_use_id": "t1", "tool_input": ["command": "make"]])
        store.send("PermissionRequest", "s1", ["tool_name": "Bash", "tool_input": ["command": "make"]])
        XCTAssertEqual(store.sessions["s1"]?.phase, .waitingPermission)
        store.resolveAttention("s1", allowed: true)
        XCTAssertEqual(store.sessions["s1"]?.phase, .tool)
        XCTAssertNil(store.sessions["s1"]?.attentionText)

        store.send("PreToolUse", "s2", ["tool_name": "Bash", "tool_use_id": "t2", "tool_input": ["command": "rm x"]])
        store.send("PermissionRequest", "s2", ["tool_name": "Bash", "tool_input": ["command": "rm x"]])
        store.resolveAttention("s2", allowed: false)
        XCTAssertEqual(store.sessions["s2"]?.phase, .thinking)
        XCTAssertTrue(store.sessions["s2"]?.activeTools.isEmpty ?? false, "l'outil refusé ne tournera pas")
    }

    /// Le module relie la décision à la session.
    func testModuleDecisionUpdatesSession() {
        let store = SessionStore()
        let config = FileManager.default.temporaryDirectory.appendingPathComponent("claude-notch-no-config")
        let module = ClaudeModule(store: store, monitor: ClaudeMonitor(), tools: ToolsFeed(paths: LayoutTests.absentPaths),
                                  prefs: prefs, hooks: HookSetup(installer: HookInstaller(configDirectory: config,
                                                                                        bundledHook: nil)),
                                  replies: replies)
        store.send("PreToolUse", "s1", ["tool_name": "Bash", "tool_use_id": "t1", "tool_input": ["command": "make"]])
        store.send("PermissionRequest", "s1", ["tool_name": "Bash", "tool_input": ["command": "make"]])
        let (request, box) = hold(permission(input: ["command": "make"]))
        module.drafts.texts[ReplyDrafts.key(request.id)] = "brouillon"
        module.decide(request, .allow)
        XCTAssertEqual(box.replies.count, 1)
        XCTAssertEqual(store.sessions["s1"]?.phase, .tool)
        XCTAssertTrue(module.drafts.texts.isEmpty, "saisie de la demande oubliée")
    }
}
