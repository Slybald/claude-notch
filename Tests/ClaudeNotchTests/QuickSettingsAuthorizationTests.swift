import XCTest
@testable import ClaudeNotch

/// Autorisation « sans mot de passe » de l'économie d'énergie (règle sudoers) : contenu de la règle, commandes,
/// choix entre `sudo -n` et la fenêtre d'autorisation, installation, retrait, états de l'interface.
/// Aucun test n'exécute sudo, AppleScript ou une commande privilégiée, ni n'écrit dans /etc : les accès sont des
/// doubles. Seuls `visudo -c` (lecture, sans droits) et /bin/sh (sur des `printf`) tournent pour de vrai.
final class QuickSettingsAuthorizationTests: XCTestCase {
    // MARK: - Doubles et outils

    private static func ok(_ stdout: String = "") -> SystemProcess.Output {
        SystemProcess.Output(status: 0, stdout: Data(stdout.utf8), stderr: Data(), timedOut: false)
    }

    private static func fail(_ stderr: String, status: Int32 = 1) -> SystemProcess.Output {
        SystemProcess.Output(status: status, stdout: Data(), stderr: Data(stderr.utf8), timedOut: false)
    }

    /// Remplace `SystemProcess.run` : note les appels, répond selon le programme. Appelé hors du fil principal.
    private final class ScriptedRunner {
        struct Call: Equatable {
            var path: String
            var arguments: [String]
        }

        var sudoReply: SystemProcess.Output? = QuickSettingsAuthorizationTests.ok()
        var osascriptReply: SystemProcess.Output? = QuickSettingsAuthorizationTests.ok()
        /// Appelé avec le script AppleScript, avant la réponse : le test regarde alors l'état du disque.
        var onOsascript: ((String) -> Void)?
        private let lock = NSLock()
        private var recorded: [Call] = []

        var calls: [Call] { lock.lock(); defer { lock.unlock() }; return recorded }
        var sudoCalls: [Call] { calls.filter { $0.path == LowPowerAuthorization.sudoPath } }
        var scripts: [String] { calls.filter { $0.path == "/usr/bin/osascript" }.map { $0.arguments[1] } }

        lazy var run: SystemProcess.Runner = { [self] path, arguments, _ in
            lock.lock(); recorded.append(Call(path: path, arguments: arguments)); lock.unlock()
            switch path {
            case LowPowerAuthorization.sudoPath:
                return sudoReply
            case "/usr/bin/osascript":
                onOsascript?(arguments[1])
                return osascriptReply
            default:
                return QuickSettingsAuthorizationTests.fail("programme inattendu : \(path)")
            }
        }
    }

    private func power(_ runner: ScriptedRunner, ruleInstalled: Bool = false, user: String = "alice",
                       temporaryRule: @escaping (String) throws -> URL = LowPowerAuthorization.writeTemporaryRule)
        -> SystemPowerMode {
        SystemPowerMode(run: runner.run, ruleExists: { ruleInstalled }, userName: { user }, temporaryRule: temporaryRule)
    }

