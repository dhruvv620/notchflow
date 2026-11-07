// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

@main
struct NotchCLIRunnerTests {
    static func main() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("NotchFlow-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        func executable(_ name: String, _ body: String) throws -> URL {
            let url = folder.appendingPathComponent(name)
            try Data(("#!/bin/sh\nset -eu\n" + body).utf8).write(to: url)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
            return url
        }
        func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
            if !condition() { throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        }

        // The prompt reaches stdin verbatim, including shell metacharacters and Unicode.
        let echo = try executable("echo-cli", "/bin/cat\n")
        let prompt = "Hi 🧽\n$(touch should-not-exist) `echo injection` ; \\\"quoted\\\""
        let reply = try NotchCLIRunner().execute(executable: echo, provider: .claude, prompt: prompt)
        try check(reply == prompt, "Prompt changed in transit")
        try check(!FileManager.default.fileExists(atPath: folder.appendingPathComponent("should-not-exist").path), "Prompt executed as shell code")

        // Codex answers are read from its output file, never from diagnostic stdout.
        let codex = try executable("codex-cli", #"""
        result=''
        while [ "$#" -gt 0 ]; do
            if [ "$1" = '--output-last-message' ]; then shift; result="$1"; fi
            shift
        done
        /bin/cat > "$result"
        echo 'diagnostic output'
        """#)
        let codexReply = try NotchCLIRunner().execute(executable: codex, provider: .codex, prompt: "Codex reply")
        try check(codexReply == "Codex reply", "Used Codex diagnostic output as its answer")

        // Large stderr must not fill a pipe and deadlock the process.
        let noisy = try executable("noisy-cli", "/usr/bin/yes diagnostic | /usr/bin/head -n 20000 >&2\necho answer\n")
        let noisyReply = try NotchCLIRunner().execute(executable: noisy, provider: .claude, prompt: "test", timeout: 5)
        try check(noisyReply == "answer", "Large stderr prevented the answer")

        let failing = try executable("failing-cli", "echo 'Please sign in' >&2\nexit 7\n")
        do {
            _ = try NotchCLIRunner().execute(executable: failing, provider: .claude, prompt: "test")
            throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Nonzero exit was accepted"])
        } catch {
            try check(error.localizedDescription.contains("Please sign in"), "CLI error was lost")
        }

        let empty = try executable("empty-cli", "exit 0\n")
        do {
            _ = try NotchCLIRunner().execute(executable: empty, provider: .claude, prompt: "test")
            throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Empty reply was accepted"])
        } catch {
            try check(error.localizedDescription.contains("no response"), "Empty reply was not reported")
        }

        let cancelled = NotchCLIRunner()
        cancelled.cancel()
        do {
            _ = try cancelled.execute(executable: echo, provider: .claude, prompt: "test")
            throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cancelled request was launched"])
        } catch is CancellationError { }

        let slow = try executable("slow-cli", "exec /bin/sleep 30\n")
        let start = Date()
        do {
            _ = try NotchCLIRunner().execute(executable: slow, provider: .claude, prompt: "test", timeout: 0.15)
            throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Timeout was ignored"])
        } catch {
            try check(error.localizedDescription.contains("limit"), "Timeout was not reported")
            try check(Date().timeIntervalSince(start) < 5, "Timeout did not stop the process promptly")
        }
        print("NotchFlow CLI runner checks passed")
    }
}
