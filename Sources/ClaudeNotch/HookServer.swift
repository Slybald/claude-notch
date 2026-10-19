import Foundation
import Network

/// Mini serveur HTTP local (127.0.0.1:47823) qui reçoit les événements relayés par le script de hook.
final class HookServer {
    typealias Handler = (HookEvent, ProcessContext) -> Void

    static let defaultPort: UInt16 = 47823
    static let maxBodySize = 32 * 1024 * 1024

    var onFailure: ((Error) -> Void)?
    /// Diagnostic en lecture seule pour `GET /state` (appelé sur le main thread).
    var stateProvider: (() -> [String: Any])?

    private let port: UInt16
    private let handler: Handler
    private let queue = DispatchQueue(label: AppIdentity.bundleId + ".server", qos: .userInitiated)
    private var listener: NWListener?

    init(port: UInt16 = HookServer.defaultPort, handler: @escaping Handler) {
        self.port = port
        self.handler = handler
    }

    func start() throws {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { throw NWError.posix(.EINVAL) }
        let parameters = NWParameters.tcp
        parameters.requiredInterfaceType = .loopback
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: nwPort)
        parameters.allowLocalEndpointReuse = true

        let listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        listener.stateUpdateHandler = { [weak self] state in
            if case .failed(let error) = state {
                self?.onFailure?(error)
            }
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    // MARK: - Connexions

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(on: connection, buffer: Data())
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { [weak self] data, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }
            var buffer = buffer
            if let data { buffer.append(data) }

            switch HTTPRequest.parse(buffer, maxBody: Self.maxBodySize) {
            case .complete(let request):
                self.serve(request, on: connection)
            case .needMore:
                if error != nil || isComplete {
                    connection.cancel()
                } else {
                    self.receive(on: connection, buffer: buffer)
                }
            case .tooLarge:
                self.reply(413, "Payload Too Large", on: connection)
            case .invalid:
                self.reply(400, "Bad Request", on: connection)
            }
        }
    }

    private func serve(_ request: HTTPRequest, on connection: NWConnection) {
        guard request.method == "POST", request.path == "/hook" else {
            switch request.path {
            case "/health":
                reply(204, "No Content", on: connection)
            case "/state" where request.method == "GET":
                let state = stateProvider.map { provider in DispatchQueue.main.sync(execute: provider) } ?? [:]
                let body = (try? JSONSerialization.data(withJSONObject: state, options: [.prettyPrinted, .sortedKeys])) ?? Data()
                reply(200, "OK", body: body, on: connection)
            default:
                reply(404, "Not Found", on: connection)
            }
            return
        }
        // Le script de hook attend notre réponse : ses processus parents sont encore vivants,
        // c'est le moment de remonter la chaîne pour identifier Claude et l'app hôte.
        let headers = HookHeaders(request.headers)
        let context = ProcessInspector.context(for: headers)
        reply(204, "No Content", on: connection)

        guard let event = HookEvent(data: request.body, headers: headers) else { return }
        handler(event, context)
    }

    private func reply(_ status: Int, _ reason: String, body: Data = Data(), on connection: NWConnection) {
        var head = "HTTP/1.1 \(status) \(reason)\r\nContent-Length: \(body.count)\r\nConnection: close\r\n"
        if !body.isEmpty { head += "Content-Type: application/json\r\n" }
        connection.send(content: Data((head + "\r\n").utf8) + body, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}

/// Requête HTTP/1.1 minimale : ligne de requête, en-têtes, corps de taille Content-Length.
struct HTTPRequest {
    enum ParseResult {
        case complete(HTTPRequest)
        case needMore
        case tooLarge
        case invalid
    }

    let method: String
    let path: String
    /// Clés en minuscules.
    let headers: [String: String]
    let body: Data

    private static let terminator = Data("\r\n\r\n".utf8)
    private static let maxHeaderSize = 64 * 1024

    static func parse(_ data: Data, maxBody: Int) -> ParseResult {
        guard let end = data.range(of: terminator) else {
            return data.count > maxHeaderSize ? .invalid : .needMore
        }
        guard let head = String(data: data[data.startIndex..<end.lowerBound], encoding: .utf8) else {
            return .invalid
        }
        var lines = head.components(separatedBy: "\r\n")
        let requestLine = lines.removeFirst().split(separator: " ")
        guard requestLine.count >= 2 else { return .invalid }

        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[key] = value
        }

        let length = Int(headers["content-length"] ?? "0") ?? -1
        guard length >= 0 else { return .invalid }
        guard length <= maxBody else { return .tooLarge }

        let bodyStart = end.upperBound
        guard data.endIndex - bodyStart >= length else { return .needMore }

        let rawPath = String(requestLine[1])
        let path = rawPath.split(separator: "?", maxSplits: 1).first.map(String.init) ?? rawPath
        return .complete(HTTPRequest(
            method: String(requestLine[0]).uppercased(),
            path: path,
            headers: headers,
            body: data.subdata(in: bodyStart..<(bodyStart + length))
        ))
    }
}
