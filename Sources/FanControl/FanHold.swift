import Foundation

// Le « bail » de l'outil `fanctl hold` : tant que l'app parle, la vitesse fixe tient ; sinon tout revient en
// automatique. Pur (le SMC et l'horloge sont passés), donc testé sans matériel ni root.
//
// Protocole, une ligne ASCII par message :
//   app → outil : `ping` | `fan <n> <tr/min>` | `auto`
//   outil → app : `ok` | `refused <raison>` | `auto <raison>` (dernier message, l'outil s'arrête ensuite)

/// Une ligne de l'app, validée contre les ventilateurs lus dans le SMC.
public enum FanRequest: Equatable {
    case ping
    case automatic
    case manual(fan: Int, rpm: Int)

    public enum Refusal: String, Error {
        case syntax, unknownFan = "unknown-fan", belowMinimum = "below-minimum", aboveMaximum = "above-maximum"
    }

    /// Stricte : mots séparés par une seule espace, nombres en chiffres ASCII sans signe ni zéro de tête, vitesse
    /// entre le minimum et le maximum du ventilateur (bornes lues dans le SMC, jamais données par l'app).
    public static func parse(_ line: String, fans: [FanReading]) -> Result<FanRequest, Refusal> {
        guard line.utf8.count <= 32 else { return .failure(.syntax) }
        let words = line.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        switch words {
        case ["ping"]:
            return .success(.ping)
        case ["auto"]:
            return .success(.automatic)
        case let parts where parts.count == 3 && parts[0] == "fan":
            guard let index = number(parts[1]), let rpm = number(parts[2]) else { return .failure(.syntax) }
            guard let fan = fans.first(where: { $0.index == index }) else { return .failure(.unknownFan) }
            if Double(rpm) < fan.minimum.rounded(.up) { return .failure(.belowMinimum) }
            if Double(rpm) > fan.maximum.rounded(.down) { return .failure(.aboveMaximum) }
            return .success(.manual(fan: index, rpm: rpm))
        default:
            return .failure(.syntax)
        }
    }

    private static func number(_ text: String) -> Int? {
        guard (1...5).contains(text.count), text.utf8.allSatisfy({ (48...57).contains($0) }),
              text == "0" || !text.hasPrefix("0") else { return nil }
        return Int(text)
    }
}

/// Une tenue en mode manuel. `now` est une horloge monotone en secondes (le sommeil du Mac compte).
public final class FanHold {
    public enum Ending: String {
        /// L'app a demandé le retour en automatique.
        case requested
        /// L'app a fermé le tube : elle a quitté ou planté.
        case closed
        /// Plus de nouvelles de l'app depuis `lease` secondes (app figée, Mac sorti de veille…).
        case lease
        /// Sonde au-delà de `temperatureLimit`.
        case temperature
        /// Le SMC a refusé une écriture.
        case write
        /// Signal reçu (arrêt du système, kill).
        case signal
        /// macOS a repris la main sur un ventilateur tenu (mode relu différent de 1) : on ne lutte pas contre lui.
        case system
    }

    /// Délai sans message de l'app avant le retour en automatique ; l'app écrit toutes les 10 s.
    public static let lease: Double = 30
    /// Au-delà, retour en automatique, sauf si tous les ventilateurs tenus sont déjà au maximum (macOS ne ferait pas
    /// mieux). Le M3 Pro mesuré dépasse 100 °C sous forte charge en automatique : seuil choisi au-dessus.
    public static let temperatureLimit: Double = 105

    public let fans: [FanReading]
    public private(set) var targets: [Int: Int] = [:]
    public private(set) var ending: Ending?
    private let smc: SMCDevice
    private let pause: (Double) -> Void
    private var lastHeard: Double

    public init(smc: SMCDevice, now: Double, pause: @escaping (Double) -> Void = { usleep(useconds_t($0 * 1_000_000)) }) {
        self.smc = smc
        self.pause = pause
        fans = Fans.read(smc).filter { Fans.supportsManualMode(smc, fan: $0.index) }
        lastHeard = now
    }

    /// Une ligne de l'app : la réponse à lui renvoyer. Seule une ligne valide renouvelle le bail.
    public func receive(_ line: String, now: Double) -> String {
        guard ending == nil else { return "auto \(ending!.rawValue)" }
        switch FanRequest.parse(line, fans: fans) {
        case .failure(let refusal):
            return "refused \(refusal.rawValue)"
        case .success(.ping):
            lastHeard = now
            return "ok"
        case .success(.automatic):
            return end(.requested)
        case .success(.manual(let fan, let rpm)):
            lastHeard = now
            guard Fans.setManual(smc, fan: fan, rpm: rpm, pause: pause) else { return end(.write) }
            targets[fan] = rpm
            return "ok"
        }
    }

    /// Réveil périodique : bail expiré, macOS qui a repris un ventilateur, ou température trop haute → automatique.
    /// nil : rien ne change.
    public func tick(now: Double, hottest: Double?) -> String? {
        guard ending == nil else { return nil }
        if now - lastHeard > Self.lease { return end(.lease) }
        if targets.keys.contains(where: { smc.read("F\($0)Md")?.number != 1 }) { return end(.system) }
        if let hottest, hottest >= Self.temperatureLimit, !targets.isEmpty,
           targets.contains(where: { fan, rpm in Double(rpm) < (fans.first { $0.index == fan }?.maximum.rounded(.down) ?? 0) }) {
            return end(.temperature)
        }
        return nil
    }

    /// Rend la main à macOS (toujours, même si rien n'a été tenu) et clôt la tenue : `auto <raison>`.
    @discardableResult
    public func end(_ reason: Ending) -> String {
        if ending == nil {
            ending = reason
            Fans.setAutomatic(smc)
            targets = [:]
        }
        return "auto \(ending!.rawValue)"
    }
}
