// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import AVFoundation
import Speech
import SwiftUI

struct CuelyScript: Codable, Identifiable {
    var id = UUID()
    var title: String
    var text: String
}

@MainActor
final class CuelyModel: ObservableObject {
    static let shared = CuelyModel()
    @Published var scripts: [CuelyScript] = []
    @Published var selectedID: UUID?
    @Published var transcript = ""
    @Published private(set) var recording = false
    @Published private(set) var requestingPermission = false
    @Published var error: String?
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognition: SFSpeechRecognitionTask?
    private var recognizer: SFSpeechRecognizer?
    private var tapped = false
    private var recordingID: UUID?
    private let storageURL: URL

    private init() {
        storageURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NotchFlow/Cuely/scripts.json")
        if FileManager.default.fileExists(atPath: storageURL.path) {
            do {
                scripts = try JSONDecoder().decode([CuelyScript].self, from: Data(contentsOf: storageURL))
            } catch { self.error = "Could not load scripts: \(error.localizedDescription)" }
        }
        selectedID = scripts.first?.id
    }

    func addScript(text: String = "Write or paste your script here.") {
        let script = CuelyScript(title: "Untitled script", text: text)
        scripts.append(script)
        selectedID = script.id
        save()
    }

    func update(id: UUID, title: String? = nil, text: String? = nil) {
        guard let index = scripts.firstIndex(where: { $0.id == id }) else { return }
        if let title { scripts[index].title = title }
        if let text { scripts[index].text = text }
        save()
    }

    func deleteSelected() {
        scripts.removeAll { $0.id == selectedID }
        selectedID = scripts.first?.id
        save()
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: storageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(scripts).write(to: storageURL, options: .atomic)
        } catch { self.error = "Could not save scripts: \(error.localizedDescription)" }
    }

    func startRecording() async {
        guard !recording, !requestingPermission else { return }
        requestingPermission = true
        let id = UUID()
        recordingID = id
        defer { requestingPermission = false }
        error = nil
        let authorized = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
        }
        guard recordingID == id else { return }
        guard authorized else {
            error = "Allow Speech Recognition for NotchFlow in System Settings > Privacy & Security."
            return
        }
        let microphone = await AVCaptureDevice.requestAccess(for: .audio)
        guard recordingID == id else { return }
        guard microphone else {
            error = "Allow Microphone access for NotchFlow in System Settings > Privacy & Security."
            return
        }
        guard let recognizer = SFSpeechRecognizer(locale: .current), recognizer.isAvailable,
              recognizer.supportsOnDeviceRecognition else {
            error = "On-device transcription is unavailable for this Mac or language. Try another system language or download its speech resources."
            return
        }
        self.recognizer = recognizer
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        self.request = request
        transcript = ""
        recognition = recognizer.recognitionTask(with: request) { [weak self] result, failure in
            let text = result?.bestTranscription.formattedString
            let final = result?.isFinal == true
            let message = failure?.localizedDescription
            Task { @MainActor in
                guard let self, self.recordingID == id else { return }
                if let text { self.transcript = text }
                if final || message != nil {
                    self.stopRecording()
                    if let message { self.error = message }
                }
            }
        }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            stopRecording()
            error = "No microphone input is available."
            return
        }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
        tapped = true
        do {
            engine.prepare()
            try engine.start()
            recording = true
        } catch {
            stopRecording()
            self.error = "Could not start microphone: \(error.localizedDescription)"
        }
    }

    func stopRecording() {
        recordingID = nil
        engine.stop()
        if tapped { engine.inputNode.removeTap(onBus: 0); tapped = false }
        request?.endAudio()
        recognition?.cancel()
        request = nil
        recognition = nil
        recording = false
    }
}
