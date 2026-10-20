import AppKit
import XCTest
@testable import ClaudeNotch

/// Historique sur disque : rien n'est écrit par défaut ; activé, textes et liens seulement, en 0600.
/// Tous les fichiers vont dans un dossier temporaire : jamais le vrai ~/Library/Application Support/ClaudeNotch.
final class ClipboardStorageTests: XCTestCase {
    private let manager = FileManager.default

    private func names(_ directory: URL) -> [String] {
        ((try? manager.contentsOfDirectory(atPath: directory.path)) ?? []).sorted()
    }

    private func permissions(_ url: URL) throws -> Int {
        (try manager.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)?.intValue ?? -1
    }

    // MARK: Désactivé par défaut

    func testNothingIsWrittenByDefault() throws {
        let rig = try makeClipboardRig()
        XCTAssertFalse(rig.module.keepsHistory)
        rig.copy("secret de travail")
        rig.copy(ClipboardContent.url(URL(string: "https://example.com")!))
        rig.module.togglePin(rig.items[0].id)
        rig.module.limit = 25
        rig.module.stop()
        rig.storage.flush()
        XCTAssertEqual(names(rig.directory), [], "rien sur disque quand le réglage est désactivé")
        XCTAssertFalse(manager.fileExists(atPath: rig.file.path))
    }

    func testStartingNeverReadsTheFileWhenDisabled() throws {
        let directory = try makeTemporaryDirectory(self)
        let file = directory.appendingPathComponent(ClipboardStorage.fileName)
        try Data("pas du JSON".utf8).write(to: file)
        let rig = try makeClipboardRig(directory: directory)
        XCTAssertTrue(rig.items.isEmpty)
        XCTAssertEqual(names(directory), [ClipboardStorage.fileName], "ni lu, ni renommé, ni effacé")
    }

    // MARK: Activé

