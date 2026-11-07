// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

enum NotchAIProvider: String, CaseIterable, Identifiable, Sendable {
    case codex = "Codex", claude = "Claude"
    var id: String { rawValue }
    var executable: String { rawValue.lowercased() }
}

/// Runs a signed-in CLI directly, without interpolating prompts into a shell.
/// File-backed output avoids pipe deadlocks; cancellation and a deadline bound each request.
final class NotchCLIRunner: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false
    func cancel() {
        lock.lock()
        cancelled = true
        let process = process
        lock.unlock()
        if let process, process.isRunning {
            process.terminate()
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            }
        }
    }

    func execute(executable: URL, provider: NotchAIProvider, prompt: String, timeout: TimeInterval = 120) throws -> String {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("NotchFlow-AI-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: folder) }
        let resultURL = folder.appendingPathComponent("reply.txt")
        let process = Process()
        process.executableURL = executable
        process.currentDirectoryURL = folder
        switch provider {
        case .codex:
            process.arguments = ["exec", "--ephemeral", "--sandbox", "read-only", "--skip-git-repo-check", "--output-last-message", resultURL.path, "-"]
        case .claude:
            process.arguments = ["--print", "--output-format", "text", "--tools", "", "--disable-slash-commands", "--no-session-persistence"]
        }
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = ([executable.deletingLastPathComponent().path, "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", environment["PATH"] ?? ""]).joined(separator: ":")
        process.environment = environment
        let inputURL = folder.appendingPathComponent("prompt.txt")
        let stdoutURL = folder.appendingPathComponent("stdout.txt")
        let stderrURL = folder.appendingPathComponent("stderr.txt")
        try Data(prompt.utf8).write(to: inputURL, options: .atomic)
        _ = FileManager.default.createFile(atPath: stdoutURL.path, contents: nil)
        _ = FileManager.default.createFile(atPath: stderrURL.path, contents: nil)
        let input = try FileHandle(forReadingFrom: inputURL)
        let output = try FileHandle(forWritingTo: stdoutURL)
        let errors = try FileHandle(forWritingTo: stderrURL)
        defer { try? input.close(); try? output.close(); try? errors.close() }
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors
        lock.lock()
        if cancelled { lock.unlock(); throw CancellationError() }
        self.process = process
        do { try process.run() } catch { lock.unlock(); throw error }
        lock.unlock()
        let deadline = DispatchWorkItem { [weak self] in self?.cancel() }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: deadline)
        defer { deadline.cancel() }
        // File-backed streams avoid pipe deadlocks and keep partial output off the UI thread.
        process.waitUntilExit()
        lock.lock()
        let wasCancelled = cancelled
        self.process = nil
        lock.unlock()
        guard !wasCancelled else { throw cliError("Request stopped or reached the two-minute limit.") }
        guard process.terminationStatus == 0 else {
            let diagnostic = String(decoding: (try? readBounded(stderrURL)) ?? Data(), as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw cliError(diagnostic.isEmpty ? "CLI failed. Check installation and sign-in in Terminal." : String(diagnostic.prefix(2000)))
        }
        let data: Data
        if provider == .codex {
            let size = (try resultURL.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0
            guard size <= 2_000_000 else { throw cliError("Reply exceeded the size limit.") }
            data = try Data(contentsOf: resultURL)
        } else { data = try readBounded(stdoutURL) }
        let reply = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reply.isEmpty else { throw cliError("The CLI returned no response. Check sign-in and CLI compatibility in Terminal.") }
        return reply
    }
    private func readBounded(_ url: URL) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        return try handle.read(upToCount: 2_000_000) ?? Data()
    }
    private func cliError(_ text: String) -> NSError { NSError(domain: "NotchFlow.AI", code: 1, userInfo: [NSLocalizedDescriptionKey: text]) }
}
