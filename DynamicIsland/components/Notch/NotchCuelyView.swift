// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620

import AppKit
import Defaults
import SwiftUI

private enum CuelyMode: String, CaseIterable, Identifiable {
    // Raw values are kept from the first Cuely so saved choices still load.
    case scripts = "Scripts"
    case live = "Live"

    var id: String { rawValue }
    var title: String {
        switch self {
        case .scripts: return "Auto-scroll"
        case .live: return "Follow voice"
        }
    }
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

/// A teleprompter with a script library on the right. In Follow voice it
/// listens while you read and keeps your place: words already read dim, the
/// next word lights up, and the text scrolls so the line you are on stays
/// near the top. Nothing is recorded or saved; audio only goes to Apple's
/// speech recognizer while listening.
struct NotchCuelyView: View {
    @EnvironmentObject private var vm: DynamicIslandViewModel
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Default(.notchReduceMotion) private var notchReduceMotion
    @Default(.cuelyPanelSize) private var panelSizeValue
    @ObservedObject private var appearance = NotchAppearanceModel.shared
    @ObservedObject private var store = CuelyScriptStore.shared
    @ObservedObject private var transcription = CuelyTranscriptionManager.shared
    @AppStorage("notchflowCuelyMode") private var storedMode = CuelyMode.live.rawValue
    @AppStorage("notchflowCuelySpeed") private var speedValue = CuelySpeed.normal.rawValue
    @AppStorage("notchflowCuelyFontSize") private var fontSize = 20.0
    @AppStorage("notchflowCuelySelectedScriptID") private var selectedIDValue = ""
    @AppStorage("notchflowCuelyShowsLibrary") private var showsLibrary = true
    @State private var teleprompterRunning = false
    @State private var teleprompterResetID = UUID()
    @State private var scriptWords: [CuelyWord] = []
    @State private var followCursor = 0
    @State private var showingEditor = false
    @State private var editorID: UUID?
    @State private var editorTitle = ""
    @State private var editorText = ""
    @State private var deleteCandidate: CuelyScript?
    @State private var interactionToken = UUID()

    private var mode: CuelyMode {
        get { CuelyMode(rawValue: storedMode) ?? .live }
        nonmutating set { storedMode = newValue.rawValue }
    }
    private var speed: CuelySpeed { CuelySpeed(rawValue: speedValue) ?? .normal }
    private var panelSize: CuelyPanelSize { CuelyPanelSize(rawValue: panelSizeValue) ?? .regular }
    private var motionReduced: Bool { systemReduceMotion || notchReduceMotion }
    private var selectedID: UUID? {
        get { UUID(uuidString: selectedIDValue) }
        nonmutating set { selectedIDValue = newValue?.uuidString ?? "" }
    }
    private var selectedScript: CuelyScript? {
        store.scripts.first { $0.id == selectedID }
    }
    private var isFollowing: Bool { mode == .live && transcription.isRunning }

