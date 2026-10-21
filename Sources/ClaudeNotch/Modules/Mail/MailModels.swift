import Foundation

// Types, script AppleScript et décodage de sa réponse pour l'onglet Mail (purs, testés sans Mail).

enum MailState: Equatable {
    /// Pas encore regardé.
    case unknown
    /// Mail est fermé. Claude Notch ne le lance jamais : le script commence par vérifier qu'il tourne.
    case notRunning
    /// L'Automatisation vers Mail n'a jamais été demandée : un clic sur « Autoriser » fait poser la question.
    case needsPermission
    case denied
    /// Mail tourne mais n'a aucun compte (la boîte de réception est vide faute de compte, pas d'e-mail).
    case noAccount
    case ready
    /// Mail n'a pas répondu à temps, ou sa réponse n'est pas lisible.
    case failed
}

struct MailMessage: Identifiable, Equatable {
    /// En-tête Message-ID (RFC 822), sans chevrons.
    var id: String
    /// Nom affiché de l'expéditeur, à défaut son adresse.
    var sender: String
    var subject: String
    var date: Date

    /// `message://` est le lien que Mail comprend pour ouvrir un message ; il ne demande aucune autorisation.
    var openURL: URL? {
        guard !id.isEmpty else { return nil }
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return "<\(id)>".addingPercentEncoding(withAllowedCharacters: allowed).flatMap { URL(string: "message://\($0)") }
    }
}

struct MailReading: Equatable {
    var unread: Int
    var accounts: Int
    var messages: [MailMessage]
}

enum MailAnswer: Equatable {
    case notRunning
    case reading(MailReading)
}

enum MailScript {
    static let bundleIdentifier = "com.apple.mail"
    static let appURL = URL(fileURLWithPath: "/System/Applications/Mail.app")
    static let recordSeparator: Character = "\u{1E}"
    static let unitSeparator: Character = "\u{1F}"

    /// Argument 1 : combien de non-lus détailler (0 = seulement les compteurs, instantané).
    ///
    /// - `application id … is not running` est évalué par AppleScript lui-même, hors de tout `tell` : Mail n'est
    ///   jamais lancé et aucune autorisation n'est demandée (mesuré : Mail fermé → « false », Mail toujours fermé).
    /// - Séparateurs ASCII 30 / 31 : un objet de message ne les contient pas. L'âge est en secondes depuis la
    ///   réception (une date en texte dépendrait de la langue du Mac).
    /// - Réponse : `NOTRUNNING`, ou `OK␟non-lus␟comptes` puis un enregistrement `␞expéditeur␟objet␟âge␟Message-ID`
    ///   par message. Le script se compile ; son exécution sur une vraie boîte n'a pas été essayée (Mail était fermé).
    static let source = """
    on run argv
        set maxItems to (item 1 of argv) as integer
        if application id "com.apple.mail" is not running then return "NOTRUNNING"
        set rs to character id 30
        set us to character id 31
        set nowDate to current date
        set out to ""
        tell application id "com.apple.mail"
            with timeout of 20 seconds
                set unreadTotal to unread count of inbox
                set out to "OK" & us & unreadTotal & us & (count of accounts)
                if maxItems > 0 and unreadTotal > 0 then
                    set unreadMessages to (messages of inbox whose read status is false)
                    set shown to count of unreadMessages
                    if shown > maxItems then set shown to maxItems
                    repeat with i from 1 to shown
                        set m to item i of unreadMessages
                        set age to (nowDate - (date received of m)) as integer
                        set out to out & rs & (sender of m) & us & (subject of m) & us & age & us & (message id of m)
                    end repeat
                end if
            end timeout
        end tell
        return out
    end run
    """

    /// nil : réponse illisible.
    static func parse(_ output: String, now: Date) -> MailAnswer? {
        if output == "NOTRUNNING" { return .notRunning }
        let records = output.split(separator: recordSeparator, omittingEmptySubsequences: false)
        guard let head = records.first?.split(separator: unitSeparator, omittingEmptySubsequences: false),
              head.count == 3, head[0] == "OK", let unread = Int(head[1]), let accounts = Int(head[2]) else { return nil }
        let messages: [MailMessage] = records.dropFirst().compactMap { record in
            let fields = record.split(separator: unitSeparator, omittingEmptySubsequences: false).map(String.init)
            guard fields.count == 4, let age = Double(fields[2]) else { return nil }
            return MailMessage(id: messageID(fields[3]), sender: displayName(of: fields[0]),
                               subject: fields[1].split(whereSeparator: \.isWhitespace).joined(separator: " "),
                               date: now.addingTimeInterval(-max(0, age)))
        }
        return .reading(MailReading(unread: unread, accounts: accounts, messages: messages.sorted { $0.date > $1.date }))
    }

    /// « Prénom Nom <a@b.c> » → « Prénom Nom » ; une adresse seule reste telle quelle.
    static func displayName(of sender: String) -> String {
        let text = sender.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.hasSuffix(">"), let open = text.lastIndex(of: "<") else { return text }
        let name = text[..<open].trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "\"")))
        return name.isEmpty ? String(text[text.index(after: open)..<text.index(before: text.endIndex)]) : name
    }

    /// Mail rend l'identifiant avec ou sans chevrons selon les versions : on ne garde que le contenu.
    static func messageID(_ raw: String) -> String {
        raw.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "<>")))
    }
}
