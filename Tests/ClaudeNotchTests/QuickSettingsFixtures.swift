import Foundation
import XCTest
@testable import ClaudeNotch

// Doubles des accès système du module « Réglages rapides » : aucun test ne bascule quoi que ce soit pour de vrai.

final class QSFakeWiFi: WiFiBackend {
    var power: Bool? = true
    var associated = true
    var failure: QuickSettingsFailure?
    /// Garde la fin de l'écriture en attente (pour voir l'état intermédiaire).
    var holdsCompletion = false
    private(set) var setCalls: [Bool] = []
    private(set) var reads = 0
    private(set) var monitoring = false
    private var pending: (() -> Void)?
    private var onChange: (() -> Void)?

    func isPoweredOn() -> Bool? { reads += 1; return power }
    func isAssociated() -> Bool { associated }

    func setPower(_ on: Bool, completion: @escaping (Result<Void, QuickSettingsFailure>) -> Void) {
        setCalls.append(on)
        let finish = { [self] in
            if let failure {
                completion(.failure(failure))
            } else {
                power = on
                completion(.success(()))
            }
        }
        if holdsCompletion { pending = finish } else { finish() }
    }

    func release() { pending?(); pending = nil }
    func startMonitoring(_ onChange: @escaping () -> Void) { monitoring = true; self.onChange = onChange }
    func stopMonitoring() { monitoring = false; onChange = nil }
    func fire() { onChange?() }
}

final class QSFakeBluetooth: BluetoothBackend {
    var power: Bool? = true
    /// L'appel part mais le contrôleur ne change pas d'état (autorisation refusée par exemple).
    var ignoresWrites = false
    var acceptsCalls = true
    private(set) var setCalls: [Bool] = []
    private(set) var reads = 0

    func isPoweredOn() -> Bool? { reads += 1; return power }

    func setPower(_ on: Bool) -> Bool {
        setCalls.append(on)
        guard acceptsCalls else { return false }
        if !ignoresWrites { power = on }
        return true
    }
}

final class QSFakePower: PowerModeBackend {
    var supported = true
    var lowPower = false
    var failure: QuickSettingsFailure?
    /// Le système ne change pas d'état malgré une écriture réussie.
    var ignoresWrites = false
    var holdsCompletion = false
    /// Règle sudoers : comme le vrai accès, une règle `.granted` que sudo n'accepte plus (`ruleWorks` faux) laisse
    /// passer l'écriture avec le mot de passe et passe à `.refused`.
    var authorization = LowPowerAuthorizationState.none
    var ruleWorks = true
    var authorizeFailure: QuickSettingsFailure?
    var revokeFailure: QuickSettingsFailure?
    private(set) var authorizeCalls = 0
    private(set) var revokeCalls = 0
    private(set) var setCalls: [Bool] = []
    private(set) var supportChecks = 0
    private(set) var monitoring = false
    private var pending: (() -> Void)?
    private var onChange: (() -> Void)?

    var isLowPowerEnabled: Bool { lowPower }

    func checkSupport(completion: @escaping (Bool) -> Void) {
        supportChecks += 1
        completion(supported)
    }

    func setLowPower(_ on: Bool, completion: @escaping (Result<LowPowerWrite, QuickSettingsFailure>) -> Void) {
        setCalls.append(on)
        let finish = { [self] in
            if let failure {
                completion(.failure(failure))
            } else {
                if !ignoresWrites { lowPower = on }
                var write = LowPowerWrite.done
                if authorization == .granted, !ruleWorks {
                    authorization = .refused
                    write = .authorizationRefused
                }
                completion(.success(write))
            }
        }
        if holdsCompletion { pending = finish } else { finish() }
    }

    func authorize(completion: @escaping (Result<Void, QuickSettingsFailure>) -> Void) {
        authorizeCalls += 1
        let finish = { [self] in
            if let authorizeFailure {
                completion(.failure(authorizeFailure))
            } else {
                authorization = .granted
                completion(.success(()))
            }
        }
        if holdsCompletion { pending = finish } else { finish() }
    }

    func revokeAuthorization(completion: @escaping (Result<Void, QuickSettingsFailure>) -> Void) {
        revokeCalls += 1
        if let revokeFailure { return completion(.failure(revokeFailure)) }
        authorization = .none
        completion(.success(()))
    }

