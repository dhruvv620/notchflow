/*
 * NotchFlow
 * Copyright (C) 2026 dhruvv620
 * Portions Copyright (C) 2024-2026 Atoll Contributors
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

import Foundation

enum WhatsAppGatewayError: LocalizedError {
    case notRunning
    case http(status: Int, code: String?, message: String?)
    case invalidResponse
    /// The gateway answered, but not in the shape NotchFlow expects.
    case unreadable(path: String, detail: String)

    var errorDescription: String? {
        switch self {
        case .notRunning:
            return String(localized: "The WhatsApp gateway is not running.")
        case let .http(status, code, message):
            if let message, !message.isEmpty { return message }
            if let code, !code.isEmpty { return "\(code) (\(status))" }
            return String(localized: "The gateway answered with HTTP \(status).")
        case .invalidResponse:
            return String(localized: "The gateway sent a response NotchFlow could not read.")
        case let .unreadable(path, detail):
            return String(localized: "The gateway's answer to \(path) could not be read (\(detail)).")
        }
    }

    var code: String? {
        if case let .http(_, code, _) = self { return code }
        return nil
    }
}

/// A small client for the GOWA REST API on localhost.
///
/// Every call carries Basic Auth (the credentials NotchFlow generated when it
/// started the gateway) and the device slot id, so the gateway never has to
/// guess which account a request is for.
struct WhatsAppGatewayClient {
    let baseURL: URL
    let username: String
    let password: String
    let deviceID: String

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.connectionProxyDictionary = [:]
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }()

    private var authorization: String {
        let token = Data("\(username):\(password)".utf8).base64EncodedString()
        return "Basic \(token)"
    }

    // MARK: Requests

    private func makeRequest(
        _ path: String,
        method: String = "GET",
        query: [URLQueryItem] = [],
        body: [String: Any]? = nil,
        scoped: Bool = true
    ) throws -> URLRequest {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.percentEncodedPath = path
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw WhatsAppGatewayError.invalidResponse }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(authorization, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // GOWA treats state-changing GETs from browser user agents as possible
        // cross-site requests; say plainly that this is not a browser.
        request.setValue("NotchFlow", forHTTPHeaderField: "User-Agent")
        if scoped {
            request.setValue(deviceID, forHTTPHeaderField: "X-Device-Id")
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        return request
    }

    private func send<T: Decodable>(_ request: URLRequest, as type: T.Type) async throws -> T {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await Self.session.data(for: request)
        } catch let error as URLError where error.code == .cannotConnectToHost || error.code == .networkConnectionLost {
            throw WhatsAppGatewayError.notRunning
        }
        guard let http = response as? HTTPURLResponse else { throw WhatsAppGatewayError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let error = try? JSONDecoder().decode(GOWAErrorResponse.self, from: data)
            throw WhatsAppGatewayError.http(status: http.statusCode, code: error?.code, message: error?.message)
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw WhatsAppGatewayError.unreadable(path: request.url?.path ?? "?", detail: Self.describe(error))
        }
    }

    /// GOWA omits `results` entirely when it is empty (`omitempty`), so an
    /// empty list arrives as no field at all rather than as `[]`.
    private func getOptional<T: Decodable>(_ path: String, query: [URLQueryItem] = [], scoped: Bool = true) async throws -> T? {
        let response: GOWAResponse<T> = try await send(makeRequest(path, query: query, scoped: scoped), as: GOWAResponse<T>.self)
        return response.results
    }

    private func get<T: Decodable>(_ path: String, query: [URLQueryItem] = [], scoped: Bool = true) async throws -> T {
        guard let results: T = try await getOptional(path, query: query, scoped: scoped) else {
            throw WhatsAppGatewayError.invalidResponse
        }
        return results
    }

    /// For calls whose `results` may be null or a bare string.
    private func call(_ path: String, method: String = "GET", body: [String: Any]? = nil, scoped: Bool = true) async throws {
        _ = try await send(makeRequest(path, method: method, body: body, scoped: scoped), as: GOWAResponse<GOWAIgnored>.self)
    }

    @discardableResult
    private func post<T: Decodable>(_ path: String, body: [String: Any], scoped: Bool = true) async throws -> T? {
        let response: GOWAResponse<T> = try await send(
            makeRequest(path, method: "POST", body: body, scoped: scoped),
            as: GOWAResponse<T>.self
        )
        return response.results
    }

    private static func describe(_ error: Error) -> String {
        guard let decoding = error as? DecodingError else { return error.localizedDescription }
        func path(_ context: DecodingError.Context) -> String {
            context.codingPath.map { $0.intValue.map(String.init) ?? $0.stringValue }.joined(separator: ".")
        }
        switch decoding {
        case let .keyNotFound(key, context): return "missing \(path(context)).\(key.stringValue)"
        case let .typeMismatch(_, context): return "unexpected type at \(path(context))"
        case let .valueNotFound(_, context): return "null at \(path(context))"
        case let .dataCorrupted(context): return "malformed data at \(path(context))"
        @unknown default: return "unknown decoding error"
        }
    }

    private static func pathComponent(_ value: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    // MARK: App

    func appInfo() async throws -> GOWAAppInfo {
        try await get("/app/info", scoped: false)
    }

    func devices() async throws -> [GOWADevice] {
        let devices: [GOWADevice]? = try await getOptional("/devices", scoped: false)
        return devices ?? []
    }

    func createDevice() async throws {
        try await call("/devices", method: "POST", body: ["device_id": deviceID], scoped: false)
    }

    func status() async throws -> GOWAStatusResults {
        try await get("/app/status")
    }

    /// Starts a QR pairing session. The QR image expires after `qrDuration`
    /// seconds; calling this again starts a fresh session with a new code.
    func login() async throws -> GOWALoginResults {
        try await get("/app/login")
    }

    func loginWithCode(phone: String) async throws -> String? {
        struct PairCode: Decodable {
            let pairCode: String?
            enum CodingKeys: String, CodingKey { case pairCode = "pair_code" }
        }
        let result: PairCode = try await get("/app/login-with-code", query: [URLQueryItem(name: "phone", value: phone)])
        return result.pairCode
    }

    func logout() async throws {
        try await call("/app/logout")
    }

    func reconnect() async throws {
        try await call("/app/reconnect")
    }

    /// Downloads the QR code image the gateway generated. The link it returns
    /// is absolute, but it is fetched with the same credentials as the API.
    func qrImageData(link: String) async throws -> Data {
        guard let url = URL(string: link) else { throw WhatsAppGatewayError.invalidResponse }
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.percentEncodedPath = url.path
        guard let resolved = components.url else { throw WhatsAppGatewayError.invalidResponse }
        var request = URLRequest(url: resolved)
        request.setValue(authorization, forHTTPHeaderField: "Authorization")
        request.setValue(deviceID, forHTTPHeaderField: "X-Device-Id")
        request.setValue("NotchFlow", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await Self.session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw WhatsAppGatewayError.invalidResponse
        }
        return data
    }

    // MARK: Chats and messages

    func chats(limit: Int = 40) async throws -> [GOWAChat] {
        let list: GOWAChatList? = try await getOptional(
            "/chats",
            query: [URLQueryItem(name: "limit", value: String(limit)), URLQueryItem(name: "offset", value: "0")]
        )
        return list?.data ?? []
    }

    /// Messages of one chat, newest first, as the gateway returns them.
    func messages(chatJID: String, limit: Int = 50) async throws -> [GOWAMessage] {
        let list: GOWAMessageList? = try await getOptional(
            "/chat/\(Self.pathComponent(chatJID))/messages",
            query: [URLQueryItem(name: "limit", value: String(limit)), URLQueryItem(name: "offset", value: "0")]
        )
        return list?.data ?? []
    }

    func sendText(to chatJID: String, text: String, replyTo messageID: String? = nil) async throws -> String? {
        var body: [String: Any] = ["phone": chatJID, "message": text]
        if let messageID { body["reply_message_id"] = messageID }
        let result: GOWASendResults? = try await post("/send/message", body: body)
        return result?.messageID
    }

    /// Sends a file: images as photos, anything else as a document.
    func sendFile(to chatJID: String, fileURL: URL, caption: String? = nil) async throws -> String? {
        let isImage = ["jpg", "jpeg", "png", "heic", "gif", "webp"].contains(fileURL.pathExtension.lowercased())
        let path = isImage ? "/send/image" : "/send/file"
        let fieldName = isImage ? "image" : "file"
        let data = try Data(contentsOf: fileURL)
        let boundary = "NotchFlow-\(UUID().uuidString)"
        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
        }
        field("phone", chatJID)
        if let caption, !caption.isEmpty { field("caption", caption) }
        if isImage { field("compress", "false") }
        let filename = fileURL.lastPathComponent.replacingOccurrences(of: "\"", with: "")
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(fieldName)\"; filename=\"\(filename)\"\r\nContent-Type: application/octet-stream\r\n\r\n".utf8))
        body.append(data)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))

        var request = try makeRequest(path, method: "POST")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        request.timeoutInterval = 120
        let response: GOWAResponse<GOWASendResults> = try await send(request, as: GOWAResponse<GOWASendResults>.self)
        return response.results?.messageID
    }

    func markRead(messageID: String, chatJID: String) async throws {
        try await call("/message/\(Self.pathComponent(messageID))/read", method: "POST", body: ["phone": chatJID])
    }

    func sendChatPresence(chatJID: String, composing: Bool) async throws {
        try await call("/send/chat-presence", method: "POST", body: ["phone": chatJID, "action": composing ? "start" : "stop"])
    }
}
