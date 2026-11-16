// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Defaults
import SwiftUI

private enum CuelyMode: String, CaseIterable, Identifiable {
    case scripts = "Scripts"
    case live = "Live"

    var id: String { rawValue }
}

private enum CuelySpeed: Double, CaseIterable, Identifiable {
    case slow = 12
    case normal = 24
    case fast = 40
    case sprint = 64

    var id: Double { rawValue }
    var title: String {
        switch self {
        case .slow: return "Slow"
        case .normal: return "Normal"
        case .fast: return "Fast"
        case .sprint: return "Sprint"
        }
    }
}

/// A compact teleprompter and live transcript that stays within the regular
/// notch panel. Script editing uses a popover so it never changes panel size.
struct NotchCuelyView: View {
    @EnvironmentObject private var vm: DynamicIslandViewModel
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Default(.notchReduceMotion) private var notchReduceMotion
    @ObservedObject private var appearance = NotchAppearanceModel.shared
    @ObservedObject private var store = CuelyScriptStore.shared
    @ObservedObject private var transcription = CuelyTranscriptionManager.shared
    @AppStorage("notchflowCuelyMode") private var storedMode = CuelyMode.scripts.rawValue
    @AppStorage("notchflowCuelySpeed") private var speedValue = CuelySpeed.normal.rawValue
    @AppStorage("notchflowCuelyFontSize") private var fontSize = 17.0
    @AppStorage("notchflowCuelySelectedScriptID") private var selectedIDValue = ""
    @State private var teleprompterRunning = false
    @State private var teleprompterResetID = UUID()
    @State private var showingEditor = false
    @State private var editorID: UUID?
    @State private var editorTitle = ""
    @State private var editorText = ""
    @State private var confirmingDelete = false
    @State private var interactionToken = UUID()

    private var mode: CuelyMode {
        get { CuelyMode(rawValue: storedMode) ?? .scripts }
        nonmutating set { storedMode = newValue.rawValue }
    }
    private var speed: CuelySpeed { CuelySpeed(rawValue: speedValue) ?? .normal }
    private var motionReduced: Bool { systemReduceMotion || notchReduceMotion }
    private var selectedID: UUID? {
        get { UUID(uuidString: selectedIDValue) }
        nonmutating set { selectedIDValue = newValue?.uuidString ?? "" }
    }
    private var selectedScript: CuelyScript? {
        store.scripts.first { $0.id == selectedID }
    }

