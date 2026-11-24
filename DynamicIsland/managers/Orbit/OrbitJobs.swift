// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620

import AppKit
import Defaults
import Foundation
import os

extension Defaults.Keys {
    /// Hand-offs to Claude Code and Codex run out of sight, in their own copy
    /// of the project, and come back for review (instead of a terminal window).
    static let orbitBackgroundHandoffs = Key<Bool>("orbitBackgroundHandoffs", default: true)
}

/// Background hand-offs. Each job gets its own git worktree (a separate copy
/// of the project on a new branch), so the agent never touches the files
/// you're working on. When it's done, you review the changes and apply,
/// commit or throw them away.
///
/// Runs only while Orbit and its Team switch are on; turning either off stops
/// running jobs and drops the list from memory (it's saved to disk).
@MainActor
final class OrbitJobs: ObservableObject {
    static let shared = OrbitJobs()

    @Published private(set) var jobs: [OrbitJob] = []
    @Published private(set) var isActive = false

    private let log = os.Logger(subsystem: "com.dhruvv620.NotchFlow", category: "OrbitJobs")
    private var processes: [UUID: Process] = [:]
    private var saveTask: Task<Void, Never>?

    private init() {}

    // MARK: Files

    nonisolated static var folder: URL { Orbit.storeURL.deletingLastPathComponent() }
    nonisolated static var storeURL: URL { folder.appendingPathComponent("jobs.json") }
    nonisolated static var worktrees: URL { folder.appendingPathComponent("Worktrees", isDirectory: true) }
    nonisolated static func patchURL(_ id: UUID) -> URL { folder.appendingPathComponent("Patches/\(id.uuidString).patch") }

    func setActive(_ active: Bool) {
        guard active != isActive else { return }
        isActive = active
        if active {
            var loaded = (try? Data(contentsOf: Self.storeURL)).flatMap { try? JSONDecoder().decode([OrbitJob].self, from: $0) } ?? []
            // Anything "running" from before didn't survive the quit.
            for index in loaded.indices where loaded[index].state == .running {
                loaded[index].state = .failed
                loaded[index].error = "Stopped when NotchFlow quit."
                loaded[index].finished = Date()
            }
            jobs = loaded
        } else {
            for (id, process) in processes {
                process.terminate()
                update(id) { $0.state = .failed; $0.error = "Stopped (Orbit's Team was turned off)."; $0.finished = Date() }
            }
            processes = [:]
            save(now: true)
            jobs = []
        }
    }

