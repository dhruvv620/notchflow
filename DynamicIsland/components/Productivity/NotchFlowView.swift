// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620

import Defaults
import SwiftUI

/// The Flow tab: switch workspaces, see where today's time went, the week's
/// report, and open promises.
struct NotchFlowView: View {
    @ObservedObject private var tracker = TimeTracker.shared
    @ObservedObject private var workspaces = WorkspaceManager.shared
    @ObservedObject private var promises = PromiseKeeper.shared
    @ObservedObject private var appearance = NotchAppearanceModel.shared
    @ObservedObject private var coordinator = DynamicIslandViewCoordinator.shared
    @Default(.enableTimeTracking) private var trackingEnabled
    @Default(.enableWorkspaces) private var workspacesEnabled
    @Default(.enablePromiseKeeper) private var promisesEnabled
    @Default(.timeTrackingGoalHours) private var goalHours
    @State private var showWeek = false
    @EnvironmentObject private var vm: DynamicIslandViewModel
    /// The workspace being renamed inline, and the name typed so far.
    @State private var renamingID: UUID?
    @State private var renameText = ""
    @State private var interactionToken = UUID()
    @FocusState private var renameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: NotchTokens.Spacing.s) {
            header
            if workspacesEnabled { workspaceStrip }
            if let deleted = workspaces.recentlyDeleted {
                HStack(spacing: 8) {
                    Image(systemName: "trash").foregroundStyle(.secondary)
                    Text("Deleted \u{201C}\(deleted.workspace.name)\u{201D}").font(NotchTokens.Typography.caption)
                    Spacer(minLength: 0)
                    NotchPillButton(title: "Undo", symbol: "arrow.uturn.backward", prominent: true) { workspaces.undoDelete() }
                }
                .transition(.opacity)
            }
            if let suggestion = workspaces.suggestion, workspacesEnabled { suggestionBanner(suggestion) }
            if workspaces.showDaySummary { daySummary }
            if trackingEnabled {
                if showWeek { WeekReportView(report: tracker.weekReport()) } else { todayView }
            } else {
                NotchEmptyState(symbol: "clock", title: "Time tracking is off",
                                detail: "Turn it on in Settings > Productivity to see where your day goes.")
            }
        }
        .notchTabPadding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            tracker.refreshNow()
            if tracker.showWeekRequested { showWeek = true; tracker.showWeekRequested = false }
        }
        .onChange(of: tracker.showWeekRequested) { _, requested in
            if requested { showWeek = true; tracker.showWeekRequested = false }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: NotchTokens.Spacing.s) {
            Text("Flow").font(NotchTokens.Typography.title)
            if trackingEnabled {
                Picker("", selection: $showWeek) {
                    Text("Today").tag(false)
                    Text("Week").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 130)
                .controlSize(.small)
            }
            Spacer(minLength: 0)
            if promisesEnabled && !promises.open.isEmpty {
                NotchPillButton(title: "\(promises.open.count) promise\(promises.open.count == 1 ? "" : "s")", symbol: "hand.raised") {
                    promises.showListRequested = true
                    withAnimation(.smooth(duration: NotchTabHeightPolicy.animationDuration)) { coordinator.currentView = .reminders }
                }
                .help(promises.open.first.map { "Next: \($0.title) (\(PromisesList.dueText($0)))" } ?? "")
            }
            NotchIconButton(symbol: "gearshape", help: "Productivity settings") {
                SettingsWindowController.shared.showWindow()
            }
        }
    }

    // MARK: Workspaces

    private var workspaceStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(workspaces.workspaces) { workspace in
                    if renamingID == workspace.id {
                        renameField
                    } else {
                        chip(workspace.name, symbol: workspace.symbol, selected: workspaces.activeID == workspace.id) {
                            workspaces.open(workspace)
                        }
                        .help(describe(workspace) + "\nRight-click to rename, update or delete.")
                        .contextMenu {
                            Button("Open") { workspaces.open(workspace) }
                            Button("Rename…") { beginRename(workspace) }
                            Button("Update to current layout") { Task { await workspaces.updateFromCurrent(workspace.id) } }
                            Button("Edit in Settings…") { SettingsWindowController.shared.showWindow() }
                            Divider()
                            Button("Delete \u{201C}\(workspace.name)\u{201D}", role: .destructive) { workspaces.delete(workspace.id) }
                        }
                    }
                }
                chip("Done for the day", symbol: "moon.stars.fill", selected: false) { workspaces.doneForTheDay() }
                    .help("Quits what your workspaces opened today, turns Focus off and shows today's summary")
                chip(workspaces.workspaces.isEmpty ? "Save what's open now" : "Save current", symbol: "plus", selected: false) {
                    Task {
                        let draft = await workspaces.captureCurrentSetup(named: "Setup \(workspaces.workspaces.count + 1)")
                        if !draft.isEmpty { workspaces.save(draft) }
                    }
                }
                .help("Saves the open apps, where each window is and how big it is, and your browser's tabs. Click the setup later to put everything back.")
            }
        }
    }

    /// Typing a new name in place of the chip: Return saves, Escape cancels.
    private var renameField: some View {
        TextField("Name", text: $renameText)
            .textFieldStyle(.plain)
            .font(NotchTokens.Typography.captionEmphasis)
            .frame(width: 130)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Capsule().fill(appearance.accentColor.opacity(0.25)))
            .focused($renameFocused)
            .onSubmit { commitRename() }
            .onExitCommand { endRename() }
            .onChange(of: renameFocused) { _, focused in if !focused && renamingID != nil { commitRename() } }
    }

    private func beginRename(_ workspace: Workspace) {
        renameText = workspace.name
        renamingID = workspace.id
        vm.setAutoCloseSuppression(true, token: interactionToken)
        DispatchQueue.main.async { renameFocused = true }
    }

    private func commitRename() {
        if let id = renamingID { workspaces.rename(id, to: renameText) }
        endRename()
    }

    private func endRename() {
        renamingID = nil
        renameFocused = false
        vm.setAutoCloseSuppression(false, token: interactionToken)
    }

    private func chip(_ title: String, symbol: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 10, weight: .semibold))
                Text(title).font(NotchTokens.Typography.captionEmphasis).lineLimit(1)
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Capsule().fill(selected ? appearance.accentColor.opacity(0.35) : Color.white.opacity(0.08)))
            .foregroundStyle(selected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }

    private func describe(_ workspace: Workspace) -> String {
        var parts: [String] = []
        if !workspace.apps.isEmpty { parts.append(workspace.apps.map(\.name).joined(separator: ", ")) }
        if !workspace.urls.isEmpty { parts.append("\(workspace.urls.count) page\(workspace.urls.count == 1 ? "" : "s")") }
        let windows = workspace.apps.reduce(0) { $0 + ($1.windows?.count ?? 0) }
        if workspace.layout == .restore && windows > 0 { parts.append("\(windows) window\(windows == 1 ? "" : "s") put back in place") }
        if workspace.turnOnFocus { parts.append("Focus on") }
        if workspace.startPomodoro { parts.append("Pomodoro") }
        return parts.joined(separator: " · ")
    }

    private func suggestionBanner(_ suggestion: WorkspaceSuggestion) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles").foregroundStyle(appearance.accentColor)
            Text("You often open \(suggestion.apps.map(\.name).prefix(3).joined(separator: ", ")) together around \(Self.hourLabel(suggestion.hour)). Save them as a workspace?")
                .font(NotchTokens.Typography.caption)
                .lineLimit(2)
            Spacer(minLength: 4)
            NotchPillButton(title: "Save", prominent: true) { workspaces.acceptSuggestion() }
            NotchIconButton(symbol: "xmark", help: "Not now") { workspaces.dismissSuggestion() }
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: NotchTokens.Radius.row).fill(appearance.accentColor.opacity(0.12)))
    }

    private var daySummary: some View {
        let log = tracker.today
        let top = log.topProjects(1).first
        return HStack(spacing: 8) {
            Image(systemName: "moon.stars.fill").foregroundStyle(appearance.accentColor)
            VStack(alignment: .leading, spacing: 1) {
                Text("Done for the day").font(NotchTokens.Typography.headline)
                Text("\(TimeTrackingPolicy.duration(tracker.workToday)) of work, \(TimeTrackingPolicy.duration(log.total)) in total"
                     + (top.map { " · most on \($0.0) (\(TimeTrackingPolicy.duration($0.1)))" } ?? ""))
                    .font(NotchTokens.Typography.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            NotchIconButton(symbol: "xmark", help: "Close") { workspaces.showDaySummary = false }
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: NotchTokens.Radius.row).fill(Color.white.opacity(0.06)))
    }

    // MARK: Today

    private var todayView: some View {
        let log = tracker.today
        return HStack(alignment: .top, spacing: NotchTokens.Spacing.m) {
            VStack(spacing: 4) {
                WorkRing(progress: tracker.goalProgress, lineWidth: 7)
                    .frame(width: 64, height: 64)
                    .overlay {
                        VStack(spacing: 0) {
                            Text(TimeTrackingPolicy.duration(tracker.workToday)).font(.system(size: 12, weight: .bold).monospacedDigit())
                            Text("of \(TimeTrackingPolicy.duration(goalHours * 3600))").font(.system(size: 8)).foregroundStyle(.secondary)
                        }
                    }
                Text("Work today").font(NotchTokens.Typography.caption).foregroundStyle(.secondary)
            }
            .frame(width: 80)

            VStack(alignment: .leading, spacing: 6) {
                CategoryBar(log: log)
                if log.total < 60 {
                    Text("Tracking starts as you work. Apps, sites and projects show up here.")
                        .font(NotchTokens.Typography.caption).foregroundStyle(.secondary)
                } else {
                    HStack(alignment: .top, spacing: NotchTokens.Spacing.m) {
                        list(title: "Apps & sites", rows: log.topApps(4))
                        if !log.projects.isEmpty { list(title: "Projects", rows: log.topProjects(4)) }
                    }
                }
            }
        }
    }

    private func list(title: String, rows: [(String, Double)]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(NotchTokens.Typography.captionEmphasis).foregroundStyle(.secondary)
            ForEach(rows, id: \.0) { row in
                HStack {
                    Text(row.0).font(NotchTokens.Typography.body).lineLimit(1)
                    Spacer(minLength: 4)
                    Text(TimeTrackingPolicy.duration(row.1)).font(NotchTokens.Typography.body.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    static func hourLabel(_ hour: Int) -> String {
        let date = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: Date()) ?? Date()
        return date.formatted(.dateTime.hour())
    }
}

/// The share of the day each category took, as one bar with a legend.
struct CategoryBar: View {
    let log: TimeDayLog

    static func color(_ category: TimeCategory) -> Color {
        switch category {
        case .coding: return Color(red: 0.40, green: 0.66, blue: 1.0)
        case .writing: return Color(red: 0.70, green: 0.48, blue: 0.98)
        case .design: return Color(red: 0.98, green: 0.45, blue: 0.62)
        case .meetings: return Color(red: 0.98, green: 0.62, blue: 0.42)
        case .learning: return Color(red: 0.38, green: 0.86, blue: 0.80)
        case .communication: return Color(red: 0.98, green: 0.82, blue: 0.35)
        case .browsing: return Color.white.opacity(0.45)
        case .entertainment: return Color(red: 0.95, green: 0.35, blue: 0.35)
        case .social: return Color(red: 0.85, green: 0.45, blue: 0.85)
        case .other: return Color.white.opacity(0.25)
        }
    }

    var body: some View {
        let parts = log.topCategories(TimeCategory.allCases.count).filter { $0.1 >= 30 }
        let total = max(1, parts.reduce(0) { $0 + $1.1 })
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geometry in
                HStack(spacing: 1.5) {
                    ForEach(parts, id: \.0) { category, seconds in
                        Self.color(category).frame(width: max(2, geometry.size.width * seconds / total))
                    }
                }
                .clipShape(Capsule())
            }
            .frame(height: 8)
            .background(Capsule().fill(Color.white.opacity(0.06)))
            HStack(spacing: 8) {
                ForEach(parts.prefix(4), id: \.0) { category, seconds in
                    HStack(spacing: 3) {
                        Circle().fill(Self.color(category)).frame(width: 6, height: 6)
                        Text("\(category.title) \(TimeTrackingPolicy.duration(seconds))")
                            .font(NotchTokens.Typography.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
        }
    }
}

/// The work goal ring.
struct WorkRing: View {
    let progress: Double
    var lineWidth: CGFloat = 3
    @ObservedObject private var appearance = NotchAppearanceModel.shared

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.12), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, progress)))
                .stroke(progress >= 1 ? Color.green : appearance.accentColor,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .animation(.smooth(duration: 0.6), value: progress)
    }
}

/// Seven days of work, with the week's highlights and the CSV export.
struct WeekReportView: View {
    let report: TimeWeekReport
    @ObservedObject private var appearance = NotchAppearanceModel.shared

    var body: some View {
        let peak = max(3600, report.days.map(\.work).max() ?? 0)
        HStack(alignment: .bottom, spacing: NotchTokens.Spacing.m) {
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(report.days, id: \.day) { day in
                    VStack(spacing: 3) {
                        Text(day.work >= 60 ? TimeTrackingPolicy.duration(day.work) : "")
                            .font(.system(size: 8).monospacedDigit()).foregroundStyle(.secondary).lineLimit(1)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(day.day == report.bestDay ? appearance.accentColor : Color.white.opacity(day.work > 0 ? 0.45 : 0.12))
                            .frame(width: 18, height: max(3, 60 * day.work / peak))
                        Text(Self.weekday(day.day)).font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("\(TimeTrackingPolicy.duration(report.workThisWeek)) of work this week")
                    .font(NotchTokens.Typography.headline)
                if let change = report.change {
                    Text("\(change >= 0 ? "+" : "")\(Int((change * 100).rounded()))% vs last week")
                        .font(NotchTokens.Typography.caption).foregroundStyle(change >= 0 ? Color.green : Color.orange)
                }
                if let best = report.bestDay {
                    Text("Best day: \(Self.weekday(best, style: .wide))").font(NotchTokens.Typography.caption).foregroundStyle(.secondary)
                }
                if let sink = report.biggestSink {
                    Text("Biggest time sink: \(sink) (\(TimeTrackingPolicy.duration(report.biggestSinkSeconds)))")
                        .font(NotchTokens.Typography.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                NotchPillButton(title: "Export hours (CSV)", symbol: "square.and.arrow.up") { TimeTracker.shared.exportCSV() }
                    .help("Hours per project per day, for invoices")
            }
            Spacer(minLength: 0)
        }
    }

    static func weekday(_ day: String, style: Date.FormatStyle.Symbol.Weekday = .narrow) -> String {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3,
              let date = Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) else { return "" }
        return date.formatted(.dateTime.weekday(style))
    }
}

// MARK: - Closed notch

/// The work ring under the closed notch, when nothing else is showing.
struct WorkGoalActivity: View {
    @ObservedObject private var tracker = TimeTracker.shared
    let isHovering: Bool

    var body: some View {
        ClosedNotchWings(isHovering: isHovering) {
            WorkRing(progress: tracker.goalProgress, lineWidth: 2.5).frame(width: 13, height: 13)
            Text("Work").font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.75))
        } trailing: {
            Text(TimeTrackingPolicy.duration(tracker.workToday))
                .font(.system(size: 10, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white.opacity(0.85))
        }
        .help(TimeTrackingPolicy.summaryLine(tracker.today))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Work today \(TimeTrackingPolicy.duration(tracker.workToday)) of \(TimeTrackingPolicy.duration(tracker.goalSeconds))")
    }
}

/// Friday's weekly report, under the closed notch for a moment.
struct WeeklyReportActivity: View {
    @ObservedObject private var appearance = NotchAppearanceModel.shared
    let report: TimeWeekReport
    let isHovering: Bool

    var body: some View {
        ClosedNotchWings(isHovering: isHovering) {
            Image(systemName: "chart.bar.fill").font(.system(size: 11, weight: .semibold)).foregroundStyle(appearance.accentColor)
            Text("Your week").font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.85))
        } trailing: {
            Text(TimeTrackingPolicy.duration(report.workThisWeek))
                .font(.system(size: 10, weight: .semibold).monospacedDigit())
                .foregroundStyle(appearance.accentColor)
        }
        .help("Click for this week's report")
    }
}