    var body: some View {
        VStack(spacing: 5) {
            header
            Group {
                switch mode {
                case .scripts: scriptsPanel
                case .live: livePanel
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if let error = store.errorMessage ?? transcription.errorMessage {
                Text(error)
                    .font(.system(size: 9))
                    .foregroundStyle(.orange)
                    .lineLimit(1)
                    .help(error)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, .dark)
        .popover(isPresented: $showingEditor, arrowEdge: .top) { editorPopover }
        .confirmationDialog("Delete this script?", isPresented: $confirmingDelete) {
            Button("Delete Script", role: .destructive, action: deleteSelected)
        } message: {
            Text("This removes the local Cuely copy. It cannot be undone.")
        }
        .onAppear {
            ensureSelection()
            transcription.refreshAccess()
            updateAutoCloseSuppression()
        }
        .onChange(of: store.scripts.map(\.id)) { _, _ in ensureSelection() }
        .onChange(of: storedMode) { _, _ in
            teleprompterRunning = false
            vm.setScrollGestureSuppression(false, token: interactionToken)
            if mode != .live { transcription.stop() }
            updateAutoCloseSuppression()
        }
        .onChange(of: teleprompterRunning) { _, _ in updateAutoCloseSuppression() }
        .onChange(of: showingEditor) { _, _ in updateAutoCloseSuppression() }
        .onChange(of: confirmingDelete) { _, _ in updateAutoCloseSuppression() }
        .onChange(of: transcription.isStarting) { _, _ in updateAutoCloseSuppression() }
        .onChange(of: transcription.isTranscribing) { _, _ in updateAutoCloseSuppression() }
        .onChange(of: transcription.isRunning) { _, _ in updateAutoCloseSuppression() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            transcription.refreshAccess()
        }
        .onDisappear {
            teleprompterRunning = false
            transcription.stop()
            vm.setAutoCloseSuppression(false, token: interactionToken)
            vm.setScrollGestureSuppression(false, token: interactionToken)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Cuely").font(.system(size: 13, weight: .semibold))
            Picker("Cuely mode", selection: Binding(get: { mode }, set: { mode = $0 })) {
                ForEach(CuelyMode.allCases) { Text($0.rawValue).tag($0) }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 142)
            Spacer(minLength: 4)
            if mode == .scripts { scriptChooser }
            else {
                Text(transcription.statusMessage)
                    .font(.caption2)
                    .foregroundStyle(transcription.isTranscribing ? Color.red : Color.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(transcription.statusMessage)
                    .accessibilityLabel("Transcription status")
                    .accessibilityValue(transcription.statusMessage)
            }
        }
    }

    private var scriptChooser: some View {
        HStack(spacing: 7) {
            Menu {
                if store.scripts.isEmpty { Text("No saved scripts") }
                ForEach(store.scripts) { script in
                    Button {
                        selectedID = script.id
                        resetTeleprompter()
                    } label: {
                        if script.id == selectedID { Label(script.title, systemImage: "checkmark") }
                        else { Text(script.title) }
                    }
                }
                if let selectedScript {
                    Divider()
                    Button("Duplicate") {
                        selectedID = store.duplicate(id: selectedScript.id)?.id ?? selectedID
                        resetTeleprompter()
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(selectedScript?.title ?? "Choose script")
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Image(systemName: "chevron.down").font(.system(size: 8))
                }
                .font(.system(size: 10, weight: .medium))
                .frame(width: 145, alignment: .trailing)
            }
            .menuStyle(.borderlessButton)
            .accessibilityLabel("Saved scripts")
            .accessibilityValue(selectedScript?.title ?? "No script selected")
            Button(action: beginNewScript) { Image(systemName: "plus") }
                .help("New script")
                .accessibilityLabel("New script")
        }
        .buttonStyle(.plain)
    }

    private var scriptsPanel: some View {
        VStack(spacing: 5) {
            if let script = selectedScript {
                CuelyTeleprompterTextView(
                    text: script.text,
                    pointSize: CGFloat(fontSize),
                    pointsPerSecond: CGFloat(speed.rawValue),
                    isRunning: teleprompterRunning,
                    resetID: teleprompterResetID,
                    onReachedEnd: { teleprompterRunning = false }
                )
                .background { NotchElementSurface(cornerRadius: 11) }
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                .onHover { vm.setScrollGestureSuppression($0, token: interactionToken) }
                .onDisappear { vm.setScrollGestureSuppression(false, token: interactionToken) }
                .accessibilityLabel("Script teleprompter")
                scriptControls(script)
            } else {
                VStack(spacing: 5) {
                    Image(systemName: "text.alignleft").font(.title3).foregroundStyle(.secondary)
                    Text("No saved scripts").font(.system(size: 12, weight: .medium))
                    Button("Add Script", action: beginNewScript).controlSize(.small)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func scriptControls(_ script: CuelyScript) -> some View {
        HStack(spacing: 7) {
            Button {
                teleprompterRunning.toggle()
            } label: {
                Label(teleprompterRunning ? "Pause" : "Start",
                      systemImage: teleprompterRunning ? "pause.fill" : "play.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .foregroundStyle(appearance.accentColor)
                    .background(appearance.accentColor.opacity(0.12), in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(script.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button(action: resetTeleprompter) { Image(systemName: "backward.end.fill") }
                .help("Return to the beginning")
                .accessibilityLabel("Return to beginning")
            HStack(spacing: 2) {
                ForEach(CuelySpeed.allCases) { value in
                    Button(value.title) { speedValue = value.rawValue }
                        .font(.system(size: 9, weight: speed == value ? .semibold : .regular))
                        .foregroundStyle(speed == value ? appearance.accentForegroundColor : Color.secondary)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(speed == value ? appearance.accentColor : Color.clear, in: Capsule())
                        .accessibilityAddTraits(speed == value ? .isSelected : [])
                }
            }
            .padding(2)
            .background(Color.white.opacity(0.05), in: Capsule())
            Spacer(minLength: 2)
            Button { fontSize = max(13, fontSize - 1) } label: { Image(systemName: "textformat.size.smaller") }
                .help("Smaller text")
                .accessibilityLabel("Decrease text size")
            Button { fontSize = min(28, fontSize + 1) } label: { Image(systemName: "textformat.size.larger") }
                .help("Larger text")
                .accessibilityLabel("Increase text size")
            Button { beginEditing(script) } label: { Image(systemName: "pencil") }
                .help("Edit script")
                .accessibilityLabel("Edit script")
            Button(role: .destructive) { confirmingDelete = true } label: { Image(systemName: "trash") }
                .help("Delete script")
                .accessibilityLabel("Delete script")
        }
        .font(.system(size: 10))
        .buttonStyle(.plain)
    }

    private var livePanel: some View {
        VStack(spacing: 5) {
            ScrollViewReader { proxy in
                ScrollView {
                    Text(transcription.transcript.isEmpty
                         ? "Start listening to create a live transcript from this Mac's microphone."
                         : transcription.transcript)
                        .font(.system(size: CGFloat(fontSize), weight: .medium))
                        .foregroundStyle(transcription.transcript.isEmpty ? Color.secondary : Color.primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 11).padding(.vertical, 8)
                    Color.clear.frame(height: 1).id("cuely-transcript-bottom")
                }
                .background { NotchElementSurface(cornerRadius: 11) }
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                .onChange(of: transcription.transcript) { _, _ in
                    if motionReduced {
                        proxy.scrollTo("cuely-transcript-bottom", anchor: .bottom)
                    } else {
                        withAnimation(.easeOut(duration: 0.12)) {
                            proxy.scrollTo("cuely-transcript-bottom", anchor: .bottom)
                        }
                    }
                }
                .onHover { vm.setScrollGestureSuppression($0, token: interactionToken) }
                .onDisappear { vm.setScrollGestureSuppression(false, token: interactionToken) }
            }
            HStack(spacing: 9) {
                Button {
                    if transcription.isRunning { transcription.stop() }
                    else { Task { await transcription.requestAndStart() } }
                } label: {
                    Label(transcription.isRunning ? "Stop" : "Start Listening",
                          systemImage: transcription.isRunning ? "stop.fill" : "mic.fill")
                        .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(transcription.isRunning ? .red : appearance.accentColor)
                if transcription.isStarting {
                    ProgressView()
                        .controlSize(.mini)
                        .accessibilityLabel("Preparing live transcription")
                }
                Spacer(minLength: 4)
                Button("Privacy") { openSpeechPrivacySettings() }
                    .font(.system(size: 10)).help("Open Cuely privacy settings")
                Button { copyTranscript() } label: { Label("Copy", systemImage: "doc.on.doc") }
                    .disabled(transcription.transcript.isEmpty)
                Button { saveTranscript() } label: { Label("Save", systemImage: "square.and.arrow.down") }
                    .disabled(transcription.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button { transcription.clear() } label: { Image(systemName: "trash") }
                    .disabled(transcription.transcript.isEmpty || transcription.isRunning)
                    .help("Clear transcript")
                    .accessibilityLabel("Clear transcript")
            }
            .font(.system(size: 10, weight: .medium))
            .buttonStyle(.plain)
        }
    }

    private var editorPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(editorID == nil ? "New Script" : "Edit Script").font(.headline)
                Spacer()
                Button("Cancel") { showingEditor = false }.controlSize(.small)
            }
            TextField("Title", text: $editorTitle).textFieldStyle(.roundedBorder)
            TextEditor(text: $editorText)
                .font(.system(size: 14))
                .scrollContentBackground(.hidden)
                .padding(7)
                .background(Color(nsColor: .textBackgroundColor).opacity(0.22), in: RoundedRectangle(cornerRadius: 8))
            if let error = store.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(1)
                    .help(error)
            }
            HStack {
                Text("Scripts stay on this Mac.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Save", action: saveEditor)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(editorTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              || editorText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16)
        .frame(width: 420, height: 300)
        .tint(appearance.accentColor)
    }

    private func ensureSelection() {
        guard selectedID == nil || !store.scripts.contains(where: { $0.id == selectedID }) else { return }
        selectedID = store.scripts.first?.id
        resetTeleprompter()
    }
    private func beginNewScript() {
        teleprompterRunning = false
        editorID = nil
        editorTitle = "Untitled script"
        editorText = "Write or paste your script here."
        showingEditor = true
    }
    private func beginEditing(_ script: CuelyScript) {
        teleprompterRunning = false
        editorID = script.id
        editorTitle = script.title
        editorText = script.text
        showingEditor = true
    }
    private func saveEditor() {
        let title = editorTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = editorText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !text.isEmpty else { return }
        if let editorID {
            guard store.update(id: editorID, title: title, text: text) != nil else { return }
            selectedID = editorID
        } else if let created = store.create(title: title, text: text) {
            selectedID = created.id
        } else {
            return
        }
        showingEditor = false
        resetTeleprompter()
    }
    private func deleteSelected() {
        guard let selectedID else { return }
        teleprompterRunning = false
        guard store.delete(id: selectedID) else { return }
        self.selectedID = store.scripts.first?.id
        resetTeleprompter()
    }
    private func resetTeleprompter() {
        teleprompterRunning = false
        teleprompterResetID = UUID()
    }
    private func copyTranscript() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(transcription.transcript, forType: .string)
    }
    private func saveTranscript() {
        let text = transcription.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        transcription.stop()
        let title = "Transcript " + Date().formatted(date: .abbreviated, time: .shortened)
        guard let created = store.create(title: title, text: text) else { return }
        selectedID = created.id
        mode = .scripts
        resetTeleprompter()
    }
    private func openSpeechPrivacySettings() {
        let anchor = transcription.microphoneAccess == .denied || transcription.microphoneAccess == .restricted
            ? "Privacy_Microphone"
            : "Privacy_SpeechRecognition"
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") else { return }
        NSWorkspace.shared.open(url)
    }
    private func updateAutoCloseSuppression() {
        let active = teleprompterRunning || showingEditor || confirmingDelete || transcription.isRunning
        vm.setAutoCloseSuppression(active, token: interactionToken)
        if !active { vm.shouldRecheckHover.toggle() }
    }
}

/// AppKit owns the scroll offset so teleprompter motion remains continuous and
/// does not rebuild SwiftUI text at 60 frames per second.
private struct CuelyTeleprompterTextView: NSViewRepresentable {
    let text: String
    let pointSize: CGFloat
    let pointsPerSecond: CGFloat
    let isRunning: Bool
    let resetID: UUID
    let onReachedEnd: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        guard let textView = scroll.documentView as? NSTextView else { return scroll }
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 11, height: 12)
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true

        context.coordinator.scrollView = scroll
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.pointsPerSecond = max(1, pointsPerSecond)
        coordinator.onReachedEnd = onReachedEnd
        coordinator.setRunning(isRunning)
        if coordinator.resetID != resetID {
            coordinator.resetID = resetID
            coordinator.didReachEnd = false
            coordinator.lastTickUptime = nil
            scroll.contentView.scroll(to: .zero)
            scroll.reflectScrolledClipView(scroll.contentView)
        }
        guard let textView = scroll.documentView as? NSTextView else { return }
        let contentChanged = coordinator.renderedText != text || coordinator.renderedPointSize != pointSize
        let viewportWidth = max(1, scroll.contentSize.width)
        let viewportHeight = max(1, scroll.contentSize.height)
        let viewportChanged = abs(coordinator.renderedViewportWidth - viewportWidth) > 0.5
            || abs(coordinator.renderedViewportHeight - viewportHeight) > 0.5
        guard contentChanged || viewportChanged else { return }
        if contentChanged {
            coordinator.renderedText = text
            coordinator.renderedPointSize = pointSize
            coordinator.didReachEnd = false
            let style = NSMutableParagraphStyle()
            style.lineSpacing = max(4, pointSize * 0.42)
            let rendered = NSAttributedString(
                string: text,
                attributes: [
                    .font: NSFont.systemFont(ofSize: pointSize, weight: .medium),
                    .foregroundColor: NSColor.white,
                    .paragraphStyle: style,
                ]
            )
            textView.textStorage?.setAttributedString(rendered)
        }
        coordinator.renderedViewportWidth = viewportWidth
        coordinator.renderedViewportHeight = viewportHeight
        coordinator.resizeDocument(textView, in: scroll)
    }

    static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
        coordinator.stopTimer()
        coordinator.isRunning = false
        coordinator.lastTickUptime = nil
        coordinator.onReachedEnd = {}
    }

    @MainActor
    final class Coordinator {
        weak var scrollView: NSScrollView?
        var timer: Timer?
        var renderedText = ""
        var renderedPointSize: CGFloat = 0
        var renderedViewportWidth: CGFloat = 0
        var renderedViewportHeight: CGFloat = 0
        var pointsPerSecond: CGFloat = 24
        var isRunning = false
        var lastTickUptime: TimeInterval?
        var resetID: UUID?
        var didReachEnd = false
        var onReachedEnd: () -> Void = {}

        func setRunning(_ running: Bool) {
            guard running != isRunning else { return }
            isRunning = running
            guard running else {
                lastTickUptime = nil
                stopTimer()
                return
            }

            if let scrollView, let document = scrollView.documentView {
                let maximum = max(0, document.bounds.height - scrollView.contentSize.height)
                let position = scrollView.contentView.bounds.origin.y
                // Pressing Start after reaching the bottom should begin again,
                // while a manual rewind resumes from the user's chosen point.
                if didReachEnd, maximum > 0, position >= maximum - 0.5 {
                    scrollView.contentView.scroll(to: .zero)
                    scrollView.reflectScrolledClipView(scrollView.contentView)
                }
            }
            didReachEnd = false
            lastTickUptime = ProcessInfo.processInfo.systemUptime
            startTimerIfNeeded()
        }

        private func startTimerIfNeeded() {
            guard timer == nil else { return }
            let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
            self.timer = timer
            RunLoop.main.add(timer, forMode: .common)
        }

        func stopTimer() {
            timer?.invalidate()
            timer = nil
        }

        func resizeDocument(_ textView: NSTextView, in scrollView: NSScrollView) {
            let width = max(1, scrollView.contentSize.width)
            let minimumHeight = max(1, scrollView.contentSize.height)
            textView.setFrameSize(NSSize(width: width, height: minimumHeight))
            guard let textContainer = textView.textContainer,
                  let layoutManager = textView.layoutManager else { return }
            layoutManager.ensureLayout(for: textContainer)
            let contentHeight = ceil(layoutManager.usedRect(for: textContainer).height
                                     + textView.textContainerInset.height * 2)
            textView.setFrameSize(NSSize(width: width, height: max(minimumHeight, contentHeight)))
            let maximum = max(0, textView.bounds.height - minimumHeight)
            let current = scrollView.contentView.bounds.origin.y
            if current > maximum {
                scrollView.contentView.scroll(to: NSPoint(x: 0, y: maximum))
                scrollView.reflectScrolledClipView(scrollView.contentView)
            }
        }

        func tick() {
            guard isRunning, let scrollView, let document = scrollView.documentView else { return }
            let maximum = max(0, document.bounds.height - scrollView.contentSize.height)
            guard maximum > 0 else {
                finishIfNeeded()
                return
            }
            let now = ProcessInfo.processInfo.systemUptime
            let elapsed = min(0.1, max(0, now - (lastTickUptime ?? now)))
            lastTickUptime = now
            let next = min(maximum, scrollView.contentView.bounds.origin.y + pointsPerSecond * CGFloat(elapsed))
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: next))
            scrollView.reflectScrolledClipView(scrollView.contentView)
            if next >= maximum { finishIfNeeded() }
        }
        private func finishIfNeeded() {
            guard !didReachEnd else { return }
            didReachEnd = true
            isRunning = false
            lastTickUptime = nil
            stopTimer()
            onReachedEnd()
        }
    }
}
