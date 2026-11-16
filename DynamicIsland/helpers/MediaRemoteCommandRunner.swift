// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// The existing bundled adapter executes inside the system Perl host on modern
/// macOS. Reading and sending commands must use that same host, not load
/// MediaRemote directly into the app process.
enum MediaRemoteCommandRunner {
    enum Failure: Error { case unavailable, commandFailed(Int32) }

    static func arguments(_ command: [String]) throws -> [String] {
        guard let script = Bundle.main.url(forResource: "mediaremote-adapter", withExtension: "pl"),
              let resources = Bundle.main.resourceURL else { throw Failure.unavailable }
        let framework = resources.appendingPathComponent("MediaRemoteAdapter.framework").path
        guard FileManager.default.fileExists(atPath: framework) else { throw Failure.unavailable }
        return [script.path, framework] + command
    }

    static func run(_ command: [String]) async throws -> Data {
        let arguments = try arguments(command)
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                let output = Pipe()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
                process.arguments = arguments
                process.standardOutput = output
                process.standardError = FileHandle.nullDevice
                do {
                    try process.run()
                    let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
                    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 5, execute: timeout)
                    let data = output.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    timeout.cancel()
                    guard process.terminationStatus == 0 else { throw Failure.commandFailed(process.terminationStatus) }
                    continuation.resume(returning: data)
                } catch { continuation.resume(throwing: error) }
            }
        }
    }
}