    var body: some View {
        VStack(spacing: 6) {
            header
            HStack(spacing: 8) {
                prompter
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if showsLibrary {
                    library
                        .frame(width: panelSize == .regular ? 176 : 210)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if selectedScript != nil { controls }
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
        .animation(NotchTokens.Motion.standard, value: showsLibrary)
        .popover(isPresented: $showingEditor, arrowEdge: .top) { editorPopover }
        .confirmationDialog("Delete \u{201C}\(deleteCandidate?.title ?? "")\u{201D}?",
                            isPresented: Binding(get: { deleteCandidate != nil }, set: { if !$0 { deleteCandidate = nil } })) {
            Button("Delete Script", role: .destructive) {
                if let deleteCandidate { delete(deleteCandidate) }
            }
        } message: {
            Text("This removes the script from this Mac. It cannot be undone.")
        }
        .onAppear {
            ensureSelection()
            reloadWords()
            transcription.refreshAccess()
            updateAutoCloseSuppression()
        }
        .onChange(of: store.scripts.map(\.id)) { _, _ in ensureSelection() }
        .onChange(of: selectedScript?.text) { _, _ in reloadWords() }
        .onChange(of: transcription.transcript) { _, transcript in follow(transcript) }
        .onChange(of: storedMode) { _, _ in
            teleprompterRunning = false
            vm.setScrollGestureSuppression(false, token: interactionToken)
            if mode != .live { transcription.stop() }
            updateAutoCloseSuppression()
        }
        .onChange(of: teleprompterRunning) { _, _ in updateAutoCloseSuppression() }
        .onChange(of: showingEditor) { _, _ in updateAutoCloseSuppression() }
        .onChange(of: deleteCandidate?.id) { _, _ in updateAutoCloseSuppression() }
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

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            Text("Cuely").font(NotchTokens.Typography.title)
            Picker("Cuely mode", selection: Binding(get: { mode }, set: { mode = $0 })) {
                ForEach(CuelyMode.allCases) { Text($0.title).tag($0) }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 196)
            Spacer(minLength: 4)
            if mode == .live {
                HStack(spacing: 5) {
                    Circle()
                        .fill(transcription.isTranscribing ? Color.red : Color.secondary.opacity(0.5))
                        .frame(width: 6, height: 6)
                    Text(liveStatus)
                        .font(NotchTokens.Typography.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .help(transcription.statusMessage)
            }
            Menu {
                ForEach(CuelyPanelSize.allCases, id: \.rawValue) { size in
                    Button {
                        panelSizeValue = size.rawValue
                    } label: {
                        if size == panelSize { Label(size.title, systemImage: "checkmark") } else { Text(size.title) }
                    }
                }
            } label: {
                Image(systemName: panelSize == .extraLarge
                      ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 11, weight: .medium))
            } primaryAction: {
                panelSizeValue = panelSize.next.rawValue
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Panel size: \(panelSize.title). Click to make Cuely bigger; hold for sizes.")
            NotchIconButton(symbol: "sidebar.right", help: showsLibrary ? "Hide scripts" : "Show scripts") {
                showsLibrary.toggle()
            }
        }
    }

    private var liveStatus: String {
        if transcription.isStarting { return "Starting…" }
        if transcription.isTranscribing { return "Listening" }
        switch transcription.authorization {
        case .denied: return "Microphone or Speech access is off"
        case .restricted: return "Speech is restricted"
        default: return "Not listening"
        }
    }

    // MARK: Prompter

    @ViewBuilder
    private var prompter: some View {
        if let script = selectedScript {
            CuelyTeleprompterTextView(
                text: script.text,
                pointSize: CGFloat(fontSize),
                pointsPerSecond: CGFloat(speed.rawValue),
                isRunning: mode == .scripts && teleprompterRunning,
                resetID: teleprompterResetID,
                follow: mode == .live ? CuelyFollowState(words: scriptWords, cursor: followCursor) : nil,
                accentColor: NSColor(appearance.accentColor),
                animatesFollow: !motionReduced,
                onReachedEnd: { teleprompterRunning = false },
                onPickCharacter: { location in jump(toCharacter: location) }
            )
            .background { NotchElementSurface(cornerRadius: 12) }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(alignment: .top) {
                // A soft edge so text scrolls out under the header.
                LinearGradient(colors: [Color.black.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 14)
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: 12, topTrailingRadius: 12, style: .continuous))
                    .allowsHitTesting(false)
            }
            .onHover { vm.setScrollGestureSuppression($0, token: interactionToken) }
            .onDisappear { vm.setScrollGestureSuppression(false, token: interactionToken) }
            .accessibilityLabel("Script teleprompter")
        } else {
            NotchEmptyState(symbol: "text.alignleft", title: "No scripts yet",
                            detail: "Add a script, then read it aloud in Follow voice and Cuely keeps your place.") {
                NotchPillButton(title: "Add Script", symbol: "plus", prominent: true, action: beginNewScript)
            }
            .background { NotchElementSurface(cornerRadius: 12) }
        }
    }

    // MARK: Library

    private var library: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("Scripts")
                    .font(NotchTokens.Typography.captionEmphasis)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                NotchIconButton(symbol: "plus", help: "New script", size: 20, action: beginNewScript)
            }
            if store.scripts.isEmpty {
                Text("Your saved scripts appear here.")
                    .font(NotchTokens.Typography.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 3) {
                        ForEach(store.scripts) { script in
                            libraryRow(script)
                        }
                    }
                }
                .onHover { vm.setScrollGestureSuppression($0, token: interactionToken) }
            }
        }
        .padding(7)
        .frame(maxHeight: .infinity, alignment: .top)
        .background { NotchElementSurface(cornerRadius: 12) }
    }

