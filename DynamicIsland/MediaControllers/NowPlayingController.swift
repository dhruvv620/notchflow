/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * Originally from boring.notch project
 * Modified and adapted for Atoll (DynamicIsland)
 * See NOTICE for details.
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

import AppKit
import Combine
import Foundation

final class NowPlayingController: ObservableObject, MediaControllerProtocol {
    @Published private(set) var playbackState = SystemNowPlayingSnapshot.empty()
    @Published private(set) var lastError: String?
    var playbackStatePublisher: AnyPublisher<PlaybackState, Never> { $playbackState.eraseToAnyPublisher() }
    var isWorking: Bool { process?.isRunning == true }
    private var process: Process?
    private var pipeHandler: JSONLinesPipeHandler?
    private var streamTask: Task<Void, Never>?
    private var wakeObserver: NSObjectProtocol?
    private var starting = false
    private var stopped = false
    private var updateSequence = 0

    init() {
        Task { @MainActor [weak self] in await self?.setupNowPlayingObserver() }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification,
                                                                         object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.updatePlaybackInfo() }
        }
    }
    deinit {
        streamTask?.cancel()
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        if let process, process.isRunning { process.terminate() }
        if let pipeHandler { Task { await pipeHandler.close() } }
    }

    func stop() {
        stopped = true
        streamTask?.cancel(); streamTask = nil
        if let process, process.isRunning { process.terminate() }
        process = nil
        if let pipeHandler { Task { await pipeHandler.close() } }
        pipeHandler = nil
    }

    @MainActor func updatePlaybackInfo() async {
        guard !stopped else { return }
        if process?.isRunning != true { await setupNowPlayingObserver() }
        let sequence = updateSequence
        do {
            let data = try await MediaRemoteCommandRunner.run(["get"])
            let payload = try JSONDecoder().decode(NowPlayingPayload?.self, from: data) ?? NowPlayingPayload()
            guard !stopped, sequence == updateSequence else { return }
            apply(NowPlayingUpdate(payload: payload, diff: false))
            lastError = nil
        } catch { lastError = "System media could not be refreshed. Try again." }
    }

    func isActive() -> Bool { !stopped }
    func play() async { await command(["send", "0"]) }
    func pause() async { await command(["send", "1"]) }
    func togglePlay() async { await command(["send", "2"]) }
    func nextTrack() async { await command(["send", "4"]) }
    func previousTrack() async { await command(["send", "5"]) }
    func seek(to time: Double) async {
        guard time.isFinite, time >= 0 else { return }
        await command(["seek", String(Int(min(time, 31_536_000) * 1_000_000))])
    }
    func toggleShuffle() async { await command(["shuffle", playbackState.isShuffled ? "1" : "3"]) }
    func toggleRepeat() async { await command(["repeat", String(playbackState.repeatMode == .off ? 3 : playbackState.repeatMode.rawValue - 1)]) }

    private func command(_ arguments: [String]) async {
        guard !stopped else { return }
        do { _ = try await MediaRemoteCommandRunner.run(arguments); await updatePlaybackInfo() }
        catch { await MainActor.run { lastError = "This media app did not respond. Try Refresh." } }
    }

    @MainActor private func setupNowPlayingObserver() async {
        guard !stopped, !starting, process?.isRunning != true else { return }
        starting = true
        defer { starting = false }
        do {
            let arguments = try MediaRemoteCommandRunner.arguments(["stream", "--debounce=50"])
            let process = Process()
            let handler = JSONLinesPipeHandler()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
            process.arguments = arguments
            process.standardOutput = await handler.getPipe()
            process.standardError = FileHandle.nullDevice
            guard !stopped else { return }
            try process.run()
            self.process = process
            self.pipeHandler = handler
            lastError = nil
            streamTask = Task { [weak self] in
                await handler.readJSONLines(as: NowPlayingUpdate.self) { [weak self] update in
                    await self?.apply(update)
                }
            }
        } catch { lastError = "System media is unavailable. Choose Refresh to reconnect." }
    }

    @MainActor private func apply(_ update: NowPlayingUpdate) {
        guard !stopped else { return }
        updateSequence += 1
        playbackState = SystemNowPlayingSnapshot.applying(update, to: playbackState)
    }
}
