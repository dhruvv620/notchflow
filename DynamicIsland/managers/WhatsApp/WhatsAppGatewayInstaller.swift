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

/// Downloads GOWA (go-whatsapp-web-multidevice) release binaries from GitHub.
///
/// GOWA is the gateway that speaks WhatsApp's multi-device protocol; NotchFlow
/// only talks to it over HTTP on localhost. Its macOS releases are zip files
/// named `whatsapp_<version>_darwin_<arch>.zip`, each holding a single
/// executable, with SHA-256 sums in `checksums-macos.txt`. A download is only
/// installed when its sum matches that file.
enum WhatsAppGatewayInstaller {
    static let repository = "aldinokemal/go-whatsapp-web-multidevice"

    struct Release: Equatable {
        let version: String
        let assetURL: URL
        let assetName: String
        let checksumsURL: URL?
    }

    enum InstallError: LocalizedError {
        case noAssetForThisMac
        case checksumMissing
        case checksumMismatch
        case binaryNotFound
        case unzipFailed

        var errorDescription: String? {
            switch self {
            case .noAssetForThisMac:
                return String(localized: "This GOWA release has no build for this Mac.")
            case .checksumMissing:
                return String(localized: "The release has no checksum for the download, so it was not installed.")
            case .checksumMismatch:
                return String(localized: "The download did not match its published checksum, so it was not installed.")
            case .binaryNotFound:
                return String(localized: "The downloaded archive did not contain the gateway.")
            case .unzipFailed:
                return String(localized: "The downloaded archive could not be opened.")
            }
        }
    }

    // MARK: Locations

    static var rootDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base
            .appendingPathComponent("NotchFlow", isDirectory: true)
            .appendingPathComponent("WhatsAppGateway", isDirectory: true)
    }

    static var binaryDirectory: URL { rootDirectory.appendingPathComponent("bin", isDirectory: true) }

    /// The gateway's working directory: its database (the WhatsApp session)
    /// and any media it stores live here.
    static var dataDirectory: URL { rootDirectory.appendingPathComponent("data", isDirectory: true) }

    static var binaryURL: URL { binaryDirectory.appendingPathComponent("gowa") }

    static var isInstalled: Bool {
        FileManager.default.isExecutableFile(atPath: binaryURL.path)
    }

    private static var architecture: String {
        #if arch(arm64)
        return "arm64"
        #else
        return "amd64"
        #endif
    }

    // MARK: Release lookup

    static func latestRelease() async throws -> Release {
        struct GitHubRelease: Decodable {
            struct Asset: Decodable {
                let name: String
                let browserDownloadURL: URL
                enum CodingKeys: String, CodingKey {
                    case name
                    case browserDownloadURL = "browser_download_url"
                }
            }
            let tagName: String
            let assets: [Asset]
            enum CodingKeys: String, CodingKey {
                case tagName = "tag_name"
                case assets
            }
        }

        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("NotchFlow", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw WhatsAppGatewayError.http(status: http.statusCode, code: nil, message: String(localized: "GitHub could not be asked for the latest gateway release."))
        }
        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        let suffix = "_darwin_\(architecture).zip"
        guard let asset = release.assets.first(where: { $0.name.hasPrefix("whatsapp_") && $0.name.hasSuffix(suffix) }) else {
            throw InstallError.noAssetForThisMac
        }
        let checksums = release.assets.first(where: { $0.name == "checksums-macos.txt" })
        let version = release.tagName.hasPrefix("v") ? String(release.tagName.dropFirst()) : release.tagName
        return Release(version: version, assetURL: asset.browserDownloadURL, assetName: asset.name, checksumsURL: checksums?.browserDownloadURL)
    }

    // MARK: Install

    /// Downloads, verifies and installs a release, replacing any installed
    /// binary. The caller stops the running gateway first.
    static func install(_ release: Release, progress: @escaping @Sendable (Double) -> Void) async throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: binaryDirectory, withIntermediateDirectories: true)

        guard let checksumsURL = release.checksumsURL else { throw InstallError.checksumMissing }
        let (checksumData, _) = try await URLSession.shared.data(from: checksumsURL)
        guard let expected = expectedChecksum(in: String(decoding: checksumData, as: UTF8.self), for: release.assetName) else {
            throw InstallError.checksumMissing
        }

        progress(0.05)
        let archive = try await download(release.assetURL, progress: { fraction in progress(0.05 + fraction * 0.85) })
        defer { try? fileManager.removeItem(at: archive) }

        let digest = SHA256.hash(data: try Data(contentsOf: archive))
        let actual = digest.map { String(format: "%02x", $0) }.joined()
        guard actual == expected.lowercased() else { throw InstallError.checksumMismatch }

        let staging = fileManager.temporaryDirectory.appendingPathComponent("notchflow-gowa-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: staging) }

        try unzip(archive, to: staging)
        guard let extracted = findExecutable(in: staging) else { throw InstallError.binaryNotFound }

        let destination = binaryURL
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: extracted, to: destination)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destination.path)
        removexattr(destination.path, "com.apple.quarantine", 0)
        progress(1)
    }

    static func uninstall() {
        try? FileManager.default.removeItem(at: binaryURL)
    }

    /// Removes the gateway's database and media, which holds the linked
    /// WhatsApp session. Only done when the user unlinks.
    static func removeData() {
        try? FileManager.default.removeItem(at: dataDirectory)
    }

    static func expectedChecksum(in checksums: String, for assetName: String) -> String? {
        for line in checksums.split(whereSeparator: \.isNewline) {
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            guard parts.count >= 2 else { continue }
            let name = parts[parts.count - 1].trimmingCharacters(in: CharacterSet(charactersIn: "*"))
            if name == assetName { return parts[0] }
        }
        return nil
    }

    private static func download(_ url: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let (bytes, response) = try await URLSession.shared.bytes(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw WhatsAppGatewayError.http(status: http.statusCode, code: nil, message: String(localized: "The gateway download failed."))
        }
        let expectedLength = response.expectedContentLength
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent("notchflow-gowa-\(UUID().uuidString).zip")
        FileManager.default.createFile(atPath: destination.path, contents: nil)
        let handle = try FileHandle(forWritingTo: destination)
        defer { try? handle.close() }

        var buffer = Data()
        buffer.reserveCapacity(1 << 16)
        var received: Int64 = 0
        var lastReported = -1
        for try await byte in bytes {
            buffer.append(byte)
            if buffer.count >= 1 << 16 {
                try handle.write(contentsOf: buffer)
                received += Int64(buffer.count)
                buffer.removeAll(keepingCapacity: true)
                if expectedLength > 0 {
                    let percent = Int(Double(received) / Double(expectedLength) * 100)
                    if percent != lastReported {
                        lastReported = percent
                        progress(min(1, Double(percent) / 100))
                    }
                }
            }
        }
        if !buffer.isEmpty {
            try handle.write(contentsOf: buffer)
        }
        return destination
    }

    private static func unzip(_ archive: URL, to directory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", archive.path, directory.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw InstallError.unzipFailed }
    }

    /// The archive holds one executable named after the platform
    /// (`darwin-arm64`); look for it anywhere in the tree rather than at a
    /// fixed path, since the archive layout is GoReleaser's to change.
    private static func findExecutable(in directory: URL) -> URL? {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey]) else { return nil }
        var fallback: URL?
        for case let url as URL in enumerator {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            let name = url.lastPathComponent
            if name.hasPrefix("darwin-") { return url }
            if fallback == nil, !name.contains("."), name != "LICENSE", name != "LICENCE" {
                fallback = url
            }
        }
        return fallback
    }
}
