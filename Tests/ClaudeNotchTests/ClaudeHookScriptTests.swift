import Foundation
import XCTest
@testable import ClaudeNotch

/// Le vrai hooks/claude-notch-hook.sh (sh et curl du système) contre un serveur de hooks de test : HOME jetable
/// (le jeton y est écrit), port de test (`CLAUDE_NOTCH_PORT`). Aucune vraie session Claude, rien d'installé.
final class ClaudeHookScriptTests: XCTestCase {
    private static let script = repositoryRoot.appendingPathComponent("hooks/claude-notch-hook.sh")

    private let permission: [String: Any] = [
        "hook_event_name": "PermissionRequest", "session_id": "s1", "tool_name": "Bash",
        "tool_input": ["command": "rm -rf build", "description": "Supprime build"], "permission_mode": "default",
    ]
    private let stop: [String: Any] = ["hook_event_name": "Stop", "session_id": "s1",
                                       "last_assistant_message": "Fini « é »"]

    /// Processus du script, sorties lues à la fin.
    final class Run {
        let process = Process()
        private let out = Pipe()
        private let err = Pipe()
        private(set) var stdout = ""
        private(set) var stderr = ""
        let started = Date()

        init(mode: String?, payload: [String: Any], home: URL, port: UInt16) throws {
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = [ClaudeHookScriptTests.script.path] + (mode.map { [$0] } ?? [])
            process.environment = ["HOME": home.path, "CLAUDE_NOTCH_PORT": String(port), "PATH": "/usr/bin:/bin",
                                   "TMPDIR": home.path]
            let input = Pipe()
            process.standardInput = input
            process.standardOutput = out
            process.standardError = err
            try process.run()
            input.fileHandleForWriting.write(try JSONSerialization.data(withJSONObject: payload))
            try input.fileHandleForWriting.close()
        }

        /// Attend la fin (boucle principale active : le serveur passe par elle), puis lit les sorties.
        @discardableResult
        func finish(timeout: TimeInterval = 10) -> Bool {
            guard spin(timeout: timeout, until: { !process.isRunning }) else { return false }
            stdout = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            stderr = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            return true
        }

        var status: Int32 { process.terminationStatus }
        var duration: TimeInterval { Date().timeIntervalSince(started) }
    }

    private func run(_ mode: String?, _ payload: [String: Any], _ fixture: ReplyServerFixture) throws -> Run {
        try Run(mode: mode, payload: payload, home: fixture.home, port: fixture.port)
    }

    // MARK: - permission

