import Foundation
import IOKit

// Accès au SMC (System Management Controller) par IOKit, partagé par l'app (lecture) et l'outil `fanctl` (écriture,
// en root). Format de l'échange mesuré sur un MacBook Pro M3 Pro : voir docs/FANS.md.

/// Une valeur lue : type SMC (« flt  », « ui8  »…) et octets bruts.
public struct SMCValue: Equatable {
    public var type: String
    public var bytes: [UInt8]

    public init(type: String, bytes: [UInt8]) {
        self.type = type
        self.bytes = bytes
    }

    /// Valeur numérique selon le type ; nil pour un type non géré ou une taille fausse. Sur Apple Silicon, `flt `
    /// est un Float32 petit-boutiste (mesuré : 2317 tr/min = 00 d0 10 45) ; les types Intel sont gros-boutistes.
    public var number: Double? {
        switch (type, bytes.count) {
        case ("flt ", 4):
            return Double(Float(bitPattern: UInt32(bytes[0]) | UInt32(bytes[1]) << 8 | UInt32(bytes[2]) << 16
                | UInt32(bytes[3]) << 24))
        case ("ui8 ", 1):
            return Double(bytes[0])
        case ("ui16", 2):
            return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
        case ("fpe2", 2):
            return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1])) / 4
        case ("sp78", 2):
            return Double(Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))) / 256
        default:
            return nil
        }
    }

    /// Float32 petit-boutiste, le format des vitesses sur Apple Silicon.
    public static func float(_ value: Float) -> [UInt8] {
        let bits = value.bitPattern
        return [UInt8(bits & 0xff), UInt8(bits >> 8 & 0xff), UInt8(bits >> 16 & 0xff), UInt8(bits >> 24)]
    }
}

/// Ce dont les lecteurs et l'outil ont besoin du SMC ; les tests y mettent un double.
public protocol SMCDevice: AnyObject {
    func read(_ key: String) -> SMCValue?
    /// false : clé absente, taille fausse ou refus (sans root, le noyau refuse toute écriture).
    func write(_ key: String, _ bytes: [UInt8]) -> Bool
    /// Toutes les clés (« #KEY » puis une lecture par index) : lent, à ne faire qu'une fois.
    func allKeys() -> [String]
}

/// La vraie connexion au service AppleSMC. Un appel coûte environ 1 ms (mesuré) : jamais sur le fil principal de
/// l'app, et depuis une seule file à la fois (le cache des types de clés n'est pas protégé).
public final class SMCConnection: SMCDevice {
    private var connection: io_connect_t = 0
    private var infoCache: [UInt32: (size: Int, type: String)] = [:]

    // Commandes de la méthode 2 (kSMCHandleYPCEvent).
    private enum Command: UInt8 {
        case read = 5, write = 6, keyAtIndex = 8, keyInfo = 9
    }

    /// nil : pas de SMC (machine virtuelle) ou ouverture refusée.
    public init?() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard IOServiceOpen(service, mach_task_self_, 0, &connection) == KERN_SUCCESS else { return nil }
    }

    deinit { IOServiceClose(connection) }

    public func read(_ key: String) -> SMCValue? {
        guard let code = Self.code(key), let info = keyInfo(code) else { return nil }
        var input = Self.request(.read, key: code)
        Self.put(UInt32(info.size), into: &input, at: 28)
        guard let output = call(input), output[40] == 0 else { return nil }
        return SMCValue(type: info.type, bytes: Array(output[48..<48 + min(info.size, 32)]))
    }

    public func write(_ key: String, _ bytes: [UInt8]) -> Bool {
        guard let code = Self.code(key), let info = keyInfo(code), info.size == bytes.count else { return false }
        var input = Self.request(.write, key: code)
        Self.put(UInt32(info.size), into: &input, at: 28)
        input.replaceSubrange(48..<48 + bytes.count, with: bytes)
        guard let output = call(input) else { return false }
        return output[40] == 0
    }

    public func allKeys() -> [String] {
        guard let count = read("#KEY"), count.bytes.count == 4 else { return [] }
        let total = count.bytes.reduce(0) { $0 << 8 | Int($1) }
        return (0..<total).compactMap { index in
            var input = Self.request(.keyAtIndex, key: 0)
            Self.put(UInt32(index), into: &input, at: 44)
            guard let output = call(input), output[40] == 0 else { return nil }
            return Self.text(Self.get(output, at: 0))
        }
    }

    // MARK: - Format de l'échange

    // SMCKeyData_t, 80 octets : clé (0), taille (28), type (32), attributs (36), résultat (40), commande (42),
    // index (44), données (48…79).
    private static let size = 80

    private func keyInfo(_ code: UInt32) -> (size: Int, type: String)? {
        if let cached = infoCache[code] { return cached }
        guard let output = call(Self.request(.keyInfo, key: code)), output[40] == 0 else { return nil }
        let size = Int(Self.get(output, at: 28))
        guard (1...32).contains(size) else { return nil }
        let info = (size, Self.text(Self.get(output, at: 32)))
        infoCache[code] = info
        return info
    }

    private func call(_ input: [UInt8]) -> [UInt8]? {
        var output = [UInt8](repeating: 0, count: Self.size)
        var outputSize = Self.size
        let status = input.withUnsafeBytes { inBuffer in
            output.withUnsafeMutableBytes { outBuffer in
                IOConnectCallStructMethod(connection, 2, inBuffer.baseAddress, Self.size, outBuffer.baseAddress,
                                          &outputSize)
            }
        }
        return status == KERN_SUCCESS ? output : nil
    }

    private static func request(_ command: Command, key: UInt32) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: size)
        put(key, into: &bytes, at: 0)
        bytes[42] = command.rawValue
        return bytes
    }

    /// Quatre caractères ASCII → entier (« FNum » = 0x464E756D).
    static func code(_ key: String) -> UInt32? {
        let bytes = Array(key.utf8)
        guard bytes.count == 4, bytes.allSatisfy({ (0x20...0x7e).contains($0) }) else { return nil }
        return bytes.reduce(0) { $0 << 8 | UInt32($1) }
    }

    static func text(_ code: UInt32) -> String {
        String(decoding: [24, 16, 8, 0].map { UInt8(code >> $0 & 0xff) }, as: UTF8.self)
    }

    /// Ordre natif : la structure est celle du noyau, sur la même machine.
    private static func put(_ value: UInt32, into bytes: inout [UInt8], at offset: Int) {
        withUnsafeBytes(of: value) { bytes.replaceSubrange(offset..<offset + 4, with: $0) }
    }

    private static func get(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        bytes[offset..<offset + 4].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
    }
}
