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
import Combine
import AppKit
#if canImport(ApplicationServices)
import ApplicationServices
#endif

/// Tracks accessibility permission status and exposes helpers to request access.
@MainActor
final class AccessibilityPermissionStore: ObservableObject {
    static let shared = AccessibilityPermissionStore()

    @Published private(set) var isAuthorized: Bool = AccessibilityPermissionStore.isAccessibilityAuthorized()
    @Published private(set) var isRepairing = false
    @Published private(set) var recoveryMessage: String?

    private var pollingTask: Task<Void, Never>?

    private init() {}

    deinit {
        pollingTask?.cancel()
    }

    func refreshStatus() {
        updateAuthorizationStatus(to: Self.isAccessibilityAuthorized())
    }

    func requestAuthorizationPrompt() {
        recoveryMessage = nil
#if canImport(ApplicationServices)
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options: CFDictionary = [promptKey: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
#endif
        beginPollingForStatusChanges()
    }

    /// Removes only NotchFlow's current/legacy Accessibility records, then asks
    /// macOS to register the exact copy that is currently running. This is an
    /// explicit recovery action for stale rows left by older local builds.
    func repairAuthorization() async {
        guard !isRepairing else { return }
        isRepairing = true
        recoveryMessage = nil
        defer { isRepairing = false }

#if os(macOS)
        let identifiers = Set([
            Bundle.main.bundleIdentifier,
            "com.dhruvv620.NotchFlowFresh",
            "com.dhruvv620.NotchFlowFresh.dev",
        ].compactMap { $0 })
        let failures = await Task.detached(priority: .userInitiated) {
            var failed: [String] = []
            for identifier in identifiers {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
                process.arguments = ["reset", "Accessibility", identifier]
                process.standardOutput = FileHandle.nullDevice
                process.standardError = FileHandle.nullDevice
                do {
                    try process.run()
                    process.waitUntilExit()
                    if process.terminationStatus != 0 { failed.append(identifier) }
                } catch {
                    failed.append(identifier)
                }
            }
            return failed
        }.value

        refreshStatus()
        if failures.isEmpty {
            requestAuthorizationPrompt()
            recoveryMessage = "Old NotchFlow Accessibility entries were reset. Approve the prompt for this running copy."
        } else {
            recoveryMessage = "macOS could not reset the stale entry. Remove every NotchFlow row in Accessibility settings, add this app again, then choose Check Access."
            openSystemSettings()
        }
#else
        refreshStatus()
#endif
    }

    func revealRunningApplication() {
#if os(macOS)
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
#endif
    }

    func openSystemSettings() {
#if os(macOS)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
#endif
    }

    private func beginPollingForStatusChanges() {
        pollingTask?.cancel()
        pollingTask = Task { [weak self] in
            for _ in 0..<30 {
                try? await Task.sleep(nanoseconds: 500_000_000)
                let status = Self.isAccessibilityAuthorized()
                await MainActor.run {
                    guard let self else { return }
                    self.updateAuthorizationStatus(to: status)
                }
                if status {
                    break
                }
            }
        }
    }

    private func updateAuthorizationStatus(to newValue: Bool) {
        guard newValue != isAuthorized else { return }
        isAuthorized = newValue
        if newValue {
            recoveryMessage = nil
        }
        if !newValue {
            beginPollingForStatusChanges()
        }
    }

    private static func isAccessibilityAuthorized() -> Bool {
#if canImport(ApplicationServices)
        if AppRuntimeEnvironment.isUITesting {
            return true
        }
        return AXIsProcessTrusted()
#else
        return true
#endif
    }
}
