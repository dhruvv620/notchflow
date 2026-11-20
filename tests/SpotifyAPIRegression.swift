// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620

import Foundation

@main
struct SpotifyAPIRegression {
    static func main() throws {
        func require(_ value: @autoclosure () -> Bool, _ message: String) throws {
            if !value() { throw NSError(domain: "SpotifyAPIRegression", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        typealias P = SpotifyAPIPolicy
        var generator = SystemRandomNumberGenerator()
        let verifier = P.makeVerifier(using: &generator)
        try require(verifier.count == 64 && verifier.allSatisfy { P.verifierAlphabet.contains($0) }, "Verifier")
        try require(P.base64URL(Data([0xfb, 0xff, 0xfe])) == "-__-", "Base64url: \(P.base64URL(Data([0xfb, 0xff, 0xfe])))")
        let authorize = P.authorizeURL(clientID: "abc123", codeChallenge: "chal", state: "st")?.absoluteString ?? ""
        try require(authorize.hasPrefix("https://accounts.spotify.com/authorize?client_id=abc123&response_type=code")
                    && authorize.contains("redirect_uri=http://127.0.0.1:47863/callback")
                    && authorize.contains("code_challenge_method=S256&code_challenge=chal&state=st"), "Authorize URL: \(authorize)")
        try require(P.tokenBody(code: "c d", verifier: "v", clientID: "id")
                    == "client_id=id&code=c%20d&code_verifier=v&grant_type=authorization_code&redirect_uri=http%3A%2F%2F127.0.0.1%3A47863%2Fcallback",
                    "Token body: \(P.tokenBody(code: "c d", verifier: "v", clientID: "id"))")
        try require(P.refreshBody(refreshToken: "r", clientID: "id") == "client_id=id&grant_type=refresh_token&refresh_token=r", "Refresh body")
        let token = P.token(from: Data(#"{"access_token":"A","token_type":"Bearer","expires_in":3600,"refresh_token":"R"}"#.utf8))
        try require(token == P.Token(accessToken: "A", refreshToken: "R", expiresIn: 3600), "Token")
        try require(P.token(from: Data(#"{"error":"invalid_grant","error_description":"Invalid authorization code"}"#.utf8)) == nil
                    && P.errorMessage(in: Data(#"{"error":"invalid_grant","error_description":"Invalid authorization code"}"#.utf8)) == "Invalid authorization code",
                    "Token error")
        try require(P.errorMessage(in: Data(#"{"error":{"status":403,"message":"Forbidden"}}"#.utf8)) == "Forbidden", "API error")
        let search = P.searchURL("i wanna love you akon", limit: 50)?.absoluteString ?? ""
        try require(search == "https://api.spotify.com/v1/search?q=i%20wanna%20love%20you%20akon&type=track&limit=10&market=from_token",
                    "Search URL: \(search)")
        let json = #"""
        {"tracks":{"items":[
          {"uri":"spotify:track:0RIAsvP8qBNxaMBkyZpuCX","name":"I Wanna Love You","artists":[{"name":"Akon"},{"name":"Snoop Dogg"}],
           "album":{"name":"Konvicted","images":[{"url":"https://i.scdn.co/image/640"},{"url":"https://i.scdn.co/image/300"},{"url":"https://i.scdn.co/image/64"}]}},
          {"uri":"spotify:episode:1","name":"Podcast"}
        ]}}
        """#
        let tracks = P.tracks(from: Data(json.utf8))
        try require(tracks.count == 1 && tracks[0].artists == "Akon, Snoop Dogg" && tracks[0].album == "Konvicted"
                    && tracks[0].artworkURL?.absoluteString == "https://i.scdn.co/image/64", "Tracks: \(tracks)")
        let ok = P.callback(fromRequest: "GET /callback?code=AQB_x-1&state=st HTTP/1.1\r\nHost: 127.0.0.1:47863\r\n\r\n")
        try require(ok?.code == "AQB_x-1" && ok?.state == "st" && ok?.error == nil, "Callback")
        try require(P.callback(fromRequest: "GET /callback?error=access_denied&state=st HTTP/1.1\r\n\r\n")?.error == "access_denied", "Denied")
        try require(P.callback(fromRequest: "GET /favicon.ico HTTP/1.1\r\n\r\n") == nil, "Not the callback")
        print("Spotify API: OK")
    }
}
