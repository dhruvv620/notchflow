// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Defaults
import SwiftUI

/// Settings for the distraction meter, copy-to-action, smart replies,
/// people pins and the build watcher.
struct SmartToolsSettings: View {
    @Default(.enableFocusGuard) private var enableFocusGuard
    @Default(.focusGuardSites) private var focusGuardSites
    @Default(.focusGuardApps) private var focusGuardApps
    @Default(.enableSmartReplies) private var enableSmartReplies
    @Default(.minimaxBaseURL) private var minimaxBaseURL
    @Default(.minimaxModel) private var minimaxModel
    @Default(.peoplePins) private var peoplePins
    @Default(.enableBuildWatcher) private var enableBuildWatcher
    @Default(.buildWatcherRepositories) private var repositories
    @ObservedObject private var whatsApp = WhatsAppManager.shared
    @ObservedObject private var buildWatcher = BuildWatchManager.shared

    @State private var minimaxKey = ""
    @State private var hasMinimaxKey = SecretStore.has(.minimaxAPIKey)
    @State private var minimaxStatus: String?
    @State private var testingMinimax = false
    @State private var githubToken = ""
    @State private var hasGitHubToken = SecretStore.has(.githubToken)
    @State private var githubStatus: String?
    @State private var testingGitHub = false
    @State private var copiedShellFunction = false

    private func highlightID(_ title: String) -> String { "smartTools-\(title)" }

    var body: some View {
        Form {
            focusSection
            copySection
            smartReplySection
            pinsSection
            buildSection
        }
    }

    // MARK: Distraction meter

    private var focusSection: some View {
        Section {
            Defaults.Toggle(key: .enableFocusGuard) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Distraction meter")
                    Text("During a Pomodoro focus block, the notch glows amber and counts the minutes you spend on these sites and apps.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .settingsHighlight(id: highlightID("Distraction meter"))
            if enableFocusGuard {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Sites").font(.caption.weight(.semibold))
                    TextField("youtube.com, x.com", text: $focusGuardSites, axis: .vertical)
                        .lineLimit(2...4)
                    Text("Read from the front tab of Safari, Chrome, Arc, Brave or Edge. macOS asks once to let NotchFlow control each browser.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Apps (bundle identifiers)").font(.caption.weight(.semibold))
                    TextField("com.hnc.Discord", text: $focusGuardApps)
                    HStack {
                        Button("Add the app in front") { addFrontApp() }
                            .help("Switch to the app within three seconds of clicking.")
                        Button("Reset sites") { focusGuardSites = FocusGuardPolicy.defaultSites.joined(separator: ", ") }
                    }
                    .controlSize(.small)
                }
            }
        } header: {
            Text("Focus")
        }
    }

