// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct NotchAIView: View {
    @ObservedObject private var model = NotchAIModel.shared
    @EnvironmentObject private var vm: DynamicIslandViewModel
    @State private var draft = ""
    @State private var token = UUID()
    @State private var setup = false

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Picker("Ask AI", selection: $model.provider) {
                    ForEach(NotchAIProvider.allCases) { Text($0.rawValue).tag($0) }
                }.frame(width: 160).disabled(model.running)
                Spacer()
                Button("Setup", systemImage: "gearshape") { setup.toggle() }
                Button("New chat", systemImage: "square.and.pencil") { model.newChat() }
            }
            if setup {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Install and sign in to the official Codex or Claude CLI in Terminal first. NotchFlow uses that sign-in; it does not connect to existing desktop chats.")
                    Text("Current executable: \(model.executableURL()?.path ?? "Not found")").textSelection(.enabled)
                    HStack {
                        Button("Choose \(model.provider.rawValue) executable…") { chooseExecutable() }
                        Button("Use default location") {
                            UserDefaults.standard.removeObject(forKey: "notchflowCLI-\(model.provider.executable)")
                            setup = false
                        }
                    }
                }.font(.caption).padding(10).background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if model.messages.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "sparkles").font(.largeTitle).foregroundStyle(.purple)
                                Text("Ask \(model.provider.rawValue) anything").font(.headline)
                                Text("Chat is kept in memory until New chat or quitting. Messages are sent to the selected AI provider through its CLI.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity).padding(24)
                        }
                        ForEach(model.messages) { message in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(message.role == "user" ? "You" : message.role).font(.caption.bold()).foregroundStyle(.secondary)
                                Text(message.text).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                            }.padding(12).background(.white.opacity(message.role == "user" ? 0.09 : 0.04), in: RoundedRectangle(cornerRadius: 12))
                        }
                        if model.running { ProgressView("Thinking…").controlSize(.small) }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                }
                .onChange(of: model.messages.count) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
            }
            if let error = model.error { Text(error).font(.caption).foregroundStyle(.orange).textSelection(.enabled).lineLimit(4) }
            HStack {
                TextField("Ask \(model.provider.rawValue)…", text: $draft, axis: .vertical)
                    .lineLimit(1...3).textFieldStyle(.plain).onSubmit(send)
                    .disabled(model.running)
                if model.running {
                    Button("Stop", systemImage: "stop.fill") { model.cancel() }
                } else {
                    Button(action: send) { Image(systemName: "arrow.up.circle.fill").font(.title2) }
                        .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .help("Send message")
                }
            }.padding(12).background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
        }
        .padding(12)
        .onAppear { vm.setAutoCloseSuppression(true, token: token) }
        .onDisappear { vm.setAutoCloseSuppression(false, token: token) }
        .onChange(of: model.provider) { _, _ in model.newChat() }
    }

    private func send() {
        guard !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !model.running else { return }
        model.send(draft)
        if model.running { draft = "" }
    }
    private func chooseExecutable() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose the installed \(model.provider.rawValue) command-line executable."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard FileManager.default.isExecutableFile(atPath: url.path) else { model.error = "Choose an executable file."; return }
        UserDefaults.standard.set(url.path, forKey: "notchflowCLI-\(model.provider.executable)")
        setup = false
    }
}
