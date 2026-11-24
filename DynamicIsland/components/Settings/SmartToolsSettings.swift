// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620

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
    @Default(.aiProvider) private var aiProviderRaw
    @Default(.peoplePins) private var peoplePins
    @Default(.enableBuildWatcher) private var enableBuildWatcher
    @Default(.buildWatcherRepositories) private var repositories
    @ObservedObject private var whatsApp = WhatsAppManager.shared
    @ObservedObject private var buildWatcher = BuildWatchManager.shared

    @State private var aiKey = ""
    @State private var aiBaseURL = AIClient.baseURL(for: AIClient.provider)
    @State private var aiModel = AIClient.model(for: AIClient.provider)
    @State private var savedKeys = Set(AIProvider.allCases.filter { AIClient.hasKey($0) })
    @State private var aiStatus: String?
    @State private var testingAI = false
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
            aiProviderSection
            smartReplySection
            pinsSection
            buildSection
        }
    }

    // MARK: Distraction meter

    private var focusSection: some View {
        Section {
            SettingsToggle(key: .enableFocusGuard, title: "Distraction meter",
                           detail: "During a Pomodoro, the notch glows amber and counts minutes on these sites and apps.",
                           highlightID: highlightID("Distraction meter"))
            if enableFocusGuard {
                Group {
                    TextField("Sites", text: $focusGuardSites, prompt: Text("youtube.com, x.com"), axis: .vertical)
                        .lineLimit(1...4)
                    TextField("Apps", text: $focusGuardApps, prompt: Text("com.hnc.Discord"))
                    HStack {
                        SettingsRowLabel(title: "Add an app", detail: "Click, then switch to the app within three seconds.")
                        Spacer()
                        Button("Reset Sites") { focusGuardSites = FocusGuardPolicy.defaultSites.joined(separator: ", ") }
                        Button("Add the App in Front") { addFrontApp() }
                    }
                }
                .padding(.leading, 16)
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
            SettingsToggle(key: .enableCopyActions, title: "Copy-to-action",
                           detail: "Copy a date, address, flight or tracking number and the notch offers what to do with it.",
                           highlightID: highlightID("Copy-to-action"))
        } header: {
            Text("Clipboard")
        }
    }

    // MARK: AI provider

    private var aiProvider: AIProvider { AIProvider(rawValue: aiProviderRaw) ?? .minimax }

    private var aiProviderSection: some View {
        Section {
            Picker("Provider", selection: Binding(get: { aiProvider }, set: { select($0) })) {
                ForEach(AIProvider.allCases, id: \.self) { provider in
                    Text(savedKeys.contains(provider) ? "\(provider.title)  \u{2713}" : provider.title).tag(provider)
                }
            }
            .settingsHighlight(id: highlightID("AI provider"))
            if aiProvider.needsKey || aiProvider == .custom {
                HStack {
                    SecureField(savedKeys.contains(aiProvider) ? "Key saved in Keychain"
                                : aiProvider == .custom ? "API key (if your server needs one)" : "\(aiProvider.title) API key",
                                text: $aiKey)
                    Button("Save") {
                        AIClient.setKey(aiKey, for: aiProvider)
                        aiKey = ""
                        refreshKeys()
                        aiStatus = savedKeys.contains(aiProvider) ? "Key saved." : nil
                    }
                    .settingsPrimaryButton()
                    .disabled(aiKey.trimmingCharacters(in: .whitespaces).isEmpty)
                    if savedKeys.contains(aiProvider) {
                        Button("Remove") {
                            AIClient.setKey("", for: aiProvider)
                            refreshKeys()
                            aiStatus = nil
                        }
                        .settingsDestructiveButton()
                    }
                }
            }
            TextField("API address", text: $aiBaseURL, prompt: Text(aiProvider == .custom ? "https://your-server/v1" : aiProvider.defaultBaseURL))
                .onSubmit { AIClient.setBaseURL(aiBaseURL, for: aiProvider) }
                .onChange(of: aiBaseURL) { _, value in AIClient.setBaseURL(value, for: aiProvider) }
            TextField("Model", text: $aiModel, prompt: Text(aiProvider.defaultModel.isEmpty ? "model name" : aiProvider.defaultModel))
                .onChange(of: aiModel) { _, value in AIClient.setModel(value, for: aiProvider) }
            HStack {
                if let aiStatus {
                    SettingsStatus(text: aiStatus, kind: aiStatus.hasPrefix("Works") || aiStatus == "Key saved." ? .ok : .warn)
                        .lineLimit(3)
                } else {
                    SettingsStatus(text: AIClient.isReady(aiProvider) ? "Ready" : "Not set up yet",
                                   kind: AIClient.isReady(aiProvider) ? .ok : .warn)
                }
                Spacer()
                if aiBaseURL != aiProvider.defaultBaseURL || aiModel != aiProvider.defaultModel, aiProvider != .custom {
                    Button("Use Defaults") {
                        aiBaseURL = aiProvider.defaultBaseURL
                        aiModel = aiProvider.defaultModel
                    }
                }
                if let page = aiProvider.keyPage, let url = URL(string: page) {
                    Button("Get a Key") { NSWorkspace.shared.open(url) }
                }
                Button(testingAI ? "Testing…" : "Test") { testAI() }
                    .disabled(!AIClient.isReady(aiProvider) || testingAI)
            }
        } header: {
            Text("AI provider")
        } footer: {
            Text(providerFooter)
        }
    }

    private var providerFooter: String {
        var parts = ["Used by smart replies and promises in any language. Keys stay in your Keychain."]
        switch aiProvider {
        case .minimax: parts.append("MiniMax in mainland China: https://api.minimaxi.com/v1.")
        case .ollama, .lmStudio: parts.append("Runs on this Mac: nothing leaves it. Start \(aiProvider == .ollama ? "Ollama" : "LM Studio's server") and use a model you've downloaded.")
        case .openRouter: parts.append("One key for models from OpenAI, Anthropic, Google, Meta and more: write the model as provider/model.")
        case .custom: parts.append("Any server that speaks the OpenAI chat-completions API (vLLM, LiteLLM, Azure OpenAI, a company proxy…).")
        case .anthropic: parts.append("For lower cost, claude-haiku-5-5 works well for both features.")
        default: break
        }
        return parts.joined(separator: " ")
    }

    private func select(_ provider: AIProvider) {
        aiProviderRaw = provider.rawValue
        aiKey = ""
        aiStatus = nil
        aiBaseURL = AIClient.baseURL(for: provider)
        aiModel = AIClient.model(for: provider)
    }

    private func refreshKeys() {
        savedKeys = Set(AIProvider.allCases.filter { AIClient.hasKey($0) })
    }

    private func testAI() {
        testingAI = true
        aiStatus = nil
        let provider = aiProvider
        Task { @MainActor in
            do {
                let replies = try await SmartReplyService.fetch(sender: "Sam", message: "Kal lunch pe mil rahe hain na?", context: [], provider: provider)
                aiStatus = "Works: " + replies.joined(separator: " · ")
            } catch {
                aiStatus = error.localizedDescription
            }
            testingAI = false
        }
    }

    // MARK: Smart replies

    private var smartReplySection: some View {
        Section {
            SettingsToggle(key: .enableSmartReplies, title: "Smart replies",
                           detail: "Three short replies in the message's own language. Only sent when you tap the sparkles.",
                           highlightID: highlightID("Smart replies"))
        } header: {
            Text("Replies")
        }
    }

    // MARK: People pins

    private var pinsSection: some View {
        Section {
            SettingsRowLabel(title: "People pins",
                             detail: "Up to five WhatsApp chats as faces in the Shelf. Drop a file on one to send it.")
                .settingsHighlight(id: highlightID("People pins"))
            if peoplePins.isEmpty {
                Text("No one pinned yet. Right-click a chat in the notch's WhatsApp tab.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                ForEach(peoplePins, id: \.self) { chatID in
                    HStack {
                        WhatsAppAvatar(initial: whatsApp.chat(id: chatID)?.initial ?? "#", isGroup: WhatsAppJID.isGroup(chatID), size: 20)
                        Text(whatsApp.chat(id: chatID)?.displayName ?? WhatsAppJID.displayNumber(chatID))
                        Spacer()
                        Button("Unpin") { PeoplePins.toggle(chatID) }
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
            SettingsToggle(key: .enableBuildWatcher, title: "Build watcher",
                           detail: "A spinner while GitHub Actions or a terminal command runs, then green or red.",
                           highlightID: highlightID("Build watcher"))
            if enableBuildWatcher {
                HStack {
                    SecureField(hasGitHubToken ? "Token saved in Keychain" : "GitHub token", text: $githubToken)
                    Button("Save") {
                        SecretStore.write(githubToken, for: .githubToken)
                        githubToken = ""
                        hasGitHubToken = SecretStore.has(.githubToken)
                        buildWatcher.refreshNow()
                    }
                    .settingsPrimaryButton()
                    .disabled(githubToken.trimmingCharacters(in: .whitespaces).isEmpty)
                    if hasGitHubToken {
                        Button("Remove") {
                            SecretStore.write("", for: .githubToken)
                            hasGitHubToken = false
                            buildWatcher.refreshNow()
                        }
                        .settingsDestructiveButton()
                    }
                }
                HStack(spacing: 4) {
                    Text("A fine-grained token with Actions: Read.")
                        .font(.caption).foregroundStyle(.secondary)
                    Link("Create one", destination: URL(string: "https://github.com/settings/personal-access-tokens/new")!)
                        .font(.caption)
                }
                TextField("Repositories", text: $repositories, prompt: Text("owner/name, owner/other"))
                    .onSubmit { buildWatcher.refreshNow() }
                HStack {
                    if let status = githubStatus ?? buildWatcher.lastError {
                        SettingsStatus(text: status, kind: status.lowercased().contains("connected") || status.lowercased().hasPrefix("works") ? .ok : .warn)
                            .lineLimit(2)
                    }
                    Spacer()
                    Button(testingGitHub ? "Checking…" : "Check Connection") {
                        testingGitHub = true
                        Task { @MainActor in
                            githubStatus = await BuildWatchManager.testConnection()
                            testingGitHub = false
                            buildWatcher.refreshNow()
                        }
                    }
                    .disabled(testingGitHub)
                }

                SettingsToggle(key: .buildWatcherTerminalJobs, title: "Watch terminal commands",
                               detail: "Run long commands as `nf npm test`. Copy the shell function below into ~/.zshrc.")
                HStack {
                    Text("nf() { … }").font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                    Spacer()
                    Button(copiedShellFunction ? "Copied" : "Copy Shell Function") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(BuildWatchPolicy.shellFunction, forType: .string)
                        copiedShellFunction = true
                    }
                }
            }
        } header: {
            Text("Developer")
        }
    }
}
