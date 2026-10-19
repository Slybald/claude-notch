import Combine
import Foundation

/// LaunchAgent `~/Library/LaunchAgents/local.claudenotch.plist` : lancement à l'ouverture de session.
enum LaunchAgent {
    static let label = "local.claudenotch"

    static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    static var isEnabled: Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    static func setEnabled(_ enabled: Bool) {
        if enabled {
            guard let executable = Bundle.main.executablePath else { return }
            let plist: [String: Any] = [
                "Label": label,
                "ProgramArguments": [executable],
                "RunAtLoad": true,
                "LimitLoadToSessionType": "Aqua",
                "ProcessType": "Interactive",
            ]
            do {
                try FileManager.default.createDirectory(at: plistURL.deletingLastPathComponent(),
                                                        withIntermediateDirectories: true)
                let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
                try data.write(to: plistURL, options: .atomic)
            } catch {
                NSLog("ClaudeNotch : écriture du LaunchAgent impossible (%@).", String(describing: error))
            }
        } else {
            // Pas de `launchctl bootout` ici : si launchd a lancé l'app, il la tuerait.
            // Sans le fichier, rien ne sera relancé à la prochaine ouverture de session.
            try? FileManager.default.removeItem(at: plistURL)
        }
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