    func testEnabledWritesTextAndLinksOnlyInAPrivateFile() throws {
        let directory = try makeTemporaryDirectory(self).appendingPathComponent("nouveau-dossier")
        let rig = try makeClipboardRig(keepsHistory: true, directory: directory)
        rig.copy("un texte")
        rig.copy(ClipboardContent.url(URL(string: "https://example.com/a")!), from: .safari)
        rig.copy(.image(makeTestImage()))
        rig.copy(.files([URL(fileURLWithPath: "/tmp/a.txt")]))
        rig.copy(.color("112233"))
        rig.module.togglePin(rig.items[4].id)
        rig.module.flushPersistence()

        XCTAssertEqual(try permissions(rig.file), 0o600)
        XCTAssertEqual(try permissions(directory), 0o700)
        XCTAssertEqual(names(directory), [ClipboardStorage.fileName], "aucun fichier temporaire ne reste")

        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: rig.file)) as? [String: Any])
        XCTAssertEqual(json["version"] as? Int, 1)
        let records = try XCTUnwrap(json["items"] as? [[String: Any]])
        XCTAssertEqual(records.map { $0["kind"] as? String }, ["url", "text"], "du plus récent au plus ancien")
        XCTAssertEqual(records.map { $0["value"] as? String }, ["https://example.com/a", "un texte"])
        XCTAssertEqual(records[0]["app"] as? String, "com.apple.Safari")
        XCTAssertEqual(records[1]["pinned"] as? Bool, true)
        let raw = try String(contentsOf: rig.file, encoding: .utf8)
        XCTAssertFalse(raw.contains("112233") || raw.contains("a.txt") || raw.contains("png"))
    }

    func testWritesAreDebouncedAndDoneOffTheMainThread() throws {
        let rig = try makeClipboardRig(keepsHistory: true)
        rig.copy("a")
        rig.copy("b")
        rig.copy("c")
        XCTAssertFalse(manager.fileExists(atPath: rig.file.path), "pas d'écriture synchrone à chaque copie")
        let deadline = Date().addingTimeInterval(3)
        while !manager.fileExists(atPath: rig.file.path), Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        rig.storage.flush()
        XCTAssertEqual(rig.storage.load().map(\.value), ["c", "b", "a"], "une seule écriture pour la rafale")
    }

    func testStoppingFlushesAPendingWrite() throws {
        let rig = try makeClipboardRig(keepsHistory: true)
        rig.copy("dernier")
        rig.module.stop()
        XCTAssertEqual(rig.storage.load().map(\.value), ["dernier"])
    }

    func testHistoryComesBackAfterARestartWithPinsAndOrder() throws {
        let first = try makeClipboardRig(keepsHistory: true)
        first.copy("ancien")
        first.copy("épingle")
        first.module.togglePin(first.items[0].id)
        first.copy("récent")
        first.module.stop()

        let second = try makeClipboardRig(directory: first.directory, defaults: first.defaults)
        XCTAssertTrue(second.module.keepsHistory, "le réglage est mémorisé")
        XCTAssertEqual(second.texts, ["récent", "épingle", "ancien"])
        XCTAssertEqual(second.module.history.ordered.map { $0.content.plainText }, ["épingle", "récent", "ancien"])
        XCTAssertEqual(second.items[1].source, .textEdit)
        // Les nouvelles copies s'ajoutent, un contenu déjà connu ne fait pas de doublon.
        second.copy("ancien")
        second.copy("neuf")
        XCTAssertEqual(second.texts, ["neuf", "ancien", "récent", "épingle"])
    }

    func testLoadedHistoryRespectsTheLimit() throws {
        let first = try makeClipboardRig(keepsHistory: true)
        for index in 0..<40 { first.copy("t\(index)") }
        first.module.stop()
        first.defaults.set(25, forKey: "clipboard.limit")
        let second = try makeClipboardRig(directory: first.directory, defaults: first.defaults)
        XCTAssertEqual(second.items.count, 25)
        XCTAssertEqual(second.texts.first, "t39")
    }

    // MARK: Désactiver, effacer

    func testTurningPersistenceOffDeletesTheFileAndOnWritesItAgain() throws {
        let rig = try makeClipboardRig(keepsHistory: true)
        rig.copy("a")
        rig.module.flushPersistence()
        XCTAssertTrue(manager.fileExists(atPath: rig.file.path))

        rig.module.keepsHistory = false
        rig.storage.flush()
        XCTAssertFalse(manager.fileExists(atPath: rig.file.path))
        XCTAssertEqual(rig.items.count, 1, "la mémoire reste")
        rig.copy("b")
        rig.module.flushPersistence()
        XCTAssertFalse(manager.fileExists(atPath: rig.file.path), "plus rien n'est écrit")

        rig.module.keepsHistory = true
        rig.module.flushPersistence()
        XCTAssertEqual(rig.storage.load().map(\.value), ["b", "a"])
    }

    func testClearingTheHistoryDeletesTheFile() throws {
        let rig = try makeClipboardRig(keepsHistory: true)
        rig.copy("a")
        rig.module.togglePin(rig.items[0].id)
        rig.module.flushPersistence()
        XCTAssertTrue(manager.fileExists(atPath: rig.file.path))
        rig.module.clearHistory()
        rig.module.flushPersistence()
        XCTAssertFalse(manager.fileExists(atPath: rig.file.path))
        XCTAssertTrue(rig.items.isEmpty)
        rig.copy("après")
        rig.module.flushPersistence()
        XCTAssertEqual(rig.storage.load().map(\.value), ["après"])
    }

    func testRemovingAnItemUpdatesTheFile() throws {
        let rig = try makeClipboardRig(keepsHistory: true)
        rig.copy("à retirer")
        rig.copy("à garder")
        rig.module.remove(rig.items[1].id)
        rig.module.flushPersistence()
        XCTAssertEqual(rig.storage.load().map(\.value), ["à garder"])
    }

    // MARK: Fichier illisible

    func testUnreadableFileIsRenamedNotOverwrittenAndHistoryStartsEmpty() throws {
        let directory = try makeTemporaryDirectory(self)
        let file = directory.appendingPathComponent(ClipboardStorage.fileName)
        let garbage = Data("{ ceci n'est pas du JSON".utf8)
        try garbage.write(to: file)

        let rig = try makeClipboardRig(keepsHistory: true, directory: directory)
        XCTAssertTrue(rig.items.isEmpty)
        XCTAssertFalse(manager.fileExists(atPath: file.path))
        XCTAssertEqual(try Data(contentsOf: file.appendingPathExtension("corrupt")), garbage, "ancien fichier intact")

        rig.copy("nouveau")
        rig.module.flushPersistence()
        XCTAssertEqual(rig.storage.load().map(\.value), ["nouveau"])
        XCTAssertEqual(try Data(contentsOf: file.appendingPathExtension("corrupt")), garbage)
    }

    func testASecondCorruptFileDoesNotReplaceTheFirstQuarantine() throws {
        let directory = try makeTemporaryDirectory(self)
        let file = directory.appendingPathComponent(ClipboardStorage.fileName)
        try Data("un".utf8).write(to: file)
        XCTAssertEqual(ClipboardStorage(directory: directory).load(), [])
        try Data("deux".utf8).write(to: file)
        XCTAssertEqual(ClipboardStorage(directory: directory).load(), [])
        XCTAssertEqual(try String(contentsOf: file.appendingPathExtension("corrupt"), encoding: .utf8), "un")
        XCTAssertEqual(names(directory).count, 2)
        XCTAssertFalse(names(directory).contains(ClipboardStorage.fileName))
    }

    func testValidJSONOfAnotherShapeIsAlsoQuarantined() throws {
        let directory = try makeTemporaryDirectory(self)
        let file = directory.appendingPathComponent(ClipboardStorage.fileName)
        try Data(#"{"version": 2, "items": []}"#.utf8).write(to: file)
        XCTAssertEqual(ClipboardStorage(directory: directory).load(), [])
        XCTAssertTrue(manager.fileExists(atPath: file.appendingPathExtension("corrupt").path))
    }

    func testUnknownRecordsAreSkippedWithoutLosingTheOthers() throws {
        let directory = try makeTemporaryDirectory(self)
        let storage = ClipboardStorage(directory: directory)
        let good = ClipboardStorage.Record(id: UUID(), kind: "text", value: "ok", date: Date(), pinned: false)
        let odd = ClipboardStorage.Record(id: UUID(), kind: "hologramme", value: "x", date: Date(), pinned: false)
        storage.save([odd, good])
        storage.flush()
        let items = storage.load().compactMap(ClipboardItem.init(record:))
        XCTAssertEqual(items.map { $0.content.plainText }, ["ok"])
    }
}