    func testPermissionDecisionGoesToStdout() throws {
        let fixture = try ReplyServerFixture(self)
        let hook = try run("permission", permission, fixture)
        XCTAssertTrue(spin { fixture.replies.requests.count == 1 }, "le hook tient sa requête")
        let request = try XCTUnwrap(fixture.replies.requests.first)
        guard case .permission(let summary) = request.kind else { return XCTFail("permission attendue") }
        XCTAssertEqual(summary.detail, "rm -rf build")
        XCTAssertTrue(hook.process.isRunning)

        fixture.replies.engage(request.id)
        XCTAssertTrue(fixture.replies.decide(request, .deny("Pas sur ce dépôt")))
        XCTAssertTrue(hook.finish())
        XCTAssertEqual(hook.status, 0)
        let output = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(hook.stdout.utf8)) as? NSDictionary)
        XCTAssertEqual(output, ["hookSpecificOutput": ["hookEventName": "PermissionRequest",
                                                       "decision": ["behavior": "deny", "message": "Pas sur ce dépôt"]]])
        XCTAssertEqual(hook.stderr, "")
    }

    func testPermissionWithoutDecisionLeavesTheTerminal() throws {
        let fixture = try ReplyServerFixture(self)
        let hook = try run("permission", permission, fixture)
        XCTAssertTrue(spin { fixture.replies.requests.count == 1 })
        fixture.replies.expire(now: Date().addingTimeInterval(ReplyCenter.graceDelay))
        XCTAssertTrue(hook.finish())
        XCTAssertEqual(hook.status, 0)
        XCTAssertEqual(hook.stdout, "", "aucune décision : le dialogue du terminal décide")

        // Réglage coupé : le hook rend la main tout de suite.
        fixture.prefs.replyFromNotch = false
        let off = try run("permission", permission, fixture)
        XCTAssertTrue(off.finish(timeout: 3))
        XCTAssertEqual(off.stdout, "")
        XCTAssertLessThan(off.duration, 2)
    }

    /// App arrêtée ou jamais lancée : sortie immédiate, rien sur stdout (jamais d'autorisation par défaut).
    func testPermissionWithoutAppFailsOpen() throws {
        let fixture = try ReplyServerFixture(self)
        fixture.server.stop()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        let stopped = try run("permission", permission, fixture)
        XCTAssertTrue(stopped.finish(timeout: 3))
        XCTAssertEqual(stopped.stdout, "")
        XCTAssertNotEqual(stopped.status, 2, "2 bloquerait")
        XCTAssertLessThan(stopped.duration, 2)

        let neverRan = try Run(mode: "permission", payload: permission, home: try makeTemporaryDirectory(self),
                               port: fixture.port)
        XCTAssertTrue(neverRan.finish(timeout: 3))
        XCTAssertEqual(neverRan.status, 0, "pas de fichier de jeton")
        XCTAssertEqual(neverRan.stdout, "")
    }

    /// « No » au terminal : Claude tue le hook (SIGTERM). Avec `exec curl`, la connexion se ferme, la carte part.
    func testTerminalAnswerKillsTheHook() throws {
        let fixture = try ReplyServerFixture(self)
        let hook = try run("permission", permission, fixture)
        XCTAssertTrue(spin { fixture.replies.requests.count == 1 })
        hook.process.terminate()
        XCTAssertTrue(hook.finish())
        XCTAssertTrue(spin { fixture.replies.requests.isEmpty }, "connexion fermée vue par l'app")
    }

    // MARK: - inbox

    func testInboxMessageWakesClaude() throws {
        let fixture = try ReplyServerFixture(self)
        let hook = try run("inbox", stop, fixture)
        XCTAssertTrue(spin { fixture.replies.waiting == ["s1"] })
        let message = "Ajoute aussi un test « $HOME » `x` \\ 😀\nDeuxième ligne"
        XCTAssertEqual(fixture.replies.send(message, to: "s1"), .delivered)
        XCTAssertTrue(hook.finish())
        XCTAssertEqual(hook.status, 2, "code 2 : asyncRewake réveille Claude")
        XCTAssertEqual(hook.stderr, message)
        XCTAssertEqual(hook.stdout, "")
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: fixture.home.path)
            .filter { $0.hasPrefix("claude-notch.") }
        XCTAssertEqual(leftovers, [], "fichiers temporaires retirés")
    }

    func testInboxEndsQuietly() throws {
        let fixture = try ReplyServerFixture(self)
        // Remplacée par une attente plus récente : 0, rien sur stderr.
        let first = try run("inbox", stop, fixture)
        XCTAssertTrue(spin { fixture.replies.waiting == ["s1"] })
        let second = try run("inbox", stop, fixture)
        XCTAssertTrue(first.finish())
        XCTAssertEqual(first.status, 0)
        XCTAssertEqual(first.stderr, "")

        // Hook arrêté (fin de session) : il sort en 0 et tue curl, l'app voit l'attente se fermer.
        XCTAssertTrue(spin { fixture.replies.waiting == ["s1"] })
        second.process.terminate()
        XCTAssertTrue(second.finish())
        XCTAssertEqual(second.status, 0)
        XCTAssertTrue(spin { fixture.replies.waiting.isEmpty })

        fixture.prefs.replyFromNotch = false
        let off = try run("inbox", stop, fixture)
        XCTAssertTrue(off.finish(timeout: 3))
        XCTAssertEqual(off.status, 0)
        XCTAssertLessThan(off.duration, 2)
    }

    /// Message envoyé sans attente connectée : il part dès l'attente suivante (Stop).
    func testQueuedMessageGoesAtNextStop() throws {
        let fixture = try ReplyServerFixture(self)
        XCTAssertEqual(fixture.replies.send("Après ce tour, lance les tests", to: "s1"), .queued)
        let hook = try run("inbox", stop, fixture)
        XCTAssertTrue(hook.finish())
        XCTAssertEqual(hook.status, 2)
        XCTAssertEqual(hook.stderr, "Après ce tour, lance les tests")
        XCTAssertNil(fixture.replies.queued["s1"])
    }

    // MARK: - Relais

    func testRelayCarriesTheToken() throws {
        let fixture = try ReplyServerFixture(self)
        let event: [String: Any] = ["hook_event_name": "PostToolUse", "session_id": "s1", "tool_name": "Bash",
                                    "tool_input": ["command": "ls"]]
        let hook = try run(nil, event, fixture)
        XCTAssertTrue(hook.finish())
        XCTAssertEqual(hook.status, 0)
        XCTAssertTrue(spin { fixture.receivedEvents.contains { $0.name == "PostToolUse" } })
    }
}
