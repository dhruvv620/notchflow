// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620

import AppKit
import Combine
import Defaults
import SwiftUI

extension Defaults.Keys {
    /// Spinner in the notch while a GitHub Actions run or an `nf` terminal job runs, then green or red.
    static let enableBuildWatcher = Key<Bool>("enableBuildWatcher", default: false)
    static let buildWatcherRepositories = Key<String>("buildWatcherRepositories", default: "")
    static let buildWatcherTerminalJobs = Key<Bool>("buildWatcherTerminalJobs", default: true)
}

/// Watches GitHub Actions runs on the user's repositories and terminal
/// commands started with the `nf` shell function.
@MainActor
final class BuildWatchManager: ObservableObject {
    static let shared = BuildWatchManager()

    @Published private(set) var runs: [WatchedRun] = []
    /// A run that just finished, shown for a few seconds.
    @Published private(set) var announcement: WatchedRun?
    @Published private(set) var lastError: String?

    var running: [WatchedRun] { runs.filter { $0.state == .running } }

    static var jobsFolder: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/NotchFlow/Jobs", isDirectory: true)
    }

    private var githubRuns: [WatchedRun] = []
    private var jobRuns: [WatchedRun] = []
    private var announcedJobIDs = Set<String>()
    private let startedAt = Date()
    private var jobTimer: AnyCancellable?
    private var githubTask: Task<Void, Never>?
    private var hideWork: DispatchWorkItem?
    private var started = false

    private init() {}

    func start() {
        guard !started else { return }
        started = true
        jobTimer = Timer.publish(every: 2, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.pollJobs() }
        githubTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.pollGitHub()
                let busy = self.githubRuns.contains { $0.state == .running }
                try? await Task.sleep(nanoseconds: UInt64((busy ? 15 : 45) * 1_000_000_000))
            }
        }
    }

    func refreshNow() {
        Task { await pollGitHub() }
        pollJobs()
    }

    // MARK: GitHub

    private func pollGitHub() async {
        let repositories = BuildWatchPolicy.repositories(from: Defaults[.buildWatcherRepositories])
        guard Defaults[.enableBuildWatcher], !repositories.isEmpty, let token = SecretStore.read(.githubToken) else {
            if !githubRuns.isEmpty { githubRuns = []; publish(previous: runs) }
            return
        }
        var collected: [WatchedRun] = []
        var failure: String?
        for repository in repositories {
            guard let url = URL(string: "https://api.github.com/repos/\(repository)/actions/runs?per_page=5") else { continue }
            var request = URLRequest(url: url, timeoutInterval: 20)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                if status == 200 {
                    collected += BuildWatchPolicy.githubRuns(from: data, repository: repository)
                } else {
                    failure = "\(repository): GitHub answered \(status)" + (status == 404 ? " (check the name and the token's access)" : "")
                }
            } catch {
                failure = "\(repository): \(error.localizedDescription)"
            }
        }
        lastError = failure
        // Runs untouched for hours are stuck in a queue, not building.
        let fresh = collected.filter { $0.state != .running || Date().timeIntervalSince($0.updatedAt) < 3 * 3600 }
        let previous = runs
        githubRuns = fresh
        publish(previous: previous)
    }

    // MARK: Terminal jobs

    private func pollJobs() {
        guard Defaults[.enableBuildWatcher], Defaults[.buildWatcherTerminalJobs] else {
            if !jobRuns.isEmpty { jobRuns = []; publish(previous: runs) }
            return
        }
        let folder = Self.jobsFolder
        guard let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey]) else {
            if !jobRuns.isEmpty { jobRuns = []; publish(previous: runs) }
            return
        }
        var jobs: [WatchedRun] = []
        for file in files where file.pathExtension == "json" {
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            if Date().timeIntervalSince(modified) > 86_400 {
                try? FileManager.default.removeItem(at: file)
                continue
            }
            guard let data = try? Data(contentsOf: file),
                  let job = BuildWatchPolicy.terminalJob(from: data, id: file.deletingPathExtension().lastPathComponent) else { continue }
            jobs.append(job)
        }
        let previous = runs
        jobRuns = jobs.sorted { $0.updatedAt > $1.updatedAt }
        // A quick command can start and finish between two checks, so terminal
        // jobs are announced when they end after launch, not only when seen running.
        for job in jobRuns where job.state != .running && job.updatedAt >= startedAt && !announcedJobIDs.contains(job.id) {
            announcedJobIDs.insert(job.id)
            announce(job)
        }
        publish(previous: previous, announceJobs: false)
    }

    // MARK: Publishing

    private func publish(previous: [WatchedRun], announceJobs: Bool = true) {
        let combined = (jobRuns + githubRuns).sorted { $0.updatedAt > $1.updatedAt }
        for run in BuildWatchPolicy.newlyFinished(previous: previous, current: combined) {
            if run.id.hasPrefix("job-") {
                guard announceJobs, !announcedJobIDs.contains(run.id) else { continue }
                announcedJobIDs.insert(run.id)
            }
            announce(run)
        }
        if combined != runs { runs = combined }
    }

    private func announce(_ run: WatchedRun) {
        if FocusQuiet.shared.shouldHold(.build) { return }
        withAnimation(.smooth(duration: 0.25)) { announcement = run }
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            withAnimation(.smooth(duration: 0.25)) { self?.announcement = nil }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: work)
    }

    func dismissAnnouncement() {
        hideWork?.cancel()
        withAnimation(.smooth(duration: 0.25)) { announcement = nil }
    }

    func open(_ run: WatchedRun) {
        if let url = run.url { NSWorkspace.shared.open(url) }
        dismissAnnouncement()
    }

    /// Checks the token and the repository list, for the Settings button.
    static func testConnection() async -> String {
        guard let token = SecretStore.read(.githubToken) else { return "Add a GitHub token first." }
        let repositories = BuildWatchPolicy.repositories(from: Defaults[.buildWatcherRepositories])
        guard let repository = repositories.first else { return "Add a repository as owner/name." }
        guard let url = URL(string: "https://api.github.com/repos/\(repository)/actions/runs?per_page=1") else { return "Bad repository name." }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            switch (response as? HTTPURLResponse)?.statusCode ?? 0 {
            case 200: return "Connected to \(repository)."
            case 401: return "GitHub rejected the token."
            case 403: return "The token cannot read Actions on \(repository). Give it Actions: Read."
            case 404: return "\(repository) was not found, or the token cannot see it."
            case let code: return "GitHub answered \(code)."
            }
        } catch {
            return error.localizedDescription
        }
    }
}
