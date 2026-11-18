/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import CryptoKit
import Foundation
import Network

/// Receives the gateway's webhook deliveries on 127.0.0.1.
///
/// This is how new messages reach the notch the moment they arrive instead of
/// on the next poll. It accepts only loopback connections, only `POST` to its
/// own path, and only bodies signed with the secret Atoll handed the gateway
/// at launch (`X-Hub-Signature-256: sha256=<hmac>`), so another local process
/// cannot inject messages into the notch.
final class WhatsAppWebhookServer {
    static let path = "/atoll/whatsapp"
    private static let maximumBodySize = 4 * 1024 * 1024

    private let secret: SymmetricKey
    private let onEvent: (Data) -> Void
    private let queue = DispatchQueue(label: "com.atoll.whatsapp.webhook")
    private var listener: NWListener?

    private(set) var port: UInt16 = 0

    init(secret: String, onEvent: @escaping (Data) -> Void) {
        self.secret = SymmetricKey(data: Data(secret.utf8))
        self.onEvent = onEvent
    }

    /// Starts listening on an ephemeral loopback port and returns it once ready.
    func start() async throws -> UInt16 {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: .any)
        let listener = try NWListener(using: parameters)
        self.listener = listener

        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }

        let port: UInt16 = try await withCheckedThrowingContinuation { continuation in
            let once = ResumeOnce()
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
            let isLoopback: Bool
            switch host {
            case .ipv4(let address): isLoopback = address.isLoopback
            case .ipv6(let address): isLoopback = address.isLoopback
            default: isLoopback = false
            }
            guard isLoopback else {
                connection.cancel()
                return
            }
        }
        connection.start(queue: queue)
        receive(on: connection, buffer: Data())
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }
            var buffer = buffer
            if let data { buffer.append(data) }

            if buffer.count > Self.maximumBodySize + 16 * 1024 {
                self.respond(connection, status: 413, reason: "Payload Too Large")
                return
            }

            switch self.parse(buffer) {
            case .incomplete:
                if isComplete || error != nil {
                    connection.cancel()
                } else {
                    self.receive(on: connection, buffer: buffer)
                }
            case .invalid(let status, let reason):
                self.respond(connection, status: status, reason: reason)
            case .request(let headers, let body):
                guard self.isSignatureValid(headers["x-hub-signature-256"], body: body) else {
                    self.respond(connection, status: 401, reason: "Unauthorized")
                    return
                }
                self.respond(connection, status: 200, reason: "OK")
                self.onEvent(body)
            }
        }
    }

    private enum ParseResult {
        case incomplete
        case invalid(Int, String)
        case request(headers: [String: String], body: Data)
    }

    private func parse(_ buffer: Data) -> ParseResult {
        let separator = Data("\r\n\r\n".utf8)
        guard let headerEnd = buffer.range(of: separator) else { return .incomplete }

        let headerText = String(decoding: buffer[buffer.startIndex..<headerEnd.lowerBound], as: UTF8.self)
        var lines = headerText.components(separatedBy: "\r\n")
        guard !lines.isEmpty else { return .invalid(400, "Bad Request") }
        let requestLine = lines.removeFirst().split(separator: " ")
        guard requestLine.count >= 2 else { return .invalid(400, "Bad Request") }
        guard requestLine[0] == "POST" else { return .invalid(405, "Method Not Allowed") }
        let target = requestLine[1].split(separator: "?").first.map(String.init) ?? ""
        guard target == Self.path else { return .invalid(404, "Not Found") }

        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[name] = value
        }

        guard let length = headers["content-length"].flatMap(Int.init), length >= 0 else {
            return .invalid(411, "Length Required")
        }
        guard length <= Self.maximumBodySize else { return .invalid(413, "Payload Too Large") }

        let bodyStart = headerEnd.upperBound
        guard buffer.count - bodyStart >= length else { return .incomplete }
        let body = buffer.subdata(in: bodyStart..<(bodyStart + length))
        return .request(headers: headers, body: body)
    }

    private func isSignatureValid(_ header: String?, body: Data) -> Bool {
        guard let header, header.hasPrefix("sha256=") else { return false }
        let hex = String(header.dropFirst("sha256=".count))
        guard let signature = Data(hexString: hex) else { return false }
        return HMAC<SHA256>.isValidAuthenticationCode(signature, authenticating: body, using: secret)
    }

    private func respond(_ connection: NWConnection, status: Int, reason: String) {
        let response = "HTTP/1.1 \(status) \(reason)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}

/// Lets the listener's state handler resume its continuation exactly once.
private final class ResumeOnce: @unchecked Sendable {
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

private extension Data {
    init?(hexString: String) {
        let characters = Array(hexString.utf8)
        guard characters.count % 2 == 0 else { return nil }
        var bytes = [UInt8]()
        bytes.reserveCapacity(characters.count / 2)
        var index = 0
        while index < characters.count {
            guard let high = Self.nibble(characters[index]), let low = Self.nibble(characters[index + 1]) else { return nil }
            bytes.append(high << 4 | low)
            index += 2
        }
        self.init(bytes)
    }

    private static func nibble(_ character: UInt8) -> UInt8? {
        switch character {
        case UInt8(ascii: "0")...UInt8(ascii: "9"): return character - UInt8(ascii: "0")
        case UInt8(ascii: "a")...UInt8(ascii: "f"): return character - UInt8(ascii: "a") + 10
        case UInt8(ascii: "A")...UInt8(ascii: "F"): return character - UInt8(ascii: "A") + 10
        default: return nil
        }
    }
}
