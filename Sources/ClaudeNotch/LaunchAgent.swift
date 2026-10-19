import Combine
import Foundation

/// LaunchAgent `~/Library/LaunchAgents/io.github.slybald.claudenotch.plist` : lancement à l'ouverture de session.
/// Le dossier est injectable pour les tests.
enum LaunchAgent {
    static var label: String { AppIdentity.bundleId }
    /// Label des premières versions (scripts/install.sh).
    static var legacyLabel: String { AppIdentity.legacyBundleId }

    static var directory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents")
    }

    static func plistURL(label: String = label, in directory: URL = directory) -> URL {
        directory.appendingPathComponent("\(label).plist")
    }

    static var plistURL: URL { plistURL() }

    static var isEnabled: Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    static func setEnabled(_ enabled: Bool, in directory: URL = directory,
                           executable: String? = Bundle.main.executablePath) {
        if enabled {
            guard let executable else { return }
            do {
                try write(executable: executable, in: directory)
            } catch {
                NSLog("ClaudeNotch : écriture du LaunchAgent impossible (%@).", String(describing: error))
            }
        } else {
            // Pas de `launchctl bootout` ici : si launchd a lancé l'app, il la tuerait.
            // Sans le fichier, rien ne sera relancé à la prochaine ouverture de session.
            for url in [plistURL(in: directory), plistURL(label: legacyLabel, in: directory)] {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    /// Ancien plist `local.claudenotch.plist` : remplacé par le nouveau pour garder « Lancer à l'ouverture
    /// de session », puis supprimé, sans `launchctl bootout` (il tuerait l'app si launchd l'a lancée).
    /// Rend vrai si une migration a eu lieu.
    @discardableResult
    static func migrateLegacy(in directory: URL = directory,
                              executable: String? = Bundle.main.executablePath) -> Bool {
        let legacy = plistURL(label: legacyLabel, in: directory)
        guard FileManager.default.fileExists(atPath: legacy.path), let executable else { return false }
        do {
            try write(executable: executable, in: directory)
            try FileManager.default.removeItem(at: legacy)
        } catch {
            NSLog("ClaudeNotch : migration du LaunchAgent impossible (%@).", String(describing: error))
            return false
        }
        return true
    }

    private static func write(executable: String, in directory: URL) throws {
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [executable],
            "RunAtLoad": true,
            "LimitLoadToSessionType": "Aqua",
            "ProcessType": "Interactive",
        ]
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: plistURL(in: directory), options: .atomic)
    }
}

/// Préférences de l'app, observables par la vue.
final class Preferences: ObservableObject {
    static let shared = Preferences()

    private static let alwaysVisibleKey = "alwaysVisible"

    @Published var alwaysVisible: Bool {
        didSet { UserDefaults.standard.set(alwaysVisible, forKey: Self.alwaysVisibleKey) }
    }

    @Published var launchAtLogin: Bool {
        didSet {
            if launchAtLogin != LaunchAgent.isEnabled { LaunchAgent.setEnabled(launchAtLogin) }
        }
    }

    init() {
        alwaysVisible = UserDefaults.standard.bool(forKey: Self.alwaysVisibleKey)
        launchAtLogin = LaunchAgent.isEnabled
    }
}
