// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620

import Foundation

/// A track from Spotify's search.
struct SpotifyTrack: Equatable, Sendable {
    let uri: String
    let title: String
    let artists: String
    let album: String
    let artworkURL: URL?
}

/// Spotify's Web API for the Music tab's search: "Log in with Spotify"
/// (authorization code with PKCE, the flow Spotify asks desktop apps to use:
/// only a Client ID, no secret) and track search. Foundation only, so
/// Build.command can check it alone.
enum SpotifyAPIPolicy {
    /// Spotify only accepts a loopback IP (not "localhost") for http redirects.
    static let callbackPort: UInt16 = 47863
    static var redirectURI: String { "http://127.0.0.1:\(callbackPort)/callback" }

    /// Allowed characters of a PKCE code verifier.
    static let verifierAlphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    static func makeVerifier<G: RandomNumberGenerator>(length: Int = 64, using generator: inout G) -> String {
        String((0..<max(43, min(128, length))).map { _ in verifierAlphabet.randomElement(using: &generator)! })
    }

    /// Base64url without padding (for the code challenge).
    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// The page where you approve NotchFlow. Search needs no scopes.
    static func authorizeURL(clientID: String, codeChallenge: String, state: String) -> URL? {
        var components = URLComponents(string: "https://accounts.spotify.com/authorize")
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: clientID), URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI), URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: codeChallenge), URLQueryItem(name: "state", value: state),
        ]
        return components?.url
    }

    static let tokenURL = URL(string: "https://accounts.spotify.com/api/token")!

    /// Form bodies for the token endpoint.
    static func tokenBody(code: String, verifier: String, clientID: String) -> String {
        formEncoded(["grant_type": "authorization_code", "code": code, "redirect_uri": redirectURI,
                     "client_id": clientID, "code_verifier": verifier])
    }

    static func refreshBody(refreshToken: String, clientID: String) -> String {
        formEncoded(["grant_type": "refresh_token", "refresh_token": refreshToken, "client_id": clientID])
    }

    static func formEncoded(_ fields: [String: String]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return fields.sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }
            .joined(separator: "&")
    }

    struct Token: Equatable {
        let accessToken: String
        let refreshToken: String?
        let expiresIn: TimeInterval
    }

    static func token(from data: Data) -> Token? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = object["access_token"] as? String, !access.isEmpty else { return nil }
        return Token(accessToken: access, refreshToken: object["refresh_token"] as? String,
                     expiresIn: (object["expires_in"] as? Double) ?? 3600)
    }

    static func errorMessage(in data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let description = object["error_description"] as? String { return description }
        if let error = object["error"] as? [String: Any] { return error["message"] as? String }
        return object["error"] as? String
    }

    /// Track search (Development Mode apps return at most 10).
    static func searchURL(_ query: String, limit: Int = 10) -> URL? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return nil }
        var components = URLComponents(string: "https://api.spotify.com/v1/search")
        components?.queryItems = [URLQueryItem(name: "q", value: trimmed), URLQueryItem(name: "type", value: "track"),
                                  URLQueryItem(name: "limit", value: String(min(10, max(1, limit)))),
                                  URLQueryItem(name: "market", value: "from_token")]
        return components?.url
    }

    static func tracks(from data: Data) -> [SpotifyTrack] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tracks = object["tracks"] as? [String: Any],
              let items = tracks["items"] as? [[String: Any]] else { return [] }
        return items.compactMap { item in
            guard let uri = item["uri"] as? String, uri.hasPrefix("spotify:track:"), let title = item["name"] as? String else { return nil }
            let artists = (item["artists"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }.joined(separator: ", ")
            let album = item["album"] as? [String: Any]
            // Images come largest first; take a small one.
            let images = (album?["images"] as? [[String: Any]] ?? []).compactMap { $0["url"] as? String }
            return SpotifyTrack(uri: uri, title: title, artists: artists, album: album?["name"] as? String ?? "",
                                artworkURL: (images.last ?? images.first).flatMap(URL.init(string:)))
        }
    }

    /// The code (or error) from the browser's request to the callback:
    /// "GET /callback?code=…&state=… HTTP/1.1".
    static func callback(fromRequest request: String) -> (code: String?, state: String?, error: String?)? {
        guard let line = request.split(separator: "\r\n").first ?? request.split(separator: "\n").first else { return nil }
        let parts = line.split(separator: " ")
        guard parts.count >= 2, parts[0] == "GET", parts[1].hasPrefix("/callback"),
              let components = URLComponents(string: "http://127.0.0.1" + parts[1]) else { return nil }
        func value(_ name: String) -> String? { components.queryItems?.first { $0.name == name }?.value }
        return (value("code"), value("state"), value("error"))
    }
}