    private func libraryRow(_ script: CuelyScript) -> some View {
        let isSelected = script.id == selectedID
        let firstLine = script.text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        return Button {
            select(script)
        } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text(script.title)
                    .font(NotchTokens.Typography.bodyEmphasis)
                    .lineLimit(1)
                Text(firstLine)
                    .font(NotchTokens.Typography.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(readingTime(script.text))
                    .font(.system(size: 9).monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: NotchTokens.Radius.row, style: .continuous)
                    .fill(isSelected ? appearance.accentColor.opacity(0.22) : Color.white.opacity(0.05))
            )
            .contentShape(RoundedRectangle(cornerRadius: NotchTokens.Radius.row, style: .continuous))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Edit") { beginEditing(script) }
            Button("Duplicate") {
                if let copy = store.duplicate(id: script.id) { select(copy) }
            }
            Divider()
            Button("Delete…", role: .destructive) { deleteCandidate = script }
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func readingTime(_ text: String) -> String {
        let words = text.split { $0.isWhitespace || $0.isNewline }.count
        let minutes = Double(words) / 150
        return minutes < 1 ? "\(words) words · under a minute" : "\(words) words · ~\(Int(minutes.rounded())) min"
    }

    // MARK: Controls

    @ViewBuilder
    private var controls: some View {
        HStack(spacing: 7) {
            switch mode {
            case .live: liveControls
            case .scripts: scrollControls
            }
            Spacer(minLength: 2)
            Button { fontSize = max(13, fontSize - 2) } label: { Image(systemName: "textformat.size.smaller") }
                .help("Smaller text")
                .accessibilityLabel("Decrease text size")
            Button { fontSize = min(44, fontSize + 2) } label: { Image(systemName: "textformat.size.larger") }
                .help("Larger text")
                .accessibilityLabel("Increase text size")
            if let script = selectedScript {
                Button { beginEditing(script) } label: { Image(systemName: "pencil") }
                    .help("Edit script")
                    .accessibilityLabel("Edit script")
            }
        }
        .font(.system(size: 10))
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var liveControls: some View {
        Button {
            if transcription.isRunning {
                transcription.stop()
            } else if let script = selectedScript {
                Task { await transcription.startFollowing(scriptText: script.text) }
            }
        } label: {
            Label(transcription.isRunning ? "Stop" : "Start reading",
                  systemImage: transcription.isRunning ? "stop.fill" : "mic.fill")
                .font(.system(size: 10, weight: .semibold))
                .padding(.horizontal, 10).padding(.vertical, 4)
                .foregroundStyle(transcription.isRunning ? Color.white : appearance.accentForegroundColor)
                .background(Capsule().fill(transcription.isRunning ? Color.red : appearance.accentColor))
        }
        .buttonStyle(.plain)
        if transcription.isStarting {
            ProgressView().controlSize(.mini)
        }
        Button { jump(toWord: 0) } label: { Image(systemName: "backward.end.fill") }
            .help("Back to the beginning")
            .accessibilityLabel("Back to the beginning")
        if !scriptWords.isEmpty {
            ProgressView(value: Double(min(followCursor, scriptWords.count)), total: Double(scriptWords.count))
                .progressViewStyle(.linear)
                .tint(appearance.accentColor)
                .frame(width: 70)
                .help("\(min(followCursor, scriptWords.count)) of \(scriptWords.count) words read")
        }
        Text(isFollowing ? "Read aloud; click any word to jump there" : "Click a word to start from there")
            .font(NotchTokens.Typography.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        if transcription.authorization == .denied || transcription.authorization == .restricted {
            Button("Privacy Settings") { openSpeechPrivacySettings() }
                .font(.system(size: 10, weight: .medium))
        }
    }

    @ViewBuilder
    private var scrollControls: some View {
        Button {
            teleprompterRunning.toggle()
        } label: {
            Label(teleprompterRunning ? "Pause" : "Start",
                  systemImage: teleprompterRunning ? "pause.fill" : "play.fill")
                .font(.system(size: 10, weight: .semibold))
                .padding(.horizontal, 10).padding(.vertical, 4)
                .foregroundStyle(appearance.accentForegroundColor)
                .background(Capsule().fill(appearance.accentColor))
        }
        .buttonStyle(.plain)
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
    }

    // MARK: Editor

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
        .frame(width: 520, height: 400)
        .tint(appearance.accentColor)
    }

    // MARK: Actions

    private func ensureSelection() {
        guard selectedID == nil || !store.scripts.contains(where: { $0.id == selectedID }) else { return }
        selectedID = store.scripts.first?.id
        reloadWords()
        resetTeleprompter()
    }

    private func select(_ script: CuelyScript) {
        guard script.id != selectedID else { return }
        transcription.stop()
        selectedID = script.id
        reloadWords()
        resetTeleprompter()
    }

    private func reloadWords() {
        scriptWords = selectedScript.map { CuelyVoiceFollowPolicy.words(in: $0.text) } ?? []
        followCursor = min(followCursor, scriptWords.count)
    }

    /// Moves the place marker to match what was just heard.
    private func follow(_ transcript: String) {
        guard mode == .live, transcription.isRunning, !scriptWords.isEmpty else { return }
        let spoken = CuelyVoiceFollowPolicy.spokenWords(in: transcript)
        guard let next = CuelyVoiceFollowPolicy.advance(script: scriptWords, spoken: spoken, cursor: followCursor),
              next != followCursor else { return }
        followCursor = next
    }

    private func jump(toCharacter location: Int) {
        guard mode == .live, let index = CuelyVoiceFollowPolicy.wordIndex(atCharacter: location, in: scriptWords) else { return }
        jump(toWord: index)
    }

    private func jump(toWord index: Int) {
        followCursor = min(max(0, index), scriptWords.count)
        // Start a fresh transcript so words heard before the jump cannot pull
        // the place marker back to where it was.
        if transcription.isRunning, let script = selectedScript {
            transcription.stop()
            Task { await transcription.startFollowing(scriptText: script.text) }
        }
    }

    private func beginNewScript() {
        teleprompterRunning = false
        editorID = nil
        editorTitle = "Untitled script"
        editorText = ""
        showingEditor = true
    }

    private func beginEditing(_ script: CuelyScript) {
        teleprompterRunning = false
        transcription.stop()
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
            followCursor = 0
        } else {
            return
        }
        showingEditor = false
        reloadWords()
        resetTeleprompter()
    }

    private func delete(_ script: CuelyScript) {
        if script.id == selectedID {
            teleprompterRunning = false
            transcription.stop()
        }
        guard store.delete(id: script.id) else { return }
        deleteCandidate = nil
        if script.id == selectedID {
            selectedID = store.scripts.first?.id
            reloadWords()
            resetTeleprompter()
        }
    }

    private func resetTeleprompter() {
        teleprompterRunning = false
        teleprompterResetID = UUID()
        followCursor = 0
    }

    private func openSpeechPrivacySettings() {
        let anchor = transcription.microphoneAccess == .denied || transcription.microphoneAccess == .restricted
            ? "Privacy_Microphone"
            : "Privacy_SpeechRecognition"
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") else { return }
        NSWorkspace.shared.open(url)
    }

    private func updateAutoCloseSuppression() {
        let active = teleprompterRunning || showingEditor || deleteCandidate != nil || transcription.isRunning
        vm.setAutoCloseSuppression(active, token: interactionToken)
        if !active { vm.shouldRecheckHover.toggle() }
    }
}

/// Where the reader is, for Follow voice.
struct CuelyFollowState: Equatable {
    let words: [CuelyWord]
    let cursor: Int
}

/// AppKit owns the scroll offset so teleprompter motion remains continuous and
/// does not rebuild SwiftUI text at 60 frames per second.
private struct CuelyTeleprompterTextView: NSViewRepresentable {
    let text: String
    let pointSize: CGFloat
    let pointsPerSecond: CGFloat
    let isRunning: Bool
    let resetID: UUID
    /// Set in Follow voice: the script's words and the reader's place.
    let follow: CuelyFollowState?
    let accentColor: NSColor
    let animatesFollow: Bool
    let onReachedEnd: () -> Void
    /// A click in the text, as a character position (Follow voice jumps there).
    let onPickCharacter: (Int) -> Void

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
        textView.delegate = context.coordinator

