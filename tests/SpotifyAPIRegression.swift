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
                    && authorize.contains("code_challenge_method=S256&code_challenge=chal&state=st")
                    && authorize.hasSuffix("&scope=user-read-private%20user-read-playback-state%20user-modify-playback-state"), "Authorize URL: \(authorize)")
        try require(P.tokenBody(code: "c d", verifier: "v", clientID: "id")
                    == "client_id=id&code=c%20d&code_verifier=v&grant_type=authorization_code&redirect_uri=http%3A%2F%2F127.0.0.1%3A47863%2Fcallback",
                    "Token body: \(P.tokenBody(code: "c d", verifier: "v", clientID: "id"))")
        try require(P.refreshBody(refreshToken: "r", clientID: "id") == "client_id=id&grant_type=refresh_token&refresh_token=r", "Refresh body")
        let token = P.token(from: Data(#"{"access_token":"A","token_type":"Bearer","expires_in":3600,"refresh_token":"R"}"#.utf8))
        try require(token == P.Token(accessToken: "A", refreshToken: "R", expiresIn: 3600) && token?.hasRequiredScopes == true, "Token")
        let scoped = P.token(from: Data(#"{"access_token":"A","expires_in":3600,"scope":"user-read-private user-read-email"}"#.utf8))
        let unscoped = P.token(from: Data(#"{"access_token":"A","expires_in":3600,"scope":""}"#.utf8))
        try require(scoped?.hasRequiredScopes == true && unscoped?.hasRequiredScopes == false, "Granted scopes")
        let playback = P.token(from: Data(#"{"access_token":"A","expires_in":3600,"scope":"user-modify-playback-state user-read-private user-read-playback-state"}"#.utf8))
        try require(playback?.canControlPlayback == true && scoped?.canControlPlayback == false && token?.canControlPlayback == false,
                    "Playback scopes")
        let devicesJSON = #"""
        {"devices":[
          {"id":"phone1","is_active":false,"is_restricted":false,"name":"My iPhone","type":"Smartphone"},
          {"id":"mac1","is_active":false,"is_restricted":false,"name":"My MacBook Pro","type":"Computer"},
          {"id":"tv","is_active":false,"is_restricted":true,"name":"TV","type":"TV"},
          {"id":null,"is_active":false,"name":"Ghost","type":"Computer"}
        ]}
        """#
        let devices = P.devices(from: Data(devicesJSON.utf8))
        try require(devices.count == 3, "Devices: \(devices)")
        try require(P.device(toPlayOn: devices, computerName: "my macbook pro")?.id == "mac1", "This Mac")
        try require(P.device(toPlayOn: devices, computerName: "Other")?.id == "mac1", "The only computer")
        try require(P.device(toPlayOn: devices.filter { $0.type != "Computer" }, computerName: nil) == nil, "Not an idle phone")
        let phoneActive = devices.map { P.Device(id: $0.id, name: $0.name, type: $0.type, isActive: $0.id == "phone1", isRestricted: $0.isRestricted) }
        try require(P.device(toPlayOn: phoneActive, computerName: "My MacBook Pro")?.id == "phone1", "The device in use")
        try require(P.playURL(deviceID: "mac1")?.absoluteString == "https://api.spotify.com/v1/me/player/play?device_id=mac1", "Play URL")
        try require(String(decoding: P.playBody(trackURI: "spotify:track:X"), as: UTF8.self) == #"{"uris":["spotify:track:X"]}"#, "Play body")
        try require(String(decoding: P.playBody(trackURI: "spotify:track:X", albumURI: "spotify:album:A"), as: UTF8.self)
                    == #"{"context_uri":"spotify:album:A","offset":{"uri":"spotify:track:X"}}"#, "Play inside the album")
        try require(P.isScopeError("Insufficient client scope") && !P.isScopeError("Forbidden") && !P.isScopeError(nil), "Scope error")
        try require(P.token(from: Data(#"{"error":"invalid_grant","error_description":"Invalid authorization code"}"#.utf8)) == nil
                    && P.errorMessage(in: Data(#"{"error":"invalid_grant","error_description":"Invalid authorization code"}"#.utf8)) == "Invalid authorization code",
                    "Token error")
        try require(P.errorMessage(in: Data(#"{"error":{"status":403,"message":"Forbidden"}}"#.utf8)) == "Forbidden", "API error")
        let search = P.searchURL("i wanna love you akon", market: "in", limit: 50)?.absoluteString ?? ""
        try require(search == "https://api.spotify.com/v1/search?q=i%20wanna%20love%20you%20akon&type=track&limit=10&market=IN",
                    "Search URL: \(search)")
        try require(P.searchURL("i wanna love you", market: nil)?.absoluteString.contains("market") == false
                    && P.searchURL("i wanna love you", market: "from_token")?.absoluteString.contains("market") == false, "No market")
        let json = #"""
        {"tracks":{"items":[
          {"uri":"spotify:track:0RIAsvP8qBNxaMBkyZpuCX","name":"I Wanna Love You","artists":[{"name":"Akon"},{"name":"Snoop Dogg"}],
           "album":{"name":"Konvicted","uri":"spotify:album:2fXzPAsm","images":[{"url":"https://i.scdn.co/image/640"},{"url":"https://i.scdn.co/image/300"},{"url":"https://i.scdn.co/image/64"}]}},
          {"uri":"spotify:episode:1","name":"Podcast"}
        ]}}
        """#
        let tracks = P.tracks(from: Data(json.utf8))
        try require(tracks.count == 1 && tracks[0].artists == "Akon, Snoop Dogg" && tracks[0].album == "Konvicted"
                    && tracks[0].artworkURL?.absoluteString == "https://i.scdn.co/image/64"
                    && tracks[0].albumURI == "spotify:album:2fXzPAsm", "Tracks: \(tracks)")
        let ok = P.callback(fromRequest: "GET /callback?code=AQB_x-1&state=st HTTP/1.1\r\nHost: 127.0.0.1:47863\r\n\r\n")
        try require(ok?.code == "AQB_x-1" && ok?.state == "st" && ok?.error == nil, "Callback")
        try require(P.callback(fromRequest: "GET /callback?error=access_denied&state=st HTTP/1.1\r\n\r\n")?.error == "access_denied", "Denied")
        try require(P.callback(fromRequest: "GET /favicon.ico HTTP/1.1\r\n\r\n") == nil, "Not the callback")
        print("Spotify API: OK")
    }
}