    private func update(_ id: UUID, _ change: (inout OrbitJob) -> Void) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        change(&jobs[index])
        save()
    }

    private func save(now: Bool = false) {
        let snapshot = jobs
        saveTask?.cancel()
        saveTask = Task {
            if !now { try? await Task.sleep(for: .seconds(2)) }
            guard !Task.isCancelled else { return }
            await Task.detached(priority: .utility) {
                guard let data = try? JSONEncoder().encode(snapshot) else { return }
                try? FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
                try? data.write(to: Self.storeURL, options: .atomic)
            }.value
        }
    }

    // MARK: Shell

    /// Runs git (or any tool) and returns its exit status and output.
    nonisolated private static func run(_ arguments: [String], in directory: String?) async -> (status: Int32, output: String) {
        await Task.detached(priority: .userInitiated) { () -> (Int32, String) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = arguments
            if let directory { process.currentDirectoryURL = URL(fileURLWithPath: directory) }
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            process.standardInput = FileHandle.nullDevice
            do { try process.run() } catch { return (-1, error.localizedDescription) }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return (process.terminationStatus, String(decoding: data, as: UTF8.self))
        }.value
    }

    private static func git(_ arguments: [String], in directory: String) async -> (status: Int32, output: String) {
        await run(["git"] + arguments, in: directory)
    }

    // MARK: Starting

    /// Starts an agent on a task in the background. Returns false if this
    /// agent can't run in the background (the caller opens a terminal instead).
    @discardableResult
    func start(agent: AgentHookPolicy.LaunchAgent, title: String, prompt: String, folder: String,
               project: String?, loopID: String?, issueID: String?, url: String?) -> Bool {
        guard isActive, OrbitJobsPolicy.backgroundAgents.contains(agent.rawValue) else { return false }
        let job = OrbitJob(agent: agent.rawValue, title: title, prompt: prompt, loopID: loopID, issueID: issueID, url: url,
                           project: project, folder: folder, workFolder: folder, started: Date())
        jobs.insert(job, at: 0)
        save()
        Task { await prepareAndRun(job.id) }
        return true
    }

    private func prepareAndRun(_ id: UUID) async {
        guard let job = jobs.first(where: { $0.id == id }) else { return }
        // A git project gets its own worktree on a new branch.
        let top = await Self.git(["rev-parse", "--show-toplevel"], in: job.folder)
        let head = await Self.git(["rev-parse", "HEAD"], in: job.folder)
        if top.status == 0, head.status == 0 {
            let root = top.output.trimmingCharacters(in: .whitespacesAndNewlines)
            let base = head.output.trimmingCharacters(in: .whitespacesAndNewlines)
            let branch = OrbitJobsPolicy.branchName(title: job.title, id: job.id)
            let path = OrbitJobsPolicy.worktreePath(base: Self.worktrees.path, project: (root as NSString).lastPathComponent, id: job.id)
            try? FileManager.default.createDirectory(at: Self.worktrees, withIntermediateDirectories: true)
            let added = await Self.git(["worktree", "add", "-b", branch, path, base], in: root)
            if added.status == 0 {
                update(id) {
                    $0.repoRoot = root
                    $0.baseCommit = base
                    $0.branch = branch
                    $0.workFolder = OrbitJobsPolicy.workFolder(for: job.folder, repoRoot: root, worktree: path)
                }
            } else {
                log.error("Worktree failed: \(added.output, privacy: .public)")
            }
        }
        launch(id, command: OrbitJobsPolicy.command(agent: job.agent, prompt: job.prompt))
    }

    private func launch(_ id: UUID, command: String) {
        guard let job = jobs.first(where: { $0.id == id }) else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = AgentTranscriptPolicy.shellInvocation(command)
        if FileManager.default.fileExists(atPath: job.workFolder) {
            process.currentDirectoryURL = URL(fileURLWithPath: job.workFolder)
        }
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        process.standardInput = FileHandle.nullDevice
        let buffer = LineBuffer()
        output.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            for line in buffer.append(data) {
                let session = AgentTranscriptPolicy.sessionID(fromStreamLine: line)
                let answer = OrbitJobsPolicy.finalAnswer(fromStreamLine: line)
                let failure = AgentTranscriptPolicy.failure(fromStreamLine: line)
                let notFound = line.contains("command not found")
                guard session != nil || answer != nil || failure != nil || notFound else { continue }
                Task { @MainActor in
                    OrbitJobs.shared.update(id) { job in
                        if let session { job.sessionID = session }
                        if let answer { job.summary = answer }
                        if let failure { job.error = failure }
                        if notFound { job.error = "The agent's command wasn't found. Check that it runs in Terminal." }
                    }
                }
            }
        }
        process.terminationHandler = { finished in
            output.fileHandleForReading.readabilityHandler = nil
            let status = finished.terminationStatus
            Task { @MainActor in await OrbitJobs.shared.finish(id, status: status) }
        }
        do {
            try process.run()
            processes[id] = process
            update(id) { $0.state = .running; $0.error = nil }
        } catch {
            update(id) { $0.state = .failed; $0.error = "Couldn't start the agent: \(error.localizedDescription)"; $0.finished = Date() }
        }
    }

    private func finish(_ id: UUID, status: Int32) async {
        processes[id] = nil
        guard var job = jobs.first(where: { $0.id == id }), job.state == .running else { return }
        if let base = job.baseCommit, let worktree = worktreeRoot(of: job) {
            _ = await Self.git(["add", "-A"], in: worktree)
            let numstat = await Self.git(["diff", "--cached", "--no-renames", "--numstat", base], in: worktree)
            job.changes = OrbitJobsPolicy.diffStat(fromNumstat: numstat.output)
            let patch = await Self.git(["diff", "--cached", "--no-renames", "--binary", base], in: worktree)
            let url = Self.patchURL(id)
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? patch.output.write(to: url, atomically: true, encoding: .utf8)
        }
        let stopped = status == 15 || status == 9
        if status == 0 || !job.changes.isEmpty {
            job.state = .review
        } else {
            job.state = .failed
            if job.error == nil { job.error = stopped ? "Stopped." : "The agent stopped with an error (exit \(status))." }
        }
        job.finished = Date()
        let finished = job
        update(id) { $0 = finished }
        guard !stopped else { return }
        let agentName = AgentHookPolicy.LaunchAgent(rawValue: job.agent)?.title ?? "The agent"
        if job.state == .review {
            NotificationHub.shared.post(id: "orbit-job-\(id.uuidString)", appName: "Orbit",
                                        title: "Ready for review: \(job.title)",
                                        body: [job.changes.summary, OrbitPolicy.clip(job.summary, to: 120)].filter { !$0.isEmpty }.joined(separator: "\n"))
        }
        Orbit.shared.jobFinished(finished, agentName: agentName)
    }

    /// The worktree's top folder (its path under Worktrees).
    private func worktreeRoot(of job: OrbitJob) -> String? {
        guard job.branch != nil else { return nil }
        let base = Self.worktrees.path + "/"
        guard job.workFolder.hasPrefix(base) else { return nil }
        let name = job.workFolder.dropFirst(base.count).split(separator: "/").first.map(String.init) ?? ""
        return name.isEmpty ? nil : base + name
    }

    // MARK: Reviewing

    func stop(_ job: OrbitJob) {
        processes[job.id]?.terminate()
    }

    /// Opens the changes (a .patch file) or, without git, the folder.
    func seeChanges(_ job: OrbitJob) {
        let patch = Self.patchURL(job.id)
        if job.branch != nil, FileManager.default.fileExists(atPath: patch.path) {
            NSWorkspace.shared.open(patch)
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: job.workFolder)])
        }
    }

    func openWorkFolder(_ job: OrbitJob) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: job.workFolder)])
    }

    /// Sends more instructions; the agent continues where it left off.
    func keepGoing(_ job: OrbitJob, message: String) {
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isActive, !text.isEmpty, let session = job.sessionID, job.state != .running else { return }
        update(job.id) { $0.state = .running; $0.finished = nil; $0.error = nil }
        launch(job.id, command: OrbitJobsPolicy.command(agent: job.agent, prompt: text, resume: session))
    }

    /// Puts the changes into your project folder (uncommitted), or commits
    /// them too, then removes the job's worktree.
    func apply(_ job: OrbitJob, commit: Bool) async {
        guard job.state == .review else { return }
        guard let root = job.repoRoot, job.branch != nil else {
            // Worked in place: the changes are already there.
            update(job.id) { $0.state = .applied }
            Orbit.shared.jobClosed(job, outcome: "Kept")
            return
        }
        let patch = Self.patchURL(job.id)
        if !job.changes.isEmpty {
            let applied = await Self.git(["apply", "--3way", "--whitespace=nowarn", patch.path], in: root)
            guard applied.status == 0 else {
                update(job.id) { $0.error = "Couldn't apply cleanly: " + OrbitPolicy.clip(applied.output, to: 160) }
                return
            }
            if commit {
                let agentName = AgentHookPolicy.LaunchAgent(rawValue: job.agent)?.title ?? "an agent"
                let paths = job.changes.files.map(\.path)
                _ = await Self.git(["add", "--"] + paths, in: root)
                let committed = await Self.git(["commit", "-m", OrbitJobsPolicy.commitMessage(title: job.title, agentName: agentName), "--"] + paths, in: root)
                if committed.status != 0 {
                    update(job.id) { $0.error = "Applied, but the commit failed: " + OrbitPolicy.clip(committed.output, to: 160) }
                }
            }
        }
        await removeWorktree(job)
        update(job.id) { $0.state = commit ? .committed : .applied; $0.finished = Date() }
        Orbit.shared.jobClosed(job, outcome: commit ? "Committed" : "Applied")
    }

    /// Stops the job if it runs and deletes its copy of the project.
    func discard(_ job: OrbitJob) async {
        processes[job.id]?.terminate()
        processes[job.id] = nil
        await removeWorktree(job)
        try? FileManager.default.removeItem(at: Self.patchURL(job.id))
        update(job.id) { $0.state = .discarded; $0.finished = Date() }
        Orbit.shared.jobClosed(job, outcome: "Thrown away")
    }

    private func removeWorktree(_ job: OrbitJob) async {
        guard let root = job.repoRoot, let branch = job.branch, let worktree = worktreeRoot(of: job) else { return }
        _ = await Self.git(["worktree", "remove", "--force", worktree], in: root)
        _ = await Self.git(["branch", "-D", branch], in: root)
    }

    /// Hides finished jobs from the list.
    func clearFinished() {
        jobs.removeAll { !$0.state.isOpen }
        save()
    }

    var visibleJobs: [OrbitJob] { OrbitJobsPolicy.visible(jobs, now: Date()) }
    var reviewCount: Int { jobs.filter { $0.state == .review }.count }
}
