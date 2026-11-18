// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Network

/// A small HTTP server on 127.0.0.1 that the `notchflow` command talks to.
///
/// Only loopback connections are accepted, and every request must carry the
/// bearer token from `agent-bridge.env`, a file only the user can read, so
/// other users on the Mac and other machines cannot reach it. A request may
/// wait (an approval waits for a click); the reply is sent when the handler
/// finishes.
final class AgentBridgeServer: @unchecked Sendable {
    struct Request: Sendable {
        let method: String
        let path: String
        let headers: [String: String]
        let body: Data
    }

    struct Response: Sendable {
        var status: Int
        var contentType = "text/plain; charset=utf-8"
        var body = Data()

        static let empty = Response(status: 200)
        static func text(_ text: String, status: Int = 200) -> Response {
            Response(status: status, body: Data(text.utf8))
        }
        static func json(_ data: Data) -> Response {
            Response(status: 200, contentType: "application/json", body: data)
        }
    }

    private static let maximumBodySize = 8 * 1024 * 1024

    private let token: String
    private let handler: @Sendable (Request) async -> Response
    private let queue = DispatchQueue(label: "com.notchflow.agents.bridge")
    private var listener: NWListener?
    private(set) var port: UInt16 = 0

    init(token: String, handler: @escaping @Sendable (Request) async -> Response) {
        self.token = token
        self.handler = handler
    }

    func start() async throws -> UInt16 {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: .any)
        let listener = try NWListener(using: parameters)
        self.listener = listener
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }

        let port: UInt16 = try await withCheckedThrowingContinuation { continuation in
            let once = BridgeResumeOnce()
            listener.stateUpdateHandler = { [weak listener] state in
                switch state {
                case .ready:
                    guard once.claim() else { return }
                    continuation.resume(returning: listener?.port?.rawValue ?? 0)
                case .failed(let error):
                    guard once.claim() else { return }
                    continuation.resume(throwing: error)
                case .cancelled:
                    guard once.claim() else { return }
                    continuation.resume(throwing: CancellationError())
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }
        self.port = port
        return port
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    // MARK: Connections

    private func accept(_ connection: NWConnection) {
        if case let .hostPort(host, _) = connection.endpoint {
            let loopback: Bool
            switch host {
            case .ipv4(let address): loopback = address.isLoopback
            case .ipv6(let address): loopback = address.isLoopback
            default: loopback = false
            }
            guard loopback else { connection.cancel(); return }
        }
        connection.start(queue: queue)
        receive(on: connection, buffer: Data())
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { connection.cancel(); return }
            var buffer = buffer
            if let data { buffer.append(data) }
            if buffer.count > Self.maximumBodySize + 16 * 1024 {
                self.send(.text("Too large", status: 413), on: connection)
                return
            }
            switch Self.parse(buffer) {
            case .incomplete:
                if isComplete || error != nil { connection.cancel() } else { self.receive(on: connection, buffer: buffer) }
            case .invalid(let status):
                self.send(.text("Bad request", status: status), on: connection)
            case .request(let request):
                guard Self.constantTimeEquals(request.headers["authorization"] ?? "", "Bearer \(self.token)") else {
                    self.send(.text("Unauthorized", status: 401), on: connection)
                    return
                }
                let handler = self.handler
                Task {
                    let response = await handler(request)
                    self.send(response, on: connection)
                }
            }
        }
    }

    private enum ParseResult {
        case incomplete
        case invalid(Int)
        case request(Request)
    }

    private static func parse(_ buffer: Data) -> ParseResult {
        guard let headerEnd = buffer.range(of: Data("\r\n\r\n".utf8)) else { return .incomplete }
        let headerText = String(decoding: buffer[buffer.startIndex..<headerEnd.lowerBound], as: UTF8.self)
        var lines = headerText.components(separatedBy: "\r\n")
        guard !lines.isEmpty else { return .invalid(400) }
        let requestLine = lines.removeFirst().split(separator: " ")
        guard requestLine.count >= 2 else { return .invalid(400) }
        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()] =
                line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let length = headers["content-length"].flatMap(Int.init) ?? 0
        guard length >= 0, length <= maximumBodySize else { return .invalid(413) }
        let bodyStart = headerEnd.upperBound
        guard buffer.count - bodyStart >= length else { return .incomplete }
        let path = requestLine[1].split(separator: "?").first.map(String.init) ?? "/"
        return .request(Request(method: String(requestLine[0]), path: path, headers: headers,
                                body: buffer.subdata(in: bodyStart..<(bodyStart + length))))
    }

    private static func constantTimeEquals(_ lhs: String, _ rhs: String) -> Bool {
        let a = Array(lhs.utf8), b = Array(rhs.utf8)
        guard a.count == b.count else { return false }
        return zip(a, b).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }

    private func send(_ response: Response, on connection: NWConnection) {
        let reason: String
        switch response.status {
        case 200: reason = "OK"
        case 204: reason = "No Content"
        case 401: reason = "Unauthorized"
        case 404: reason = "Not Found"
        case 413: reason = "Payload Too Large"
        default: reason = "Error"
        }
        var head = "HTTP/1.1 \(response.status) \(reason)\r\n"
        head += "Content-Type: \(response.contentType)\r\nContent-Length: \(response.body.count)\r\nConnection: close\r\n\r\n"
        var data = Data(head.utf8)
        data.append(response.body)
        connection.send(content: data, completion: .contentProcessed { _ in connection.cancel() })
    }

    /// Parses `application/x-www-form-urlencoded` bodies (what `curl --data-urlencode` sends).
    static func formFields(_ body: Data) -> [String: String] {
        var fields: [String: String] = [:]
        for pair in String(decoding: body, as: UTF8.self).split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1).map {
                String($0).replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? String($0)
            }
            if let key = parts.first { fields[key] = parts.count > 1 ? parts[1] : "" }
        }
        return fields
    }
}

/// Lets the listener's state handler resume its continuation exactly once.
private final class BridgeResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !claimed else { return false }
        claimed = true
        return true
    }
}
