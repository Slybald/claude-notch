import Foundation

// Lecture des ventilateurs et des températures, et séquences d'écriture du mode. Tout passe par `SMCDevice` :
// les tests y mettent un double, aucun n'écrit dans le vrai SMC.

/// Un ventilateur tel que le SMC le décrit (tr/min).
public struct FanReading: Equatable {
    public var index: Int
    public var actual: Double
    public var minimum: Double
    public var maximum: Double
    /// Cible demandée par macOS (automatique) ou par nous (manuel) ; nil si la clé manque.
    public var target: Double?
    /// `F<n>Md` : 0 automatique, 1 manuel ; nil si la clé manque (Mac Intel).
    public var mode: Int?

    public init(index: Int, actual: Double, minimum: Double, maximum: Double, target: Double? = nil, mode: Int? = nil) {
        self.index = index
        self.actual = actual
        self.minimum = minimum
        self.maximum = maximum
        self.target = target
        self.mode = mode
    }

    public var isManual: Bool { mode == 1 }
}

public enum Fans {
    /// Au-delà, `FNum` est faux : aucun Mac n'a autant de ventilateurs.
    static let maxCount = 8

    /// Les ventilateurs lisibles ; vide sur un Mac sans ventilateur (MacBook Air). Un ventilateur dont le minimum ou
    /// le maximum manque, ou dont les bornes sont incohérentes, est écarté : il ne pourrait pas être borné.
    public static func read(_ smc: SMCDevice) -> [FanReading] {
        guard let count = smc.read("FNum")?.number.map(Int.init), count > 0 else { return [] }
        return (0..<min(count, maxCount)).compactMap { index in
            guard let minimum = smc.read("F\(index)Mn")?.number, let maximum = smc.read("F\(index)Mx")?.number,
                  minimum > 0, maximum > minimum, maximum < 20_000 else { return nil }
            return FanReading(index: index, actual: smc.read("F\(index)Ac")?.number ?? 0, minimum: minimum,
                              maximum: maximum, target: smc.read("F\(index)Tg")?.number,
                              mode: smc.read("F\(index)Md")?.number.map(Int.init))
        }
    }

    /// Le mode manuel suit la méthode Apple Silicon (`F<n>Md` et une cible `flt `) ; les Mac Intel (clé `FS!`, cible
    /// en `fpe2`) ne sont pas pris en charge : leur tuile reste en lecture seule.
    public static func supportsManualMode(_ smc: SMCDevice, fan index: Int) -> Bool {
        smc.read("F\(index)Md")?.type == "ui8 " && smc.read("F\(index)Tg")?.type == "flt "
    }

    // MARK: - Écriture (root seulement)

    /// Passe un ventilateur en manuel à `rpm` (bornes déjà vérifiées par `FanRequest`). Si le SMC refuse
    /// `F<n>Md` = 1 (sur M3 et suivantes, macOS garde la main), on pose `Ftst` = 1, puis on réessaie toutes les
    /// 100 ms pendant 10 s au plus : le déverrouillage prend quelques secondes. `pause` sert aux
    /// tests. Rend false si le mode ou la vitesse est refusé.
    public static func setManual(_ smc: SMCDevice, fan index: Int, rpm: Int,
                                 pause: (Double) -> Void = { usleep(useconds_t($0 * 1_000_000)) }) -> Bool {
        let mode = "F\(index)Md"
        if smc.read(mode)?.number != 1, !smc.write(mode, [1]) {
            guard smc.read("Ftst") != nil, smc.write("Ftst", [1]) else { return false }
            var accepted = false
            for _ in 0..<100 where !accepted {
                pause(0.1)
                accepted = smc.write(mode, [1])
            }
            guard accepted else { return false }
        }
        return smc.write("F\(index)Tg", SMCValue.float(Float(rpm)))
    }

    /// Rend tous les ventilateurs à macOS : `F<n>Md` = 0 pour chacun, puis `Ftst` = 0. Essaie tout même après un
    /// refus (un ventilateur rendu vaut mieux qu'aucun) ; true si tout a été accepté.
    @discardableResult
    public static func setAutomatic(_ smc: SMCDevice) -> Bool {
        let count = min(Int(smc.read("FNum")?.number ?? 0), maxCount)
        var ok = true
        for index in 0..<count where smc.read("F\(index)Md") != nil {
            ok = smc.write("F\(index)Md", [0]) && ok
        }
        if smc.read("Ftst") != nil { ok = smc.write("Ftst", [0]) && ok }
        return ok
    }
}

/// Températures utiles : la plus chaude des sondes du processeur (cœurs performance `Tp…` et efficacité `Te…` sur
/// Apple Silicon, `TC…` sur Intel) et du GPU (`Tg…`, `TG…` sur Intel). Les clés sont cherchées une fois.
public final class Thermals {
    public struct Reading: Equatable {
        public var cpu: Double?
        public var gpu: Double?

        public init(cpu: Double?, gpu: Double?) {
            self.cpu = cpu
            self.gpu = gpu
        }

        /// La plus chaude des deux : c'est elle que la sécurité de température surveille.
        public var hottest: Double? { [cpu, gpu].compactMap { $0 }.max() }
    }

    private let smc: SMCDevice
    private lazy var keys: (cpu: [String], gpu: [String]) = {
        let all = smc.allKeys()
        func matching(_ prefixes: [String]) -> [String] { all.filter { key in prefixes.contains { key.hasPrefix($0) } } }
        let cpu = matching(["Tp", "Te"])
        let gpu = matching(["Tg"])
        return (cpu.isEmpty ? matching(["TC"]) : cpu, gpu.isEmpty ? matching(["TG"]) : gpu)
    }()

    public init(smc: SMCDevice) {
        self.smc = smc
    }

    public func read() -> Reading {
        Reading(cpu: hottest(keys.cpu), gpu: hottest(keys.gpu))
    }

    /// Une sonde absente ou débranchée rend 0, une valeur négative ou absurde : on ne garde que 1…150 °C.
    private func hottest(_ keys: [String]) -> Double? {
        keys.compactMap { smc.read($0)?.number }.filter { $0 > 0 && $0 < 150 }.max()
    }
}