        context.coordinator.scrollView = scroll
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.pointsPerSecond = max(1, pointsPerSecond)
        coordinator.onReachedEnd = onReachedEnd
        coordinator.onPickCharacter = onPickCharacter
        coordinator.setRunning(isRunning && follow == nil)
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
        let followChanged = coordinator.renderedFollow != follow || coordinator.renderedAccent != accentColor
        guard contentChanged || viewportChanged || followChanged else { return }
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
        if contentChanged || viewportChanged {
            coordinator.resizeDocument(textView, in: scroll)
        }
        if contentChanged || followChanged {
            let cursorMoved = coordinator.renderedFollow?.cursor != follow?.cursor || contentChanged || viewportChanged
            coordinator.renderedFollow = follow
            coordinator.renderedAccent = accentColor
            coordinator.applyHighlight(follow, accent: accentColor, to: textView)
            if let follow, cursorMoved {
                coordinator.scrollToCursor(follow, in: scroll, animated: animatesFollow && !contentChanged)
            }
        } else if viewportChanged, let follow {
            coordinator.scrollToCursor(follow, in: scroll, animated: false)
        }
    }

    static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
        coordinator.stopTimer()
        coordinator.isRunning = false
        coordinator.lastTickUptime = nil
        coordinator.onReachedEnd = {}
        coordinator.onPickCharacter = { _ in }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
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
        var onPickCharacter: (Int) -> Void = { _ in }
        var renderedFollow: CuelyFollowState?
        var renderedAccent: NSColor?

