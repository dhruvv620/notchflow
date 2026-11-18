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

import Foundation

/// Runs the GOWA gateway as a child process of Atoll.
///
/// It binds to 127.0.0.1 only, behind Basic Auth with a password generated
/// for this launch, with its web dashboard and MCP endpoint switched off:
/// nothing but Atoll is meant to talk to it. It does not mark messages read,
/// download media, or go "online" on its own, so the phone keeps getting
/// notifications and read receipts are only sent when the user reads in Atoll.
final class WhatsAppGatewayProcess {
    struct Configuration {
        let port: UInt16
        let username: String
        let password: String
        let webhookURL: String
        let webhookSecret: String
        let deviceName: String
    }

    private var process: Process?
    private var logHandle: FileHandle?
    var onExit: ((Int32) -> Void)?

    var isRunning: Bool { process?.isRunning ?? false }

    private static var pidFile: URL {
        WhatsAppGatewayInstaller.rootDirectory.appendingPathComponent("gateway.pid")
    }

    static var logFile: URL {
        WhatsAppGatewayInstaller.rootDirectory.appendingPathComponent("gateway.log")
    }

    func start(_ configuration: Configuration) throws {
        stop()
        Self.terminateOrphan()

        let fileManager = FileManager.default
        try fileManager.createDirectory(at: WhatsAppGatewayInstaller.dataDirectory, withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = WhatsAppGatewayInstaller.binaryURL
        process.currentDirectoryURL = WhatsAppGatewayInstaller.dataDirectory
        process.arguments = [
            "rest",
            "--host=127.0.0.1",
            "--port=\(configuration.port)",
            "--basic-auth=\(configuration.username):\(configuration.password)",
            "--os=\(configuration.deviceName)",
            "--ui-enabled=false",
            "--mcp-enabled=false",
            "--webhook=\(configuration.webhookURL)",
            "--webhook-secret=\(configuration.webhookSecret)",
            "--webhook-events=message,message.ack,message.revoked,message.edited,message.deleted,device.logged_out",
            "--auto-mark-read=false",
            "--auto-download-media=false",
            "--presence-on-connect=unavailable",
        ]
        var environment = ProcessInfo.processInfo.environment
        // A user-level proxy would otherwise also be applied to the webhook
        // calls back to 127.0.0.1.
        environment["NO_PROXY"] = "127.0.0.1,localhost"
        process.environment = environment

        // Keep the last run's output for troubleshooting; truncate per launch
        // so it cannot grow without bound.
        fileManager.createFile(atPath: Self.logFile.path, contents: nil)
        if let handle = try? FileHandle(forWritingTo: Self.logFile) {
            logHandle = handle
            process.standardOutput = handle
            process.standardError = handle
        } else {
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
        }

        process.terminationHandler = { [weak self] finished in
            let status = finished.terminationStatus
            DispatchQueue.main.async {
                guard let self, self.process === finished else { return }
                self.process = nil
                try? self.logHandle?.close()
                self.logHandle = nil
                try? FileManager.default.removeItem(at: Self.pidFile)
                self.onExit?(status)
            }
        }

        try process.run()
        self.process = process
        try? String(process.processIdentifier).write(to: Self.pidFile, atomically: true, encoding: .utf8)
    }

    func stop() {
        guard let process else { return }
        self.process = nil
        process.terminationHandler = nil
        if process.isRunning {
            process.terminate()
            // Give the gateway a moment to close its database cleanly.
            let deadline = Date().addingTimeInterval(3)
            while process.isRunning && Date() < deadline {
                usleep(50_000)
            }
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
        }
        try? logHandle?.close()
        logHandle = nil
        try? FileManager.default.removeItem(at: Self.pidFile)
    }

    /// A gateway left behind by a previous Atoll that crashed or was killed
    /// would still hold the WhatsApp session database open. Stop it, but only
    /// if the process with the recorded pid really is our gateway binary.
    private static func terminateOrphan() {
        guard let text = try? String(contentsOf: pidFile, encoding: .utf8),
              let pid = Int32(text.trimmingCharacters(in: .whitespacesAndNewlines)),
              pid > 0 else { return }
        defer { try? FileManager.default.removeItem(at: pidFile) }

        guard let command = commandPath(of: pid),
              command == WhatsAppGatewayInstaller.binaryURL.path else { return }
        kill(pid, SIGTERM)
        let deadline = Date().addingTimeInterval(3)
        while kill(pid, 0) == 0 && Date() < deadline {
            usleep(50_000)
        }
        if kill(pid, 0) == 0 {
            kill(pid, SIGKILL)
        }
    }

    private static func commandPath(of pid: Int32) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-p", String(pid), "-o", "comm="]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        process.waitUntilExit()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return output.isEmpty ? nil : output
    }

    /// Picks a free loopback TCP port for the gateway's API.
    static func freePort() -> UInt16? {
        let socketFD = socket(AF_INET, SOCK_STREAM, 0)
        guard socketFD >= 0 else { return nil }
        defer { close(socketFD) }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr.s_addr = inet_addr("127.0.0.1")

        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(socketFD, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else { return nil }

        var assigned = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let named = withUnsafeMutablePointer(to: &assigned) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(socketFD, $0, &length)
            }
        }
        guard named == 0 else { return nil }
        return UInt16(bigEndian: assigned.sin_port)
    }
}
