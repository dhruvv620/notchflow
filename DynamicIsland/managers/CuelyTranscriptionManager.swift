// SPDX-License-Identifier: GPL-3.0-or-later

import AVFoundation
import AppKit
import Combine
import Foundation
import Speech

/// Owns Cuely's microphone and Speech framework lifecycle.
///
/// Permission prompts are never raised from initialization. `start()` is
/// intended to be called only after an explicit user action.
/// Audio buffers stay in memory and are sent only to Apple's speech recognizer
/// according to the recognition mode available for the current locale.
@MainActor
final class CuelyTranscriptionManager: ObservableObject {
    static let shared = CuelyTranscriptionManager()

    enum AccessState: Equatable, Sendable {
        case notDetermined
        case authorized
        case denied
        case restricted
    }

    @Published private(set) var transcript = ""
    @Published private(set) var isStarting = false
    @Published private(set) var isTranscribing = false
    @Published private(set) var speechAccess: AccessState
    @Published private(set) var microphoneAccess: AccessState
    @Published private(set) var isRecognizerAvailable: Bool
    @Published private(set) var usesOnDeviceRecognition = false
    @Published var errorMessage: String?

    private let audioEngine = AVAudioEngine()
    private let recognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var inputTapInstalled = false
    private var sessionPrefix = ""
    private var generation = UUID()
    private var pendingStartID: UUID?
    private var userRequestedRunning = false
    private var lifecycleObservers = Set<AnyCancellable>()

    init(locale: Locale = .current) {
        recognizer = SFSpeechRecognizer(locale: locale)
        speechAccess = Self.mapSpeechAccess(SFSpeechRecognizer.authorizationStatus())
        microphoneAccess = Self.mapMicrophoneAccess(AVCaptureDevice.authorizationStatus(for: .audio))
        isRecognizerAvailable = recognizer?.isAvailable == true
        installLifecycleObservers()
    }

    var isRunning: Bool { userRequestedRunning || isStarting || isTranscribing }

    var authorization: AccessState {
        if speechAccess == .restricted || microphoneAccess == .restricted { return .restricted }
        if speechAccess == .denied || microphoneAccess == .denied { return .denied }
        if speechAccess == .authorized && microphoneAccess == .authorized { return .authorized }
        return .notDetermined
    }

    var statusMessage: String {
        if isStarting || (userRequestedRunning && !isTranscribing) {
            return "Preparing live transcription…"
        }
        if isTranscribing {
            return usesOnDeviceRecognition
                ? "Listening · on-device"
                : "Listening · Apple Speech service"
        }
        switch authorization {
        case .authorized:
            guard isRecognizerAvailable else { return "Speech recognition is temporarily unavailable" }
            return recognizer?.supportsOnDeviceRecognition == true
                ? "Ready · on-device recognition"
                : "Ready · Apple Speech service"
        case .denied:
            return "Microphone or Speech Recognition access is denied"
        case .restricted:
            return "Live transcription is restricted on this Mac"
        case .notDetermined:
            return "Microphone and Speech Recognition access will be requested when you start"
        }
    }

    /// Re-reads TCC state after returning from System Settings without
    /// triggering either permission dialog.
    func refreshAccess() {
        speechAccess = Self.mapSpeechAccess(SFSpeechRecognizer.authorizationStatus())
        microphoneAccess = Self.mapMicrophoneAccess(AVCaptureDevice.authorizationStatus(for: .audio))
        isRecognizerAvailable = recognizer?.isAvailable == true
        // If access was revoked in System Settings while Cuely was running,
        // release the tap immediately instead of waiting for an engine error.
        // `.notDetermined` is expected between the Speech and Microphone
        // prompts. Only tear down an established capture here; otherwise an
        // app-activation notification could cancel the second prompt.
        if authorization != .authorized, isTranscribing {
            stopForInterruption(
                "Live transcription stopped because microphone or Speech Recognition access changed."
            )
        }
    }

