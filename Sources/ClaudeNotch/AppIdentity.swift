import Foundation

/// Identité publique de l'app.
///
/// `bundleId` doit rester égal à CFBundleIdentifier (Resources/Info.plist), à l'identifiant que
/// hooks/claude-notch-hook.sh relance (`open -g -b`) et au label du LaunchAgent (scripts/install.sh).
enum AppIdentity {
    static let bundleId = "io.github.slybald.claudenotch"
    /// Identifiant des premières versions, installées par scripts/install.sh.
    static let legacyBundleId = "local.claudenotch"

    /// Reprend une installation faite sous l'ancien identifiant : préférences, puis LaunchAgent.
    /// Le LaunchAgent n'est migré que depuis Applications : lancée depuis le DMG, l'app y écrirait
    /// un chemin qui disparaît à l'éjection.
    static func migrateLegacyInstall() {
        let defaults = UserDefaults.standard
        if Bundle.main.bundleIdentifier != legacyBundleId {
            migrateLegacyDefaults(from: defaults.persistentDomain(forName: legacyBundleId), to: defaults)
        }
        if isInApplicationsFolder(Bundle.main.bundlePath) {
            LaunchAgent.migrateLegacy()
        }
    }

    /// Les préférences changent de domaine avec l'identifiant : recopie celles de l'ancien domaine,
    /// sans écraser une valeur déjà présente dans le nouveau.
    static func migrateLegacyDefaults(from legacy: [String: Any]?, to defaults: UserDefaults) {
        guard let legacy else { return }
        for (key, value) in legacy where defaults.object(forKey: key) == nil {
            defaults.set(value, forKey: key)
        }
    }

    /// Vrai si l'app tourne depuis /Applications ou ~/Applications, et non depuis le DMG ou une copie
    /// translocalisée par Gatekeeper (/private/var/folders/…/AppTranslocation/…).
    static func isInApplicationsFolder(_ bundlePath: String,
                                       home: String = FileManager.default.homeDirectoryForCurrentUser.path) -> Bool {
        let path = (bundlePath as NSString).standardizingPath.lowercased()
        let folders = ["/Applications", (home as NSString).appendingPathComponent("Applications")]
        return folders.contains { path.hasPrefix($0.lowercased() + "/") }
    }
}