    private func write(_ mode: SystemPowerMode, _ on: Bool) throws -> Result<LowPowerWrite, QuickSettingsFailure> {
        let done = expectation(description: "setLowPower")
        var outcome: Result<LowPowerWrite, QuickSettingsFailure>?
        mode.setLowPower(on) {
            XCTAssertTrue(Thread.isMainThread)
            outcome = $0
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
        return try XCTUnwrap(outcome)
    }

    private func authorize(_ mode: SystemPowerMode) throws -> Result<Void, QuickSettingsFailure> {
        let done = expectation(description: "authorize")
        var outcome: Result<Void, QuickSettingsFailure>?
        mode.authorize {
            XCTAssertTrue(Thread.isMainThread)
            outcome = $0
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
        return try XCTUnwrap(outcome)
    }

    private func revoke(_ mode: SystemPowerMode) throws -> Result<Void, QuickSettingsFailure> {
        let done = expectation(description: "revoke")
        var outcome: Result<Void, QuickSettingsFailure>?
        mode.revokeAuthorization {
            XCTAssertTrue(Thread.isMainThread)
            outcome = $0
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
        return try XCTUnwrap(outcome)
    }

    /// Relit un littéral AppleScript comme AppleScript le lit (`\\`, `\"`, `\n`, `\r`, `\t`) ; nil si le script n'a
    /// pas la forme attendue ou si un guillemet y est resté sans protection.
    private func shellCommand(inScript script: String) -> String? {
        let prefix = "do shell script \""
        let suffix = "\" with administrator privileges"
        guard script.hasPrefix(prefix), script.hasSuffix(suffix) else { return nil }
        var result = ""
        var escaping = false
        for character in script.dropFirst(prefix.count).dropLast(suffix.count) {
            if escaping {
                switch character {
                case "n": result.append("\n")
                case "r": result.append("\r")
                case "t": result.append("\t")
                case "\\", "\"": result.append(character)
                default: return nil
                }
                escaping = false
            } else if character == "\\" {
                escaping = true
            } else if character == "\"" {
                return nil
            } else {
                result.append(character)
            }
        }
        return escaping ? nil : result
    }

    private func failure(of result: Result<Void, QuickSettingsFailure>) -> QuickSettingsFailure? {
        if case .failure(let failure) = result { return failure }
        return nil
    }

    private func shell(_ command: String) throws -> SystemProcess.Output {
        try XCTUnwrap(SystemProcess.run("/bin/sh", ["-c", command], timeout: 10))
    }

    private func text(_ data: Data) -> String { String(decoding: data, as: UTF8.self) }

    /// Un dossier au nom hostile (espace, apostrophe, guillemet, barre oblique inverse, `$`, accent, accent grave).
    private func hostileTemporaryRule(_ contents: String) throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("Mon dossier d'essai \"x\" \\ $HOME `id` é \(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let file = directory.appendingPathComponent("règle d'essai")
        XCTAssertTrue(FileManager.default.createFile(atPath: file.path, contents: Data(contents.utf8),
                                                     attributes: [.posixPermissions: 0o600]))
        return file
    }

    // MARK: - Règle sudoers

    func testRuleContentsAreExact() {
        XCTAssertEqual(LowPowerAuthorization.ruleContents(forUser: "jean.dupont"), """
            # Claude Notch : active ou coupe l'economie d'energie sans demander le mot de passe.
            # Pour retirer cette autorisation : sudo rm /etc/sudoers.d/claude-notch-lowpower
            jean.dupont ALL=(root) NOPASSWD: /usr/bin/pmset -a lowpowermode 0, /usr/bin/pmset -a lowpowermode 1

            """)
    }

    /// Une seule règle, deux commandes complètes, ni joker ni autre commande.
    func testRuleAllowsExactlyTwoPmsetCommands() throws {
        let rule = try XCTUnwrap(LowPowerAuthorization.ruleContents(forUser: "alice"))
        XCTAssertTrue(rule.hasSuffix("\n"))
        XCTAssertTrue(rule.allSatisfy(\.isASCII), "lu par root : pas de caractère exotique")
        let rules = rule.components(separatedBy: "\n").filter { !$0.isEmpty && !$0.hasPrefix("#") }
        XCTAssertEqual(rules.count, 1)
        let parts = rules[0].components(separatedBy: " NOPASSWD: ")
        XCTAssertEqual(parts.count, 2)
        XCTAssertEqual(parts[0], "alice ALL=(root)")
        XCTAssertEqual(parts[1].components(separatedBy: ", "),
                       ["/usr/bin/pmset -a lowpowermode 0", "/usr/bin/pmset -a lowpowermode 1"])
        for forbidden in ["*", "ALL=(ALL", "SETENV", "!", "\\"] {
            XCTAssertFalse(rule.contains(forbidden), forbidden)
        }
    }

    /// sudo ignore les fichiers de sudoers.d dont le nom contient un point ou finit par `~`.
    func testRuleFileNameIsReadBySudo() {
        let url = URL(fileURLWithPath: LowPowerAuthorization.rulePath)
        XCTAssertEqual(url.deletingLastPathComponent().path, "/etc/sudoers.d")
        XCTAssertEqual(url.lastPathComponent, "claude-notch-lowpower")
        XCTAssertFalse(url.lastPathComponent.contains("."))
        XCTAssertFalse(url.lastPathComponent.hasSuffix("~"))
    }

    func testValidUsersAreAccepted() {
        for name in ["alice", "Jean.Dupont", "_www", "user-1", "a", "a_b-c.d", "0", String(repeating: "a", count: 64)] {
            XCTAssertTrue(LowPowerAuthorization.isValidUser(name), name)
            XCTAssertNotNil(LowPowerAuthorization.ruleContents(forUser: name), name)
        }
    }

    func testUnsafeUsersAreRefused() {
        let unsafe = [
            "", "-alice", "-", "ALL", "alice bob", "alice\nbob ALL=(ALL) NOPASSWD: ALL", "alice\n", "\nalice",
            "alice\r", "a\tb", "a#b", "#0", "%admin", "+netgroup", "!alice", "a,b", "a:b", "a=b", "a\\b", "a/b",
            "../x", "a'b", "a\"b", "a$b", "a;b", "a*b", "a(b)", "é", "alicé", "a\u{0}b",
            String(repeating: "a", count: 65),
        ]
        for name in unsafe {
            XCTAssertFalse(LowPowerAuthorization.isValidUser(name), name.debugDescription)
            XCTAssertNil(LowPowerAuthorization.ruleContents(forUser: name), name.debugDescription)
        }
    }

    /// Preuve avec le vrai `visudo -c` (lecture seule, sans droits root) : la règle générée est syntaxiquement
    /// valide, et visudo refuse bien une règle abîmée (sinon le test ne prouverait rien).
    func testGeneratedRulePassesRealVisudo() throws {
        guard FileManager.default.isExecutableFile(atPath: LowPowerAuthorization.visudoPath) else {
            throw XCTSkip("visudo absent")
        }
        var users = ["alice", "jean.dupont", "_user-1"]
        if LowPowerAuthorization.isValidUser(NSUserName()) { users.append(NSUserName()) }
        for user in users {
            let file = try LowPowerAuthorization.writeTemporaryRule(try XCTUnwrap(
                LowPowerAuthorization.ruleContents(forUser: user)))
            defer { LowPowerAuthorization.discardTemporaryRule(file) }
            let output = try XCTUnwrap(SystemProcess.run(LowPowerAuthorization.visudoPath, ["-cf", file.path],
                                                         timeout: 10))
            XCTAssertEqual(output.status, 0, "\(user) : \(text(output.stdout)) \(text(output.stderr))")
            XCTAssertTrue(text(output.stdout).contains("parsed OK"), text(output.stdout))
        }
        let broken = try LowPowerAuthorization.writeTemporaryRule("alice ALL=(root) NOPASSWD /usr/bin/pmset\n")
        defer { LowPowerAuthorization.discardTemporaryRule(broken) }
        let refused = try XCTUnwrap(SystemProcess.run(LowPowerAuthorization.visudoPath, ["-cf", broken.path],
                                                      timeout: 10))
        XCTAssertNotEqual(refused.status, 0)
    }

    // MARK: - Commandes

    func testSudoRunsOneFixedCommandWithoutShell() {
        XCTAssertEqual(LowPowerAuthorization.sudoArguments(lowPower: true),
                       ["-n", "/usr/bin/pmset", "-a", "lowpowermode", "1"])
        XCTAssertEqual(LowPowerAuthorization.sudoArguments(lowPower: false),
                       ["-n", "/usr/bin/pmset", "-a", "lowpowermode", "0"])
    }

    func testShellQuoteSurvivesARealShell() throws {
        let texts = ["plain", "with space", "it's", "a'b'c", "'", "''", "$HOME", "`id`", "\"dq\"", "back\\slash",
                     "new\nline", "; touch /nonexistent", "Mon dossier d'essai/règle \"x\" \\ $y", "é"]
        for original in texts {
            let output = try shell("printf %s \(LowPowerAuthorization.shellQuote(original))")
            XCTAssertEqual(text(output.stdout), original, original.debugDescription)
        }
    }

    func testAppleScriptLiteralKeepsTheCommandIntact() throws {
        let commands = ["/usr/bin/pmset -a lowpowermode 1", "a \"b\" c", "back\\slash", "\\\"", "tab\tand\nnewline\r",
                        "'quoted' path/règle \\n"]
        for command in commands {
            let script = LowPowerAuthorization.administratorScript(running: command)
            XCTAssertEqual(shellCommand(inScript: script), command, script)
        }
        XCTAssertEqual(LowPowerAuthorization.administratorScript(running: "/usr/bin/pmset -a lowpowermode 1"),
                       "do shell script \"/usr/bin/pmset -a lowpowermode 1\" with administrator privileges",
                       "le script de bascule avec mot de passe reste celui d'avant")
    }

    func testInstallCommandChecksWithVisudoBeforeInstalling() throws {
        let command = LowPowerAuthorization.installShellCommand(temporaryFile: "/tmp/x y/it's")
        XCTAssertEqual(command, "/usr/sbin/visudo -cf '/tmp/x y/it'\\''s' && /usr/bin/install -m 0440 -o root -g wheel "
            + "'/tmp/x y/it'\\''s' /etc/sudoers.d/claude-notch-lowpower")
        let visudo = try XCTUnwrap(command.range(of: "/usr/sbin/visudo"))
        let chain = try XCTUnwrap(command.range(of: " && "))
        let install = try XCTUnwrap(command.range(of: "/usr/bin/install"))
        XCTAssertTrue(visudo.lowerBound < chain.lowerBound && chain.upperBound <= install.lowerBound,
                      "visudo -c d'abord, et install seulement s'il réussit")
        XCTAssertEqual(command.components(separatedBy: "install").count, 2, "un seul install")
        XCTAssertFalse(command.contains(";"), "pas de commande qui s'exécute malgré l'échec de visudo")
    }

    /// Exécute pour de vrai la chaîne `visudo … && install …`, mais avec `install` remplacé par un `printf` : rien
    /// n'est installé. Fichier valide : visudo réussit, la suite s'exécute. Fichier invalide : elle ne s'exécute pas.
    func testInstallIsSkippedWhenVisudoRefusesTheFile() throws {
        guard FileManager.default.isExecutableFile(atPath: LowPowerAuthorization.visudoPath) else {
            throw XCTSkip("visudo absent")
        }
        func dryRun(_ file: URL) throws -> SystemProcess.Output {
            let command = LowPowerAuthorization.installShellCommand(temporaryFile: file.path)
                .replacingOccurrences(of: LowPowerAuthorization.installPath, with: "/usr/bin/printf INSTALLED #")
            XCTAssertFalse(command.contains(LowPowerAuthorization.installPath), "l'installation réelle est retirée")
            return try shell(command)
        }
        let good = try hostileTemporaryRule(try XCTUnwrap(LowPowerAuthorization.ruleContents(forUser: "alice")))
        defer { LowPowerAuthorization.discardTemporaryRule(good) }
        let accepted = try dryRun(good)
        XCTAssertEqual(accepted.status, 0, text(accepted.stderr))
        XCTAssertTrue(text(accepted.stdout).hasSuffix("INSTALLED"), text(accepted.stdout))

        let bad = try hostileTemporaryRule("alice ALL=(root) NOPASSWD /usr/bin/pmset\n")
        defer { LowPowerAuthorization.discardTemporaryRule(bad) }
        let refused = try dryRun(bad)
        XCTAssertNotEqual(refused.status, 0)
        XCTAssertFalse(text(refused.stdout).contains("INSTALLED"), "install ne tourne pas si visudo refuse")
    }

    func testTemporaryRuleIsPrivateAndRemovedAfterwards() throws {
        let file = try LowPowerAuthorization.writeTemporaryRule("contenu\n")
        let directory = file.deletingLastPathComponent()
        func mode(_ url: URL) throws -> Int {
            try XCTUnwrap(FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int)
        }
        XCTAssertEqual(try mode(file), 0o600)
        XCTAssertEqual(try mode(directory), 0o700)
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "contenu\n")
        XCTAssertNotEqual(directory.path, NSTemporaryDirectory(), "un dossier à part, pas le dossier temporaire commun")
        LowPowerAuthorization.discardTemporaryRule(file)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }

    // MARK: - Bascule : sudo -n, puis repli sur la fenêtre d'autorisation

    func testWithoutARuleTheSystemPromptIsUsedLikeBefore() throws {
        let runner = ScriptedRunner()
        let mode = power(runner)
        XCTAssertEqual(mode.authorization, .none)
        XCTAssertEqual(try write(mode, true), .success(.done))
        XCTAssertEqual(try write(mode, false), .success(.done))
        XCTAssertTrue(runner.sudoCalls.isEmpty, "sans règle, sudo n'est pas essayé")
        XCTAssertEqual(runner.scripts, [
            "do shell script \"/usr/bin/pmset -a lowpowermode 1\" with administrator privileges",
            "do shell script \"/usr/bin/pmset -a lowpowermode 0\" with administrator privileges",
        ])
    }

    func testWithTheRuleNoPromptIsShown() throws {
        let runner = ScriptedRunner()
        let mode = power(runner, ruleInstalled: true)
        XCTAssertEqual(mode.authorization, .granted)
        XCTAssertEqual(try write(mode, true), .success(.done))
        XCTAssertEqual(try write(mode, false), .success(.done))
        XCTAssertEqual(runner.calls, [
            .init(path: "/usr/bin/sudo", arguments: ["-n", "/usr/bin/pmset", "-a", "lowpowermode", "1"]),
            .init(path: "/usr/bin/sudo", arguments: ["-n", "/usr/bin/pmset", "-a", "lowpowermode", "0"]),
        ], "deux bascules, aucune fenêtre d'autorisation")
        XCTAssertEqual(mode.authorization, .granted)
    }

    func testRuleRefusedBySudoFallsBackToThePasswordThenStopsTrying() throws {
        let runner = ScriptedRunner()
        runner.sudoReply = Self.fail("sudo: a password is required")
        let mode = power(runner, ruleInstalled: true)

        XCTAssertEqual(try write(mode, true), .success(.authorizationRefused), "réussi, mais avec le mot de passe")
        XCTAssertEqual(runner.calls.map(\.path), ["/usr/bin/sudo", "/usr/bin/osascript"])
        XCTAssertEqual(runner.scripts, ["do shell script \"/usr/bin/pmset -a lowpowermode 1\" with administrator privileges"])
        XCTAssertEqual(mode.authorization, .refused)

        XCTAssertEqual(try write(mode, false), .success(.done))
        XCTAssertEqual(runner.calls.map(\.path), ["/usr/bin/sudo", "/usr/bin/osascript", "/usr/bin/osascript"],
                       "sudo n'est plus essayé tant que la règle n'est pas redonnée")
    }

    func testReGrantingTheRuleMakesSudoUsableAgain() throws {
        let runner = ScriptedRunner()
        runner.sudoReply = Self.fail("sudo: a password is required")
        let mode = power(runner, ruleInstalled: true)
        _ = try write(mode, true)
        XCTAssertEqual(mode.authorization, .refused)

        runner.sudoReply = Self.ok()
        XCTAssertNoThrow(try authorize(mode).get())
        XCTAssertEqual(mode.authorization, .granted)
        let before = runner.sudoCalls.count
        XCTAssertEqual(try write(mode, false), .success(.done))
        XCTAssertEqual(runner.sudoCalls.count, before + 1)
    }

    func testSudoThatCannotStartFallsBackToo() throws {
        let runner = ScriptedRunner()
        runner.sudoReply = nil
        let mode = power(runner, ruleInstalled: true)
        XCTAssertEqual(try write(mode, true), .success(.authorizationRefused))
        XCTAssertEqual(mode.authorization, .refused)
    }

    /// La fenêtre d'autorisation fermée ne prouve rien contre la règle : on la garde, sans bruit.
    func testClosingThePromptAfterARefusedRuleKeepsTheRule() throws {
        let runner = ScriptedRunner()
        runner.sudoReply = Self.fail("sudo: a password is required")
        runner.osascriptReply = Self.fail("0:60: execution error: User canceled. (-128)")
        let mode = power(runner, ruleInstalled: true)
        XCTAssertEqual(try write(mode, true), .failure(QuickSettingsFailure(.cancelled)))
        XCTAssertEqual(mode.authorization, .granted)
    }

    func testWrongPasswordFailureIsPassedOn() throws {
        let runner = ScriptedRunner()
        runner.osascriptReply = Self.fail("execution error: The administrator user name or password was incorrect. (-60005)")
        let result = try write(power(runner), true)
        guard case .failure(let failure) = result else { return XCTFail("\(result)") }
        XCTAssertEqual(failure.kind, .denied)
    }

    // MARK: - Installation

    func testInstallRunsOneAdministratorScriptThenCleansUp() throws {
        let runner = ScriptedRunner()
        var seenAtPromptTime: (exists: Bool, mode: Int?, contents: String?)?
        var path = ""
        let mode = power(runner, user: "alice", temporaryRule: { [self] contents in
            let file = try hostileTemporaryRule(contents)
            path = file.path
            return file
        })
        runner.onOsascript = { _ in
            let attributes = try? FileManager.default.attributesOfItem(atPath: path)
            seenAtPromptTime = (FileManager.default.fileExists(atPath: path), attributes?[.posixPermissions] as? Int,
                                try? String(contentsOfFile: path, encoding: .utf8))
        }

        XCTAssertNoThrow(try authorize(mode).get())

        XCTAssertEqual(runner.calls.count, 1, "un seul mot de passe : un seul script")
        XCTAssertTrue(runner.sudoCalls.isEmpty)
        let script = try XCTUnwrap(runner.scripts.first)
        let command = try XCTUnwrap(shellCommand(inScript: script), script)
        XCTAssertEqual(command, LowPowerAuthorization.installShellCommand(temporaryFile: path))
        XCTAssertEqual(command.components(separatedBy: LowPowerAuthorization.shellQuote(path)).count, 3,
                       "le chemin entre apostrophes, deux fois (visudo et install)")
        XCTAssertEqual(seenAtPromptTime?.exists, true)
        XCTAssertEqual(seenAtPromptTime?.mode, 0o600)
        XCTAssertEqual(seenAtPromptTime?.contents, LowPowerAuthorization.ruleContents(forUser: "alice"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: path), "fichier temporaire supprimé")
        XCTAssertFalse(FileManager.default.fileExists(atPath: (path as NSString).deletingLastPathComponent),
                       "et son dossier")

        // Le shell reçoit bien chaque chemin comme UN argument, malgré l'espace, l'apostrophe, le guillemet, `$`…
        let dryRun = command
            .replacingOccurrences(of: LowPowerAuthorization.visudoPath, with: "/usr/bin/printf '[%s]'")
            .replacingOccurrences(of: LowPowerAuthorization.installPath, with: "/usr/bin/printf '[%s]'")
        let output = try shell(dryRun)
        XCTAssertEqual(text(output.stdout), "[-cf][\(path)][-m][0440][-o][root][-g][wheel][\(path)]"
            + "[/etc/sudoers.d/claude-notch-lowpower]")
    }

    func testInstallIsRefusedForAnUnsafeUserBeforeAnythingIsWritten() throws {
        let runner = ScriptedRunner()
        var wroteSomething = false
        let mode = power(runner, user: "alice\nmallory ALL=(ALL) NOPASSWD: ALL", temporaryRule: { contents in
            wroteSomething = true
            return try LowPowerAuthorization.writeTemporaryRule(contents)
        })
        let result = try authorize(mode)
        XCTAssertEqual(failure(of: result), QuickSettingsFailure(.invalidUser))
        XCTAssertFalse(wroteSomething)
        XCTAssertTrue(runner.calls.isEmpty, "ni script ni mot de passe")
    }

    func testInstallFailuresAreClassifiedAndLeaveNoTemporaryFile() throws {
        let cases: [(stderr: String, kind: QuickSettingsFailure.Kind)] = [
            ("0:60: execution error: User canceled. (-128)", .cancelled),
            ("execution error: The administrator user name or password was incorrect. (-60005)", .denied),
            ("/tmp/x:1:30: syntax error\nexecution error: boom (1)", .failed),
        ]
        for (stderr, kind) in cases {
            let runner = ScriptedRunner()
            runner.osascriptReply = Self.fail(stderr)
            var created: URL?
            let mode = power(runner, temporaryRule: { [self] contents in
                let file = try hostileTemporaryRule(contents)
                created = file
                return file
            })
            let result = try authorize(mode)
            guard case .failure(let failure) = result else { return XCTFail("\(result)") }
            XCTAssertEqual(failure.kind, kind, stderr)
            XCTAssertFalse(FileManager.default.fileExists(atPath: try XCTUnwrap(created).path), stderr)
        }
    }

    func testInstallFailsCleanlyWhenTheTemporaryFileCannotBeWritten() throws {
        struct Boom: Error {}
        let runner = ScriptedRunner()
        let mode = power(runner, temporaryRule: { _ in throw Boom() })
        XCTAssertEqual(failure(of: try authorize(mode)), QuickSettingsFailure(.failed))
        XCTAssertTrue(runner.calls.isEmpty)
    }

    // MARK: - Retrait

    func testRemovalRunsOneAdministratorCommandThatOnlyRemovesTheRule() throws {
        let runner = ScriptedRunner()
        let mode = power(runner, ruleInstalled: true)
        XCTAssertNoThrow(try revoke(mode).get())
        XCTAssertEqual(runner.calls.count, 1)
        XCTAssertEqual(runner.scripts, [
            "do shell script \"/bin/rm -f /etc/sudoers.d/claude-notch-lowpower\" with administrator privileges",
        ])
    }

    func testRemovalFailureIsReported() throws {
        let runner = ScriptedRunner()
        runner.osascriptReply = Self.fail("0:60: execution error: User canceled. (-128)")
        let result = try revoke(power(runner, ruleInstalled: true))
        guard case .failure(let failure) = result else { return XCTFail("\(result)") }
        XCTAssertEqual(failure.kind, .cancelled)
    }

    /// Pour la désinstallation de l'app : rien à retirer, rien n'est demandé.
    func testUninstallHookOnlyPromptsWhenTheRuleExists() {
        let fake = QSFakePower()
        var results: [Result<Void, QuickSettingsFailure>] = []
        LowPowerAuthorization.remove(power: fake, isInstalled: { false }) { results.append($0) }
        XCTAssertEqual(fake.revokeCalls, 0)
        XCTAssertEqual(results.count, 1)

        fake.authorization = .granted
        LowPowerAuthorization.remove(power: fake, isInstalled: { true }) { results.append($0) }
        XCTAssertEqual(fake.revokeCalls, 1)
        XCTAssertEqual(fake.authorization, .none)
        XCTAssertEqual(results.count, 2)
    }

    func testAuthorizationStateFollowsTheRuleFile() {
        var installed = false
        let mode = SystemPowerMode(run: ScriptedRunner().run, ruleExists: { installed })
        XCTAssertEqual(mode.authorization, .none)
        installed = true
        XCTAssertEqual(mode.authorization, .granted)
    }

    func testUninstallScriptRemovesTheRule() throws {
        let script = try String(contentsOf: repositoryRoot.appendingPathComponent("scripts/uninstall.sh"), encoding: .utf8)
        XCTAssertTrue(script.contains(LowPowerAuthorization.rulePath))
        XCTAssertTrue(script.contains("sudo /bin/rm -f \"$LOWPOWER_RULE\""), "retrait avec sudo")
        XCTAssertTrue(script.contains("if [ -e \"$LOWPOWER_RULE\" ]"), "seulement si le fichier existe")
    }

    // MARK: - États de l'interface

    func testInterfaceStates() {
        XCTAssertTrue(QuickSettingsView.asksPassword(.none))
        XCTAssertTrue(QuickSettingsView.asksPassword(.refused))
        XCTAssertFalse(QuickSettingsView.asksPassword(.granted), "ni cadenas ni note de pied")

        typealias Action = QuickSettingsSettingsView.AuthorizationAction
        XCTAssertEqual(QuickSettingsSettingsView.authorizationActions(.none), [Action.grant])
        XCTAssertEqual(QuickSettingsSettingsView.authorizationActions(.granted), [Action.revoke])
        XCTAssertEqual(QuickSettingsSettingsView.authorizationActions(.refused), [Action.regrant, Action.revoke])

        XCTAssertEqual(QuickSettingsSettingsView.authorizationState(.none), "Mot de passe demandé à chaque fois")
        XCTAssertEqual(QuickSettingsSettingsView.authorizationState(.granted), "Autorisé sans mot de passe")
        XCTAssertEqual(Action.grant.title, "Ne plus demander le mot de passe")
        XCTAssertEqual(Action.revoke.title, "Retirer l'autorisation")
        XCTAssertEqual(QuickSettingsSettingsView.authorizationNote,
                       "Ajoute une règle système limitée à l'activation et la désactivation de l'économie d'énergie.")
    }
}

/// Le module face à l'autorisation : état lu, pose, retrait, erreurs, règle refusée par sudo. Doubles seulement.
final class QuickSettingsAuthorizationModuleTests: XCTestCase {
    private func settle() { QuickSettingsFixture.settle() }

    func testAuthorizationIsReadAtStartAndWhenTheTabAppears() {
        let f = QuickSettingsFixture(self)
        f.power.authorization = .granted
        f.module.start()
        XCTAssertEqual(f.module.authorization, .granted)
        // La règle est retirée hors de l'app (script de désinstallation, retrait à la main).
        f.power.authorization = .none
        f.module.viewAppeared()
        XCTAssertEqual(f.module.authorization, .none)
        f.power.authorization = .granted
        f.module.refreshAuthorization()
        XCTAssertEqual(f.module.authorization, .granted)
    }

    func testGrantingPutsTheRuleInPlaceWithoutAnyError() {
        let f = QuickSettingsFixture(self)
        f.startAndShow()
        f.module.grantLowPowerAuthorization()
        XCTAssertEqual(f.power.authorizeCalls, 1)
        XCTAssertEqual(f.module.authorization, .granted)
        XCTAssertFalse(f.module.busy.contains(.authorization))
        XCTAssertNil(f.module.issue)
    }

    func testRevokingPutsThePasswordBack() {
        let f = QuickSettingsFixture(self)
        f.power.authorization = .granted
        f.startAndShow()
        f.module.revokeLowPowerAuthorization()
        XCTAssertEqual(f.power.revokeCalls, 1)
        XCTAssertEqual(f.module.authorization, .none)
        XCTAssertNil(f.module.issue)
    }

    func testClosingThePromptIsNotAnError() {
        let f = QuickSettingsFixture(self)
        f.power.authorizeFailure = QuickSettingsFailure(.cancelled)
        f.startAndShow()
        f.module.grantLowPowerAuthorization()
        XCTAssertEqual(f.module.authorization, .none)
        XCTAssertNil(f.module.issue)
        XCTAssertFalse(f.module.busy.contains(.authorization))
    }

    func testFailuresAreExplained() {
        let cases: [(QuickSettingsFailure, String)] = [
            (QuickSettingsFailure(.denied), "Autorisation : identifiants administrateur refusés."),
            (QuickSettingsFailure(.timeout), "Autorisation : pas de réponse à la demande d'autorisation."),
            (QuickSettingsFailure(.invalidUser), "Autorisation : nom d'utilisateur non pris en charge."),
            (QuickSettingsFailure(.failed, "boom (1)"), "Autorisation : boom (1)"),
            (QuickSettingsFailure(.failed), "Autorisation : installation impossible."),
        ]
        for (failure, message) in cases {
            let f = QuickSettingsFixture(self)
            f.power.authorizeFailure = failure
            f.startAndShow()
            f.module.grantLowPowerAuthorization()
            XCTAssertEqual(f.module.issue?.message, message)
            XCTAssertEqual(f.module.authorization, .none)
        }
        let f = QuickSettingsFixture(self)
        f.power.authorization = .granted
        f.power.revokeFailure = QuickSettingsFailure(.failed)
        f.startAndShow()
        f.module.revokeLowPowerAuthorization()
        XCTAssertEqual(f.module.issue?.message, "Autorisation : retrait impossible.")
        XCTAssertEqual(f.module.authorization, .granted, "la règle est toujours là")
    }

    func testOnlyOneAuthorizationPromptAtATime() {
        let f = QuickSettingsFixture(self)
        f.power.holdsCompletion = true
        f.startAndShow()
        f.module.grantLowPowerAuthorization()
        f.module.grantLowPowerAuthorization()
        f.module.revokeLowPowerAuthorization()
        XCTAssertEqual(f.power.authorizeCalls, 1)
        XCTAssertEqual(f.power.revokeCalls, 0)
        XCTAssertTrue(f.module.busy.contains(.authorization))
        // Pas non plus une bascule de l'économie d'énergie pendant la fenêtre de pose.
        f.module.toggleLowPower()
        XCTAssertTrue(f.power.setCalls.isEmpty)
        XCTAssertFalse(f.module.lowPower)
        f.power.release()
        XCTAssertFalse(f.module.busy.contains(.authorization))
        XCTAssertEqual(f.module.authorization, .granted)
    }

    func testGrantingIsRefusedWhileTheLowPowerPromptIsOpen() {
        let f = QuickSettingsFixture(self)
        f.power.holdsCompletion = true
        f.startAndShow()
        f.module.toggleLowPower()
        f.module.grantLowPowerAuthorization()
        XCTAssertEqual(f.power.authorizeCalls, 0)
        f.power.release()
    }

    func testTogglesWithTheRuleInPlaceStayQuiet() {
        let f = QuickSettingsFixture(self)
        f.power.authorization = .granted
        f.startAndShow()
        f.module.toggleLowPower()
        settle()
        f.module.toggleLowPower()
        settle()
        XCTAssertEqual(f.power.setCalls, [true, false])
        XCTAssertEqual(f.module.authorization, .granted)
        XCTAssertNil(f.module.issue)
    }

    /// La règle ne marche plus (autre utilisateur…) : la bascule réussit avec le mot de passe, l'état le dit (note
    /// de pied « La redonner », volet de réglages), et aucune erreur n'est affichée.
    func testARuleThatNoLongerWorksIsFlaggedButTheToggleSucceeds() {
        let f = QuickSettingsFixture(self)
        f.power.authorization = .granted
        f.power.ruleWorks = false
        f.startAndShow()
        f.module.toggleLowPower()
        settle()
        XCTAssertTrue(f.module.lowPower)
        XCTAssertEqual(f.module.authorization, .refused)
        XCTAssertNil(f.module.issue)

        f.module.grantLowPowerAuthorization()
        XCTAssertEqual(f.module.authorization, .granted)
    }

    func testScenesGoThroughTheSameWrite() {
        let f = QuickSettingsFixture(self)
        f.power.authorization = .granted
        f.startAndShow()
        f.module.applyScene(.autonomy)
        settle()
        f.module.applyScene(.presentation)
        settle()
        f.module.applyScene(.normal)
        settle()
        XCTAssertEqual(f.power.setCalls, [true, false], "Normal rend l'état d'avant : déjà coupé, rien à écrire")
        XCTAssertEqual(f.module.authorization, .granted)
        XCTAssertNil(f.module.issue)
    }
}
