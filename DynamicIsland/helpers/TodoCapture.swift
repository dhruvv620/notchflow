// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620

import AppKit
import Defaults
import SwiftUI
import UniformTypeIdentifiers

extension Defaults.Keys {
    /// A "today" progress ring in the closed notch when nothing else is showing.
    static let showTodayProgressRing = Key<Bool>("showTodayProgressRing", default: true)
}

extension RemindersManager {
    /// Creates a todo from a line of text, reading a trailing date phrase
    /// ("…tomorrow 7 pm") the same way the Add form does.
    @discardableResult
    func capture(_ text: String) async -> Bool {
        if access != .authorized { await requestAccess() }
        guard access == .authorized else {
            errorMessage = "Allow Reminders access to add todos."
            return false
        }
        if lists.isEmpty { await refresh() }
        guard let listID = preferredCreationListID else {
            errorMessage = "Create a list in Reminders first."
            return false
        }
        guard let line = TodoCapturePolicy.title(fromText: text) else { return false }
        if let parsed = ReminderDateParser.parse(line) {
            return await create(title: parsed.title, listID: listID, dueDate: parsed.dueDate, includesTime: parsed.includesTime)
        }
        return await create(title: line, listID: listID, dueDate: nil, includesTime: false)
    }

    var todayProgress: TodoCapturePolicy.Progress {
        TodoCapturePolicy.todayProgress(
            reminders.map { (isCompleted: $0.isCompleted, dueDate: $0.dueDate, completionDate: $0.completionDate) },
            now: Date()
        )
    }

    /// Reads dropped items (text, links, files) and adds one todo per item.
    func captureDropped(_ providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers {
            if provider.canLoadObject(ofClass: NSURL.self) {
                handled = true
                _ = provider.loadObject(ofClass: NSURL.self) { object, _ in
                    guard let url = object as? URL else { return }
                    Task { @MainActor in _ = await self.capture(TodoCapturePolicy.title(fromURL: url)) }
                }
            } else if provider.canLoadObject(ofClass: NSString.self) {
                handled = true
                _ = provider.loadObject(ofClass: NSString.self) { text, _ in
                    guard let text = text as? String else { return }
                    Task { @MainActor in _ = await self.capture(text) }
                }
            }
        }
        return handled
    }
}

/// A small ring showing today's todo progress.
struct TodayProgressRing: View {
    let progress: TodoCapturePolicy.Progress
    var size: CGFloat = 18
    var lineWidth: CGFloat = 3
    @ObservedObject private var appearance = NotchAppearanceModel.shared

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.15), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: progress.fraction)
                .stroke(progress.done == progress.total && progress.total > 0 ? Color.green : appearance.accentColor,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.smooth(duration: 0.4), value: progress.fraction)
        }
        .frame(width: size, height: size)
        .accessibilityLabel("\(progress.done) of \(progress.total) todos done today")
    }
}

/// The closed-notch activity: ring on the left wing, count on the right.
struct TodayProgressActivity: View {
    @EnvironmentObject private var vm: DynamicIslandViewModel
    @ObservedObject private var reminders = RemindersManager.shared
    let isHovering: Bool

    var body: some View {
        let progress = reminders.todayProgress
        HStack(spacing: 0) {
            TodayProgressRing(progress: progress, size: max(14, vm.effectiveClosedNotchHeight - 16))
                .frame(width: vm.effectiveClosedNotchHeight, alignment: .center)
            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchSize.width + (isHovering ? 8 : 0))
            Text("\(progress.done)/\(progress.total)")
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: vm.effectiveClosedNotchHeight + 8, alignment: .center)
        }
        .frame(height: vm.effectiveClosedNotchHeight + (isHovering ? 8 : 0))
        .help("Todos due today")
    }
}
