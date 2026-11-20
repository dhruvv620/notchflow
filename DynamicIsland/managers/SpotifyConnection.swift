// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620

import AppKit
import CryptoKit
import Defaults
import Network
import SwiftUI

extension Defaults.Keys {
    /// The Client ID of your own Spotify developer app (not a secret).
    static let spotifyClientID = Key<String>("spotifyClientID", default: "")
}

/// "Log in with Spotify" for the Music tab's search: authorization code with
/// PKCE (only your app's Client ID, no secret), a one-time callback on
/// 127.0.0.1, and a refresh token kept in the Keychain.
@MainActor
final class SpotifyConnection: ObservableObject {
    static let shared = SpotifyConnection()

    enum State: Equatable { case notConnected, connecting, connected, failed(String) }
    @Published private(set) var state: State = .notConnected

    private static let refreshAccount = "spotify-refresh-token"
    private var accessToken: String?
    private var accessExpiry = Date.distantPast
    private var listener: NWListener?
    private var pendingVerifier: String?
    private var pendingState: String?

    private init() {
        if SecretStore.read(account: Self.refreshAccount) != nil { state = .connected }
    }

    var isConnected: Bool { state == .connected }

    // MARK: Connecting

    func connect() {
        let clientID = Defaults[.spotifyClientID].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clientID.isEmpty else {
            state = .failed("Paste your app's Client ID first.")
            return
        }
        var generator = SystemRandomNumberGenerator()
        let verifier = SpotifyAPIPolicy.makeVerifier(using: &generator)
        let challenge = SpotifyAPIPolicy.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
        let stateToken = UUID().uuidString
        guard let url = SpotifyAPIPolicy.authorizeURL(clientID: clientID, codeChallenge: challenge, state: stateToken) else { return }
        do {
            try startListening()
        } catch {
            state = .failed("Couldn't listen for Spotify's answer on port \(SpotifyAPIPolicy.callbackPort): \(error.localizedDescription)")
            return
        }
        pendingVerifier = verifier
        pendingState = stateToken
        state = .connecting
        NSWorkspace.shared.open(url)
    }

    func disconnect() {
        SecretStore.write("", account: Self.refreshAccount)
        accessToken = nil
        accessExpiry = .distantPast
        stopListening()
        state = .notConnected
    }

