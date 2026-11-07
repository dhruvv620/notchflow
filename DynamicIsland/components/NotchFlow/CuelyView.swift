// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI
import AppKit

struct CuelyView: View {
    @ObservedObject private var model = CuelyModel.shared
    @EnvironmentObject private var vm: DynamicIslandViewModel
    @State private var live = false
    @State private var editing = false
    @State private var playing = false
    @State private var restart = UUID()
    @State private var token = UUID()
    @AppStorage("cuelySpeed") private var speed = 28.0
    @AppStorage("cuelyFontSize") private var fontSize = 24.0
    @State private var confirmingDelete = false

    private var selected: CuelyScript? { model.scripts.first { $0.id == model.selectedID } }

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Picker("Mode", selection: $live) {
                    Text("Scripts").tag(false)
                    Text("Live transcript").tag(true)
                }.pickerStyle(.segmented).frame(maxWidth: 260)
                Spacer()
                Text("Visible when sharing this screen").font(.caption).foregroundStyle(.secondary)
            }
            if live { transcriptPanel } else { scriptPanel }
            if let error = model.error {
                Text(error).font(.caption).foregroundStyle(.orange).textSelection(.enabled)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { vm.setAutoCloseSuppression(true, token: token) }
        .onDisappear {
            playing = false
            model.stopRecording()
            vm.setAutoCloseSuppression(false, token: token)
        }
        .onChange(of: live) { _, _ in playing = false; model.stopRecording() }
        .onChange(of: model.selectedID) { _, _ in playing = false; restart = UUID() }
        .confirmationDialog("Delete this script?", isPresented: $confirmingDelete) {
            Button("Delete script", role: .destructive) { model.deleteSelected() }
        }
    }

    private var transcriptPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollViewReader { proxy in
                ScrollView {
                    Text(model.transcript.isEmpty ? "Press Record to transcribe your microphone on this Mac." : model.transcript)
                        .font(.system(size: fontSize)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                    Color.clear.frame(height: 1).id("bottom")
                }
                .onChange(of: model.transcript) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
            HStack {
                Button(model.recording ? "Stop recording" : "Record", systemImage: model.recording ? "stop.circle.fill" : "mic.fill") {
                    if model.recording { model.stopRecording() }
                    else { Task { await model.startRecording() } }
                }
                .tint(model.recording ? .red : .accentColor)
                .disabled(model.requestingPermission)
                if model.recording { Text("Microphone on").font(.caption).foregroundStyle(.red) }
                Spacer()
                Button("Save as script") { model.addScript(text: model.transcript); live = false }
                    .disabled(model.transcript.isEmpty || model.recording)
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(model.transcript, forType: .string)
                }.disabled(model.transcript.isEmpty)
            }
            Text("On-device speech recognition. Microphone only; stops when you leave Cuely. Long recordings may end at the system recognition limit.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var scriptPanel: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Scripts").font(.headline)
                    Spacer()
                    Button { model.addScript() } label: { Image(systemName: "plus") }.help("New script")
                }
                List(selection: $model.selectedID) {
                    ForEach(model.scripts) { script in Text(script.title).lineLimit(1).tag(script.id) }
                }.listStyle(.plain)
                Button("Delete", role: .destructive) { confirmingDelete = true }.disabled(selected == nil)
            }.frame(width: 140)
            VStack(spacing: 10) {
                if let script = selected {
                    HStack {
                        TextField("Script title", text: Binding(get: { selected?.title ?? "" }, set: { model.update(id: script.id, title: $0) }))
                        Toggle("Edit", isOn: $editing).toggleStyle(.button)
                            .onChange(of: editing) { _, _ in playing = false }
                    }
                    if editing {
                        TextEditor(text: Binding(get: { selected?.text ?? "" }, set: { model.update(id: script.id, text: $0) }))
                            .font(.system(size: fontSize))
                    } else {
                        ScrollingScriptView(text: script.text, fontSize: fontSize, speed: speed, playing: playing, restart: restart)
                    }
                    HStack {
                        Button(playing ? "Pause" : "Start", systemImage: playing ? "pause.fill" : "play.fill") { playing.toggle() }
                            .disabled(editing || script.text.isEmpty)
                        Button("Rewind", systemImage: "backward.end") { playing = false; restart = UUID() }
                        Picker("Speed", selection: $speed) {
                            Text("Slow").tag(15.0); Text("Normal").tag(28.0)
                            Text("Fast").tag(45.0); Text("Sprint").tag(70.0)
                        }.labelsHidden()
                        Slider(value: $fontSize, in: 18...40).frame(width: 70).help("Text size")
                    }
                } else {
                    ContentUnavailableView("Your scripts", systemImage: "text.alignleft", description: Text("Add a script to read it from the notch."))
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// Native scrolling keeps the teleprompter smooth and lets the user scroll manually.
private struct ScrollingScriptView: NSViewRepresentable {
    let text: String
    let fontSize: Double
    let speed: Double
    let playing: Bool
    let restart: UUID

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        let view = scroll.documentView as! NSTextView
        view.isEditable = false
        view.isSelectable = true
        view.drawsBackground = false
        view.textColor = .white
        view.textContainerInset = NSSize(width: 14, height: 20)
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]
        view.textContainer?.widthTracksTextView = true
        scroll.documentView = view
        context.coordinator.scroll = scroll
        context.coordinator.timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak coordinator = context.coordinator] _ in
            MainActor.assumeIsolated { coordinator?.tick() }
        }
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = scroll.documentView as? NSTextView else { return }
        if view.string != text || view.font?.pointSize != fontSize {
            view.string = text
            view.font = .systemFont(ofSize: fontSize, weight: .medium)
            let style = NSMutableParagraphStyle()
            style.lineSpacing = 12
            view.textStorage?.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: (text as NSString).length))
            view.setFrameSize(NSSize(width: scroll.contentSize.width, height: scroll.contentSize.height))
            view.sizeToFit()
        }
        if context.coordinator.restart != restart {
            context.coordinator.restart = restart
            scroll.contentView.scroll(to: .zero)
            scroll.reflectScrolledClipView(scroll.contentView)
        }
        context.coordinator.speed = speed
        context.coordinator.playing = playing
    }
    static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) { coordinator.timer?.invalidate() }
    @MainActor final class Coordinator {
        weak var scroll: NSScrollView?
        var timer: Timer?
        var speed = 28.0
        var playing = false
        var restart: UUID?
        func tick() {
            guard playing, let scroll, let document = scroll.documentView else { return }
            let maxY = max(0, document.bounds.height - scroll.contentSize.height)
            let y = min(maxY, scroll.contentView.bounds.origin.y + speed / 30)
            scroll.contentView.scroll(to: NSPoint(x: 0, y: y))
            scroll.reflectScrolledClipView(scroll.contentView)
        }
    }
}