        /// Dims what has been read and lights up the next word.
        func applyHighlight(_ follow: CuelyFollowState?, accent: NSColor, to textView: NSTextView) {
            guard let storage = textView.textStorage, storage.length > 0 else { return }
            let full = NSRange(location: 0, length: storage.length)
            storage.beginEditing()
            storage.addAttribute(.foregroundColor, value: NSColor.white, range: full)
            if let follow, !follow.words.isEmpty {
                let readEnd = follow.cursor < follow.words.count
                    ? follow.words[follow.cursor].range.location
                    : storage.length
                if readEnd > 0 {
                    storage.addAttribute(.foregroundColor, value: NSColor.white.withAlphaComponent(0.32),
                                         range: NSRange(location: 0, length: min(readEnd, storage.length)))
                }
                if follow.cursor < follow.words.count {
                    let next = follow.words[follow.cursor].range
                    if NSMaxRange(next) <= storage.length {
                        storage.addAttribute(.foregroundColor, value: accent, range: next)
                    }
                }
            }
            storage.endEditing()
        }

        /// Keeps the line being read about a third of the way down.
        func scrollToCursor(_ follow: CuelyFollowState, in scrollView: NSScrollView, animated: Bool) {
            guard let textView = scrollView.documentView as? NSTextView,
                  let layoutManager = textView.layoutManager,
                  let container = textView.textContainer,
                  !follow.words.isEmpty else { return }
            let index = min(follow.cursor, follow.words.count - 1)
            let glyphs = layoutManager.glyphRange(forCharacterRange: follow.words[index].range, actualCharacterRange: nil)
            let rect = layoutManager.boundingRect(forGlyphRange: glyphs, in: container)
            let viewport = scrollView.contentSize.height
            let maximum = max(0, textView.bounds.height - viewport)
            let target = min(maximum, max(0, rect.minY + textView.textContainerOrigin.y - viewport * 0.3))
            let clip = scrollView.contentView
            guard abs(clip.bounds.origin.y - target) > 1 else { return }
            if animated {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.45
                    context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    context.allowsImplicitAnimation = true
                    clip.animator().setBoundsOrigin(NSPoint(x: 0, y: target))
                } completionHandler: {
                    scrollView.reflectScrolledClipView(clip)
                }
            } else {
                clip.scroll(to: NSPoint(x: 0, y: target))
                scrollView.reflectScrolledClipView(clip)
            }
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView,
                  textView.window?.currentEvent?.type == .leftMouseUp
                    || textView.window?.currentEvent?.type == .leftMouseDown else { return }
            let selection = textView.selectedRange()
            guard selection.length == 0 else { return }
            onPickCharacter(selection.location)
        }

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