    private func startListening() throws {
        stopListening()
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv4(.loopback),
                                                               port: NWEndpoint.Port(rawValue: SpotifyAPIPolicy.callbackPort)!)
        parameters.allowLocalEndpointReuse = true
        let listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { [weak self] connection in
            connection.start(queue: .main)
            connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { data, _, _, _ in
                let request = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                MainActor.assumeIsolated { self?.handle(request, on: connection) }
            }
        }
        listener.start(queue: .main)
        self.listener = listener
        // Give up after five minutes.
        DispatchQueue.main.asyncAfter(deadline: .now() + 300) { [weak self] in
            guard let self, self.state == .connecting else { return }
            self.stopListening()
            self.state = .failed("Spotify didn't answer. Try Connect again.")
        }
    }

    private func stopListening() {
        listener?.cancel()
        listener = nil
    }

    private func handle(_ request: String, on connection: NWConnection) {
        guard let callback = SpotifyAPIPolicy.callback(fromRequest: request) else {
            respond(connection, status: "404 Not Found", body: "")
            return
        }
        let ok = callback.error == nil && callback.code != nil && callback.state == pendingState
        respond(connection, status: "200 OK", body: ok
            ? "<h2>NotchFlow is connected to Spotify.</h2><p>You can close this tab.</p>"
            : "<h2>Spotify didn't connect.</h2><p>\(callback.error ?? "Try again from NotchFlow's settings.")</p>")
        stopListening()
        guard ok, let code = callback.code, let verifier = pendingVerifier else {
            state = .failed(callback.error == "access_denied" ? "You declined in Spotify." : "Spotify didn't connect. Try again.")
            return
        }
        pendingVerifier = nil
        Task { await exchange(code: code, verifier: verifier) }
    }

    private func respond(_ connection: NWConnection, status: String, body: String) {
        let html = "<!doctype html><meta charset=utf-8><body style=\"font:15px -apple-system;padding:40px\">\(body)</body>"
        let response = "HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(html.utf8.count)\r\nConnection: close\r\n\r\n\(html)"
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
    }

    private func exchange(code: String, verifier: String) async {
        let clientID = Defaults[.spotifyClientID].trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let token = try await requestToken(body: SpotifyAPIPolicy.tokenBody(code: code, verifier: verifier, clientID: clientID))
            store(token)
            state = .connected
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    // MARK: Tokens

    private struct APIError: LocalizedError {
        let errorDescription: String?
    }

    private func requestToken(body: String) async throws -> SpotifyAPIPolicy.Token {
        var request = URLRequest(url: SpotifyAPIPolicy.tokenURL, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(body.utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200, let token = SpotifyAPIPolicy.token(from: data) else {
            throw APIError(errorDescription: "Spotify: " + (SpotifyAPIPolicy.errorMessage(in: data) ?? "the sign-in didn't work."))
        }
        return token
    }

    private func store(_ token: SpotifyAPIPolicy.Token) {
        accessToken = token.accessToken
        accessExpiry = Date().addingTimeInterval(token.expiresIn - 60)
        // Spotify may hand out a new refresh token; keep the newest.
        if let refresh = token.refreshToken { SecretStore.write(refresh, account: Self.refreshAccount) }
    }

    /// A valid access token, refreshed when it has run out.
    private func validToken() async throws -> String {
        if let accessToken, Date() < accessExpiry { return accessToken }
        guard let refresh = SecretStore.read(account: Self.refreshAccount) else {
            state = .notConnected
            throw APIError(errorDescription: "Connect Spotify in Settings › Music.")
        }
        let clientID = Defaults[.spotifyClientID].trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let token = try await requestToken(body: SpotifyAPIPolicy.refreshBody(refreshToken: refresh, clientID: clientID))
            store(token)
            return token.accessToken
        } catch {
            state = .failed("Spotify signed NotchFlow out. Connect again in Settings › Music.")
            SecretStore.write("", account: Self.refreshAccount)
            throw error
        }
    }

    // MARK: Search

    func search(_ query: String) async throws -> [SpotifyTrack] {
        guard let url = SpotifyAPIPolicy.searchURL(query) else { return [] }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("Bearer \(try await validToken())", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 { accessExpiry = .distantPast }
        guard status == 200 else {
            throw APIError(errorDescription: "Spotify search: " + (SpotifyAPIPolicy.errorMessage(in: data) ?? "error \(status)"))
        }
        return SpotifyAPIPolicy.tracks(from: data)
    }
}

/// Settings › Music: connect your Spotify, so the Music tab's search uses
/// Spotify's own catalog and plays the exact track.
struct SpotifyConnectRow: View {
    @ObservedObject private var spotify = SpotifyConnection.shared
    @Default(.spotifyClientID) private var clientID
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Spotify search")
                    Text(status).font(.caption).foregroundStyle(statusColor)
                }
                Spacer()
                switch spotify.state {
                case .connected:
                    Button("Disconnect", role: .destructive) { spotify.disconnect() }
                case .connecting:
                    ProgressView().controlSize(.small)
                default:
                    Button("Connect Spotify") { spotify.connect() }
                        .disabled(clientID.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            if !spotify.isConnected {
                Text("""
                One time: 1. Open developer.spotify.com/dashboard, sign in and click Create app (any name; tick Web API). \
                2. Add this Redirect URI and save. 3. Paste the app's Client ID below and click Connect Spotify, then Agree in the browser. \
                Spotify asks the app's owner to have Premium.
                """)
                .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Text(SpotifyAPIPolicy.redirectURI).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    Button(copied ? "Copied" : "Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(SpotifyAPIPolicy.redirectURI, forType: .string)
                        copied = true
                    }
                    .controlSize(.small)
                    Button("Open Spotify dashboard") {
                        NSWorkspace.shared.open(URL(string: "https://developer.spotify.com/dashboard")!)
                    }
                    .controlSize(.small)
                }
                TextField("Client ID", text: $clientID)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
            }
        }
    }

    private var status: String {
        switch spotify.state {
        case .connected: return "Connected: Spotify searches use Spotify's catalog and play the exact track."
        case .connecting: return "Waiting for you to agree in the browser…"
        case .notConnected: return "Not connected: Spotify songs are matched through song.link."
        case .failed(let reason): return reason
        }
    }

    private var statusColor: Color {
        if case .failed = spotify.state { return .orange }
        return .secondary
    }
}