    private func addFrontApp() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            guard let id = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
                  id != Bundle.main.bundleIdentifier else { return }
            var apps = FocusGuardPolicy.list(from: focusGuardApps)
            if !apps.contains(id.lowercased()) { apps.append(id.lowercased()) }
            focusGuardApps = apps.joined(separator: ", ")
        }
    }

    // MARK: Copy-to-action

    private var copySection: some View {
        Section {
            Defaults.Toggle(key: .enableCopyActions) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Copy-to-action")
                    Text("Copy a tracking number, date, address, flight, e-mail, phone number or sum and the notch offers Track, Add to Calendar, Directions or the answer. Text marked secret by password managers is skipped.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .settingsHighlight(id: highlightID("Copy-to-action"))
        } header: {
            Text("Clipboard")
        }
    }

    // MARK: Smart replies

    private var smartReplySection: some View {
        Section {
            Defaults.Toggle(key: .enableSmartReplies) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Smart replies")
                    Text("A sparkles button above WhatsApp and notification replies asks MiniMax for three short replies. Only the message you are replying to (and, in WhatsApp, the last few lines) is sent, and only when you tap it.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .settingsHighlight(id: highlightID("Smart replies"))
            if enableSmartReplies {
                HStack {
                    SecureField(hasMinimaxKey ? "Key saved in Keychain" : "MiniMax API key", text: $minimaxKey)
                    Button("Save") {
                        SecretStore.write(minimaxKey, for: .minimaxAPIKey)
                        minimaxKey = ""
                        hasMinimaxKey = SecretStore.has(.minimaxAPIKey)
                        minimaxStatus = hasMinimaxKey ? "Key saved." : nil
                    }
                    .disabled(minimaxKey.trimmingCharacters(in: .whitespaces).isEmpty)
                    if hasMinimaxKey {
                        Button("Remove", role: .destructive) {
                            SecretStore.write("", for: .minimaxAPIKey)
                            hasMinimaxKey = false
                            minimaxStatus = nil
                        }
                    }
                }
                TextField("API address", text: $minimaxBaseURL)
                Text("Global: https://api.minimax.io/v1 · Mainland China: https://api.minimaxi.com/v1")
                    .font(.caption).foregroundStyle(.secondary)
                TextField("Model", text: $minimaxModel)
                HStack {
                    Button(testingMinimax ? "Testing…" : "Test") { testMinimax() }
                        .disabled(!hasMinimaxKey || testingMinimax)
                    if let minimaxStatus {
                        Text(minimaxStatus).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                    }
                }
            }
        } header: {
            Text("Replies")
        }
    }

    private func testMinimax() {
        testingMinimax = true
        minimaxStatus = nil
        Task { @MainActor in
            do {
                let replies = try await SmartReplyService.fetch(sender: "Sam", message: "Are we still on for lunch tomorrow?", context: [])
                minimaxStatus = "Works: " + replies.joined(separator: " · ")
            } catch {
                minimaxStatus = error.localizedDescription
            }
            testingMinimax = false
        }
    }

    // MARK: People pins

    private var pinsSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 2) {
                Text("People pins")
                Text("Up to five WhatsApp chats as faces in the Shelf corner. Drop a file on a face to send it. Pin a chat with a right-click in the notch's WhatsApp tab.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .settingsHighlight(id: highlightID("People pins"))
            if peoplePins.isEmpty {
                Text("No one pinned yet.").foregroundStyle(.secondary)
            } else {
                ForEach(peoplePins, id: \.self) { chatID in
                    HStack {
                        WhatsAppAvatar(initial: whatsApp.chat(id: chatID)?.initial ?? "#", isGroup: WhatsAppJID.isGroup(chatID), size: 20)
                        Text(whatsApp.chat(id: chatID)?.displayName ?? WhatsAppJID.displayNumber(chatID))
                        Spacer()
                        Button("Unpin") { PeoplePins.toggle(chatID) }
                            .controlSize(.small)
                    }
                }
            }
        } header: {
            Text("Shelf")
        }
    }

    // MARK: Build watcher

    private var buildSection: some View {
        Section {
            Defaults.Toggle(key: .enableBuildWatcher) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Build watcher")
                    Text("A spinner in the notch while a GitHub Actions run or a terminal command runs, then green or red when it finishes. Click it to open the run.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .settingsHighlight(id: highlightID("Build watcher"))
            if enableBuildWatcher {
                HStack {
                    SecureField(hasGitHubToken ? "Token saved in Keychain" : "GitHub token", text: $githubToken)
                    Button("Save") {
                        SecretStore.write(githubToken, for: .githubToken)
                        githubToken = ""
                        hasGitHubToken = SecretStore.has(.githubToken)
                        buildWatcher.refreshNow()
                    }
                    .disabled(githubToken.trimmingCharacters(in: .whitespaces).isEmpty)
                    if hasGitHubToken {
                        Button("Remove", role: .destructive) {
                            SecretStore.write("", for: .githubToken)
                            hasGitHubToken = false
                            buildWatcher.refreshNow()
                        }
                    }
                }
                HStack(spacing: 4) {
                    Text("A fine-grained token with Actions: Read on the repositories below.")
                        .font(.caption).foregroundStyle(.secondary)
                    Link("Create one", destination: URL(string: "https://github.com/settings/personal-access-tokens/new")!)
                        .font(.caption)
                }
                TextField("Repositories (owner/name, comma separated)", text: $repositories)
                    .onSubmit { buildWatcher.refreshNow() }
                HStack {
                    Button(testingGitHub ? "Checking…" : "Check connection") {
                        testingGitHub = true
                        Task { @MainActor in
                            githubStatus = await BuildWatchManager.testConnection()
                            testingGitHub = false
                            buildWatcher.refreshNow()
                        }
                    }
                    .disabled(testingGitHub)
                    if let status = githubStatus ?? buildWatcher.lastError {
                        Text(status).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                }

                Defaults.Toggle(key: .buildWatcherTerminalJobs) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Watch terminal commands")
                        Text("Add this to ~/.zshrc, then run long commands as `nf npm test` or `nf bash Build.command`.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                HStack {
                    Text("nf() { … }").font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                    Spacer()
                    Button(copiedShellFunction ? "Copied" : "Copy shell function") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(BuildWatchPolicy.shellFunction, forType: .string)
                        copiedShellFunction = true
                    }
                    .controlSize(.small)
                }
            }
        } header: {
            Text("Developer")
        }
    }
}