    /// Requests Speech and microphone access in sequence. This must only be
    /// reached from an explicit Allow/Start action in the Cuely UI. The start
    /// identifier is revalidated between prompts so leaving Cuely while the
    /// Speech sheet is open does not unexpectedly raise the Microphone sheet.
    private func requestAccess(for startID: UUID) async -> Bool {
        errorMessage = nil

        if SFSpeechRecognizer.authorizationStatus() == .notDetermined
            || AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            // The notch is a nonactivating panel. Bring an explicit Start/Allow
            // action forward before macOS presents either privacy sheet.
            NSApplication.shared.activate()
            await Task.yield()
            guard pendingStartID == startID else { return false }
        }

        let speechStatus: SFSpeechRecognizerAuthorizationStatus
        switch SFSpeechRecognizer.authorizationStatus() {
        case .notDetermined:
            speechStatus = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
            }
        case let current:
            speechStatus = current
        }
        speechAccess = Self.mapSpeechAccess(speechStatus)
        guard speechStatus == .authorized else {
            errorMessage = speechStatus == .restricted
                ? "Speech recognition is restricted on this Mac."
                : "Allow Speech Recognition for NotchFlow in System Settings."
            return false
        }
        guard pendingStartID == startID else { return false }

        let microphoneGranted: Bool
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .notDetermined:
            microphoneGranted = await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { continuation.resume(returning: $0) }
            }
        case .authorized:
            microphoneGranted = true
        default:
            microphoneGranted = false
        }
        microphoneAccess = Self.mapMicrophoneAccess(AVCaptureDevice.authorizationStatus(for: .audio))
        guard pendingStartID == startID else { return false }
        guard microphoneGranted, microphoneAccess == .authorized else {
            errorMessage = microphoneAccess == .restricted
                ? "Microphone access is restricted on this Mac."
                : "Allow Microphone access for NotchFlow in System Settings."
            return false
        }

        isRecognizerAvailable = recognizer?.isAvailable == true
        guard recognizer != nil else {
            errorMessage = "Speech recognition is not available for this language."
            return false
        }
        return true
    }

    /// Begins a live transcript. Pass `append: true` to keep the current text
    /// and continue after a completed recognition segment.
    func start(append: Bool = false) async {
        guard !isStarting, !isTranscribing else { return }
        let startID = UUID()
        pendingStartID = startID
        userRequestedRunning = true
        isStarting = true
        errorMessage = nil
        defer {
            // A permission request cannot be cancelled once macOS is showing
            // it. If this start was stopped and a newer start began while the
            // old request was awaiting its callback, the old invocation must
            // not clear the newer invocation's state.
            if pendingStartID == startID {
                pendingStartID = nil
                isStarting = false
            }
        }

        guard await requestAccess(for: startID) else {
            if pendingStartID == startID { userRequestedRunning = false }
            return
        }
        guard pendingStartID == startID else { return }
        guard let recognizer else {
            userRequestedRunning = false
            return
        }
        guard recognizer.isAvailable else {
            isRecognizerAvailable = false
            errorMessage = "Speech recognition is temporarily unavailable. Try again shortly."
            userRequestedRunning = false
            return
        }

        stopCapture(cancelTask: true)
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        request.taskHint = .dictation
        // Prefer a local recognizer whenever this locale has one. When it does
        // not, the OS-granted Speech Recognition service is the fallback; the
        // status copy above makes that distinction visible while recording.
        usesOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        request.requiresOnDeviceRecognition = usesOnDeviceRecognition

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            errorMessage = "No usable microphone input is available. Check the selected input device."
            userRequestedRunning = false
            usesOnDeviceRecognition = false
            return
        }

        if !append { transcript = "" }
        sessionPrefix = append ? transcript.trimmingCharacters(in: .whitespacesAndNewlines) : ""
        let session = UUID()
        generation = session
        recognitionRequest = request

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self, self.generation == session else { return }
                if let result {
                    self.transcript = Self.join(self.sessionPrefix, result.bestTranscription.formattedString)
                    if result.isFinal {
                        self.finishNaturally(continueAfterFinalResult: true)
                        return
                    }
                }
                if let error {
                    self.errorMessage = "Live transcription stopped: \(error.localizedDescription)"
                    self.userRequestedRunning = false
                    self.finishNaturally(continueAfterFinalResult: false)
                }
            }
        }

        input.installTap(onBus: 0, bufferSize: 1_024, format: format) { [weak request] buffer, _ in
            request?.append(buffer)
        }
        inputTapInstalled = true

        do {
            audioEngine.prepare()
            try audioEngine.start()
            isRecognizerAvailable = true
            isTranscribing = true
        } catch {
            errorMessage = "The microphone could not start: \(error.localizedDescription)"
            userRequestedRunning = false
            stopCapture(cancelTask: true)
        }
    }

    /// Stops recording while keeping the latest partial transcript visible.
    func stop() {
        guard isStarting || isTranscribing || recognitionTask != nil || userRequestedRunning else { return }
        pendingStartID = nil
        userRequestedRunning = false
        isStarting = false
        generation = UUID()
        stopCapture(cancelTask: true)
    }

    func requestAndStart(append: Bool = false) async {
        await start(append: append)
    }

    func clear() {
        stop()
        sessionPrefix = ""
        transcript = ""
        errorMessage = nil
    }

    private func installLifecycleObservers() {
        NotificationCenter.default.publisher(
            for: .AVAudioEngineConfigurationChange,
            object: audioEngine
        )
        .sink { [weak self] _ in
            Task { @MainActor [weak self] in
                // Route changes can briefly stop and restart the engine. Give
                // AVFoundation one moment to settle before declaring failure.
                try? await Task.sleep(for: .milliseconds(150))
                guard let self, self.isTranscribing, !self.audioEngine.isRunning else { return }
                self.stopForInterruption(
                    "Audio input changed. Check your microphone, then start listening again."
                )
            }
        }
        .store(in: &lifecycleObservers)

        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.willSleepNotification)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.isRunning else { return }
                    self.stopForInterruption(
                        "Live transcription stopped while your Mac slept. Start listening to continue."
                    )
                }
            }
            .store(in: &lifecycleObservers)

        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    // The main-queue will-sleep callback may not run before
                    // suspension. Never carry a pre-sleep capture across wake.
                    if self.isRunning {
                        self.stopForInterruption(
                            "Live transcription stopped while your Mac slept. Start listening to continue."
                        )
                    }
                    self.refreshAccess()
                }
            }
            .store(in: &lifecycleObservers)
    }

    private func stopForInterruption(_ message: String) {
        stop()
        errorMessage = message
    }

    private func finishNaturally(continueAfterFinalResult: Bool) {
        generation = UUID()
        stopCapture(cancelTask: false)
        guard continueAfterFinalResult, userRequestedRunning else { return }
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, self.userRequestedRunning else { return }
            await self.start(append: true)
        }
    }

    private func stopCapture(cancelTask: Bool) {
        if audioEngine.isRunning { audioEngine.stop() }
        if inputTapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            inputTapInstalled = false
        }
        recognitionRequest?.endAudio()
        if cancelTask { recognitionTask?.cancel() }
        recognitionTask = nil
        recognitionRequest = nil
        isTranscribing = false
        if !userRequestedRunning { usesOnDeviceRecognition = false }
    }

    private static func join(_ prefix: String, _ segment: String) -> String {
        let prefix = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        let segment = segment.trimmingCharacters(in: .whitespacesAndNewlines)
        if prefix.isEmpty { return segment }
        if segment.isEmpty { return prefix }
        return prefix + "\n" + segment
    }

    private static func mapSpeechAccess(_ status: SFSpeechRecognizerAuthorizationStatus) -> AccessState {
        switch status {
        case .authorized: return .authorized
        case .denied: return .denied
        case .restricted: return .restricted
        case .notDetermined: return .notDetermined
        @unknown default: return .denied
        }
    }

    private static func mapMicrophoneAccess(_ status: AVAuthorizationStatus) -> AccessState {
        switch status {
        case .authorized: return .authorized
        case .denied: return .denied
        case .restricted: return .restricted
        case .notDetermined: return .notDetermined
        @unknown default: return .denied
        }
    }
}
