import Darwin
import Foundation

/// Historique sur disque (réglage « garder l'historique après redémarrage », désactivé par défaut) : textes et
/// liens seulement, jamais les images, fichiers ni couleurs.
///
/// - Un seul fichier JSON en 0600, dans le dossier de l'app (injectable pour les tests).
/// - Écriture atomique (fichier temporaire 0600 créé en `O_EXCL`, puis `rename`) sur une file en arrière-plan.
/// - JSON illisible : le fichier est renommé en `.corrupt` (jamais écrasé) et l'historique repart de zéro.
final class ClipboardStorage {
    struct Record: Codable, Equatable {
        var id: UUID
        /// « text » ou « url ».
        var kind: String
        var value: String
        var date: Date
        var pinned: Bool
        var app: String?
        var appName: String?
    }

    private struct Document: Codable {
        var version = 1
        var items: [Record]
    }

    static let fileName = "clipboard-history.json"

    let url: URL
    private let queue = DispatchQueue(label: "claudenotch.clipboard.storage", qos: .utility)

    init(directory: URL = SharedFiles.notchDirectory) {
        url = directory.appendingPathComponent(Self.fileName)
    }

    /// Lecture synchrone (une fois, au premier démarrage du module). Fichier absent : vide ; illisible : renommé.
    func load() -> [Record] {
        queue.sync {
            guard let data = try? Data(contentsOf: url) else { return [] }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .secondsSince1970
            if let document = try? decoder.decode(Document.self, from: data), document.version == 1 {
                return document.items
            }
            quarantine()
            return []
        }
    }

    /// Écriture asynchrone et atomique.
    func save(_ records: [Record]) {
        queue.async { [url] in
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .secondsSince1970
            guard let data = try? encoder.encode(Document(items: records)) else { return }
            try? Self.write(data, to: url)
        }
    }

    /// Supprime le fichier, dans l'ordre des écritures déjà demandées.
    func delete() {
        queue.async { [url] in try? FileManager.default.removeItem(at: url) }
    }

    /// Attend la fin des écritures en cours (arrêt du module, fin de l'app, tests).
    func flush() {
        queue.sync {}
    }

    // MARK: Fichiers

    private func quarantine() {
        let manager = FileManager.default
        var target = url.appendingPathExtension("corrupt")
        if manager.fileExists(atPath: target.path) {
            target = url.appendingPathExtension("corrupt-\(Int(Date().timeIntervalSince1970))")
        }
        try? manager.moveItem(at: url, to: target)
    }

    private static func write(_ data: Data, to file: URL) throws {
        let directory = file.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let temporary = directory.appendingPathComponent(".\(file.lastPathComponent)-\(UUID().uuidString)")
        let fd = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        let written = data.withUnsafeBytes { Darwin.write(fd, $0.baseAddress, $0.count) }
        close(fd)
        guard written == data.count, rename(temporary.path, file.path) == 0 else {
            let code = POSIXErrorCode(rawValue: errno) ?? .EIO
            unlink(temporary.path)
            throw POSIXError(code)
        }
    }
}

extension ClipboardItem {
    /// nil : seuls les textes et les liens se gardent sur disque.
    var record: ClipboardStorage.Record? {
        let kind: String
        let value: String
        switch content {
        case .text(let text): (kind, value) = ("text", text)
        case .url(let url): (kind, value) = ("url", url.absoluteString)
        default: return nil
        }
        return ClipboardStorage.Record(id: id, kind: kind, value: value, date: date, pinned: pinned,
                                       app: source?.bundleID, appName: source?.name)
    }

    init?(record: ClipboardStorage.Record) {
        let content: ClipboardContent
        switch record.kind {
        case "text": content = .text(record.value)
        case "url": guard let url = URL(string: record.value) else { return nil }; content = .url(url)
        default: return nil
        }
        let source = record.app.map { ClipboardSource(bundleID: $0, name: record.appName ?? $0) }
        self.init(content, date: record.date, source: source, pinned: record.pinned, id: record.id)
    }
}