    func release() { pending?(); pending = nil }
    func startMonitoring(_ onChange: @escaping () -> Void) { monitoring = true; self.onChange = onChange }
    func stopMonitoring() { monitoring = false; onChange = nil }
    func fire() { onChange?() }
}

final class QSFakeBattery: BatteryBackend {
    var iops: [PowerSourceInfo] = [QSFakeBattery.mac(percent: 78)]
    var pmset: [PowerSourceInfo] = []
    private(set) var iopsReads = 0
    private(set) var pmsetReads = 0
    private(set) var monitoring = false
    private var onChange: (() -> Void)?

    static func mac(percent: Int, pluggedIn: Bool = false, charging: Bool = false, minutes: Int? = 227) -> PowerSourceInfo {
        PowerSourceInfo(name: "InternalBattery-0", kind: .mac, percent: percent, isCharging: charging,
                        isPluggedIn: pluggedIn, minutes: minutes)
    }

    func readIOPS() -> [PowerSourceInfo] { iopsReads += 1; return iops }
    func readPmset(completion: @escaping ([PowerSourceInfo]) -> Void) { pmsetReads += 1; completion(pmset) }
    func startMonitoring(_ onChange: @escaping () -> Void) { monitoring = true; self.onChange = onChange }
    func stopMonitoring() { monitoring = false; onChange = nil }

    /// Notification IOPS : le système a changé quelque chose.
    func fire(percent: Int? = nil, pluggedIn: Bool = false) {
        if let percent { iops = [Self.mac(percent: percent, pluggedIn: pluggedIn)] }
        onChange?()
    }
}

final class QSFakeCaffeine: CaffeineBackend {
    var fails = false
    private(set) var acquires: [Bool] = []
    private(set) var releases = 0

    func acquire(keepDisplayOn: Bool) -> Bool {
        acquires.append(keepDisplayOn)
        return !fails
    }

    func release() { releases += 1 }
}

final class QSFakeShortcuts: ShortcutBackend {
    var failure: QuickSettingsFailure?
    private(set) var runs: [String] = []

    func run(_ name: String, completion: @escaping (Result<Void, QuickSettingsFailure>) -> Void) {
        runs.append(name)
        completion(failure.map { .failure($0) } ?? .success(()))
    }
}

/// Un module branché sur des doubles, des réglages jetables et une horloge réglable.
final class QuickSettingsFixture {
    let wifi = QSFakeWiFi()
    let bluetooth = QSFakeBluetooth()
    let power = QSFakePower()
    let battery = QSFakeBattery()
    let caffeine = QSFakeCaffeine()
    let shortcuts = QSFakeShortcuts()
    let defaults: UserDefaults
    /// Horloge et URL ouvertes : dans un objet à part, que le module garde en vie même si la fixture disparaît.
    private final class State {
        var now = Date(timeIntervalSince1970: 1_800_000_000)
        var opened: [URL] = []
    }

    private let state = State()
    private(set) lazy var module = makeModule()

    var now: Date {
        get { state.now }
        set { state.now = newValue }
    }

    var opened: [URL] { state.opened }

    init(_ testCase: XCTestCase) {
        defaults = makeEphemeralDefaults(testCase)
    }

    /// Laisse passer les tâches différées (relectures du Bluetooth, de l'économie d'énergie).
    static func settle(_ duration: TimeInterval = 0.05) {
        RunLoop.main.run(until: Date().addingTimeInterval(duration))
    }

    var backends: QuickSettingsBackends {
        QuickSettingsBackends(wifi: wifi, bluetooth: bluetooth, power: power, battery: battery,
                              caffeine: caffeine, shortcuts: shortcuts)
    }

    /// Un deuxième module sur les mêmes réglages (relance de l'app).
    func makeModule() -> QuickSettingsModule {
        let state = state
        return QuickSettingsModule(backends: backends, defaults: defaults, clock: { state.now }, settleDelay: 0,
                                   open: { state.opened.append($0) })
    }

    /// Démarre le module et affiche l'onglet : tout est lu.
    @discardableResult
    func startAndShow() -> QuickSettingsModule {
        module.start()
        module.viewAppeared()
        return module
    }
}
