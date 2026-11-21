// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620

import AppKit
import Defaults
import EventKit
import PDFKit
import SwiftUI
import WebKit

/// Where a panel's grid cells are on screen.
enum GlanceLayout {
    static func rect(for frame: GlanceRect, in area: CGRect, gap: CGFloat) -> CGRect {
        let cellWidth = area.width / CGFloat(GlancePolicy.columns)
        let cellHeight = area.height / CGFloat(GlancePolicy.rows)
        return CGRect(x: area.minX + CGFloat(frame.x) * cellWidth + gap / 2,
                      y: area.minY + CGFloat(frame.y) * cellHeight + gap / 2,
                      width: CGFloat(frame.width) * cellWidth - gap,
                      height: CGFloat(frame.height) * cellHeight - gap)
    }
}

/// The board itself: your panels, as glass cards, over the screen (clear,
/// dimmed or blurred behind them).
struct GlanceBoardView: View {
    /// The display this board is on.
    let displayKey: String
    @ObservedObject private var glance = GlanceManager.shared
    @Default(.glanceBackdrop) private var backdrop
    @Default(.glanceMode) private var mode

    var body: some View {
        if let board = glance.board(onDisplay: displayKey) {
            content(board)
        } else {
            Color.clear
        }
    }

    private func content(_ board: GlanceBoard) -> some View {
        GeometryReader { geometry in
            let area = CGRect(x: 28, y: 52, width: max(200, geometry.size.width - 56), height: max(200, geometry.size.height - 80))
            ZStack(alignment: .topLeading) {
                backdropView
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { glance.hide() }

                let shown = board.panels.filter(\.isShown)
                if shown.isEmpty {
                    Text("Nothing on this board yet. Add panels in Settings › Glance.")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .allowsHitTesting(false)
                }
                ForEach(shown) { panel in
                    let rect = GlanceLayout.rect(for: panel.frame, in: area, gap: 18)
                    GlancePanelCard(panel: panel)
                        .frame(width: rect.width, height: rect.height)
                        .offset(x: rect.minX, y: rect.minY)
                }

                header(board)
                    .frame(width: geometry.size.width)
                    .padding(.top, 12)
            }
        }
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder
    private var backdropView: some View {
        switch GlancePolicy.Backdrop(rawValue: backdrop) ?? .dim {
        case .clear:
            // Almost invisible, but still catches a click outside the panels.
            Color.black.opacity(0.02)
        case .dim:
            Color.black.opacity(0.32)
        case .blur:
            Rectangle().fill(.ultraThinMaterial).overlay(Color.black.opacity(0.18))
        }
    }

    /// A small bar at the top: the layout (switch it with several), edit, close.
    private func header(_ board: GlanceBoard) -> some View {
        HStack(spacing: 10) {
            if glance.boards.count > 1 {
                Menu {
                    ForEach(glance.boards) { other in
                        Button(other.name) { glance.switchBoard(other.id, onDisplay: displayKey) }
                    }
                } label: {
                    Text(board.name).font(.system(size: 12, weight: .semibold))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            Button {
                glance.hide()
                SettingsWindowController.shared.showWindow()
            } label: {
                Image(systemName: "slider.horizontal.3").font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.borderless)
            .help("Edit the layout in Settings")
            if glance.isPinned {
                Button {
                    glance.hide()
                } label: {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .bold))
                }
                .buttonStyle(.borderless)
                .help("Close (Esc)")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.1)))
        .opacity(0.85)
        .frame(maxWidth: .infinity)
    }
}

/// One panel: a glass card with what it shows, edge to edge. Hovering shows
/// its name (and Reload for a web page).
struct GlancePanelCard: View {
    let panel: GlancePanel
    @State private var hovering = false

    private static let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background {
                ZStack {
                    Self.shape.fill(.ultraThinMaterial)
                    Self.shape.fill(Color.black.opacity(0.38))
                }
            }
            .clipShape(Self.shape)
            .overlay(Self.shape.strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
            .overlay(alignment: .topTrailing) {
                if hovering { hoverBar }
            }
            .shadow(color: .black.opacity(0.35), radius: 22, y: 10)
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.15), value: hovering)
    }

    private var hoverBar: some View {
        HStack(spacing: 6) {
            Text(panel.title.isEmpty ? panel.kind.defaultTitle : panel.title)
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(1)
            if panel.kind == .web {
                Button {
                    GlanceWebPanels.shared.reload(panel.id)
                } label: {
                    Image(systemName: "arrow.clockwise").font(.system(size: 9, weight: .bold))
                }
                .buttonStyle(.borderless)
                .help("Reload")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(8)
        .transition(.opacity)
    }

    @ViewBuilder
    private var content: some View {
        switch panel.kind {
        case .web: GlanceWebPanelView(panel: panel)
        case .pdf: GlancePDFPanelView(panel: panel)
        case .window: GlanceLiveWindowPanel(panel: panel)
        case .calendar: GlanceTodayPanel()
        case .reminders: GlanceRemindersPanel()
        case .clocks: GlanceClocksPanel(timeZones: panel.timeZones)
        case .stocks: GlanceStocksPanel(symbols: panel.symbols)
        case .nowPlaying: GlanceNowPlayingPanel()
        case .promises: GlancePromisesPanel()
        case .setups: GlanceSetupsPanel()
        case .stash: GlanceStashPanel()
        case .whatsapp: GlanceWhatsAppPanel()
        }
    }
}

// MARK: - Web and PDF

/// Hosts a panel's kept-loaded page (it moves into whichever board shows it).
struct GlanceWebPanelView: NSViewRepresentable {
    let panel: GlancePanel

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        attach(to: container)
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        attach(to: container)
    }

    private func attach(to container: NSView) {
        let page = GlanceWebPanels.shared.view(for: panel)
        guard page.superview !== container else { return }
        page.removeFromSuperview()
        page.frame = container.bounds
        page.autoresizingMask = [.width, .height]
        container.addSubview(page)
    }
}

/// A PDF, opened on the page you left it on.
struct GlancePDFPanelView: NSViewRepresentable {
    let panel: GlancePanel

    final class Coordinator: NSObject {
        let panelID: String
        init(panelID: String) { self.panelID = panelID }

        @objc func pageChanged(_ note: Notification) {
            guard let view = note.object as? PDFView, let page = view.currentPage, let document = view.document else { return }
            let index = document.index(for: page)
            Defaults[.glancePDFPages][panelID] = index
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(panelID: panel.id.uuidString) }

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.backgroundColor = .clear
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.pageChanged(_:)),
                                               name: .PDFViewPageChanged, object: view)
        load(view)
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        if view.document?.documentURL?.path != (panel.address as NSString).expandingTildeInPath { load(view) }
    }

    private func load(_ view: PDFView) {
        guard !panel.address.isEmpty, let document = GlanceWebPanels.shared.pdf(at: panel.address) else {
            view.document = nil
            return
        }
        view.document = document
        if let index = Defaults[.glancePDFPages][panel.id.uuidString], let page = document.page(at: index) {
            view.go(to: page)
        }
    }
}

// MARK: - Built-in panels

private struct PanelMessage: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .padding(12)
    }
}

/// Today as a timeline: hours down the side, events as blocks, a red line at now.
struct GlanceTodayPanel: View {
    @State private var events: [EKEvent] = []
    @State private var allowed = true
    private static let store = EKEventStore()
    private static let hourHeight: CGFloat = 46

    var body: some View {
        Group {
            if !allowed {
                PanelMessage(text: "Allow Calendar access in Settings › Calendar & Todos.")
            } else {
                timeline
            }
        }
        .onAppear(perform: load)
    }

    private var timeline: some View {
        let allDay = events.filter(\.isAllDay)
        let timed = events.filter { !$0.isAllDay }
        return VStack(alignment: .leading, spacing: 6) {
            if !allDay.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(allDay, id: \.self) { event in
                        Text(event.title ?? "Event")
                            .font(.system(size: 11, weight: .semibold))
                            .lineLimit(1)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(cgColor: event.calendar.cgColor).opacity(0.35), in: RoundedRectangle(cornerRadius: 6))
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 10)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    ZStack(alignment: .topLeading) {
                        VStack(spacing: 0) {
                            ForEach(0..<24, id: \.self) { hour in
                                HStack(alignment: .top, spacing: 8) {
                                    Text(Self.hourLabel(hour))
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 40, alignment: .trailing)
                                    Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1).padding(.top, 6)
                                }
                                .frame(height: Self.hourHeight, alignment: .top)
                                .id(hour)
                            }
                        }
                        GeometryReader { geometry in
                            let left: CGFloat = 52
                            let width = geometry.size.width - left - 8
                            let columns = Self.columns(for: timed)
                            ForEach(Array(timed.enumerated()), id: \.offset) { index, event in
                                let column = columns[index]
                                let y = Self.offset(of: event.startDate) + 6
                                let height = max(22, Self.offset(of: event.endDate) - Self.offset(of: event.startDate) - 2)
                                let columnWidth = width / CGFloat(column.count)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(event.title ?? "Event").font(.system(size: 11, weight: .semibold)).lineLimit(height > 34 ? 2 : 1)
                                    if height > 34 {
                                        Text(event.startDate.formatted(date: .omitted, time: .shortened))
                                            .font(.system(size: 10)).foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.horizontal, 7).padding(.vertical, 4)
                                .frame(width: columnWidth - 3, height: height, alignment: .topLeading)
                                .background(Color(cgColor: event.calendar.cgColor).opacity(0.3), in: RoundedRectangle(cornerRadius: 7))
                                .overlay(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 2).fill(Color(cgColor: event.calendar.cgColor)).frame(width: 3)
                                }
                                .opacity(event.endDate < Date() ? 0.5 : 1)
                                .offset(x: left + CGFloat(column.index) * columnWidth, y: y)
                            }
                            TimelineView(.periodic(from: .now, by: 60)) { context in
                                HStack(spacing: 0) {
                                    Circle().fill(Color.red).frame(width: 7, height: 7)
                                    Rectangle().fill(Color.red).frame(height: 1.5)
                                }
                                .offset(x: left - 4, y: Self.offset(of: context.date) + 6 - 3.5)
                            }
                        }
                    }
                    .frame(height: Self.hourHeight * 24)
                    .padding(.trailing, 8)
                }
                .onAppear {
                    proxy.scrollTo(max(0, Calendar.current.component(.hour, from: Date()) - 1), anchor: .top)
                }
            }
        }
    }

    private func load() {
        let status = EKEventStore.authorizationStatus(for: .event)
        allowed = status == .fullAccess || status.rawValue == 3
        guard allowed else { return }
        let start = Calendar.current.startOfDay(for: Date())
        guard let end = Calendar.current.date(byAdding: .day, value: 1, to: start) else { return }
        let predicate = Self.store.predicateForEvents(withStart: start, end: end, calendars: nil)
        events = Self.store.events(matching: predicate).sorted { $0.startDate < $1.startDate }
    }

    private static func offset(of date: Date) -> CGFloat {
        let start = Calendar.current.startOfDay(for: Date())
        let hours = min(24, max(0, date.timeIntervalSince(start) / 3600))
        return CGFloat(hours) * hourHeight
    }

    private static func hourLabel(_ hour: Int) -> String {
        var components = DateComponents()
        components.hour = hour
        let date = Calendar.current.date(from: components) ?? Date()
        return date.formatted(.dateTime.hour())
    }

    /// Side by side for events at the same time: each event's column and how many share its time.
    private static func columns(for events: [EKEvent]) -> [(index: Int, count: Int)] {
        var result = [(index: Int, count: Int)](repeating: (0, 1), count: events.count)
        var columnEnds: [Date] = []
        var group: [Int] = []
        var groupEnd = Date.distantPast
        func closeGroup() {
            let width = max(1, columnEnds.count)
            for member in group { result[member].count = width }
            group = []
            columnEnds = []
        }
        for (index, event) in events.enumerated() {
            if event.startDate >= groupEnd { closeGroup() }
            if let free = columnEnds.firstIndex(where: { $0 <= event.startDate }) {
                columnEnds[free] = event.endDate
                result[index].index = free
            } else {
                columnEnds.append(event.endDate)
                result[index].index = columnEnds.count - 1
            }
            group.append(index)
            groupEnd = max(groupEnd, event.endDate)
        }
        closeGroup()
        return result
    }
}

/// Reminders to do, grouped by when (Today, Tomorrow, This week…); tick one off here.
struct GlanceRemindersPanel: View {
    @ObservedObject private var reminders = RemindersManager.shared

    private var groups: [(title: String, items: [ReminderItem])] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        let dayAfter = calendar.date(byAdding: .day, value: 2, to: today) ?? today
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: today) ?? today
        let open = reminders.reminders.filter { !$0.isCompleted }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
        func items(_ test: (Date?) -> Bool) -> [ReminderItem] { open.filter { test($0.dueDate) } }
        return [
            ("Overdue", items { $0.map { $0 < today } ?? false }),
            ("Today", items { $0.map { $0 >= today && $0 < tomorrow } ?? false }),
            ("Tomorrow", items { $0.map { $0 >= tomorrow && $0 < dayAfter } ?? false }),
            ("This week", items { $0.map { $0 >= dayAfter && $0 < weekEnd } ?? false }),
            ("Later", items { $0.map { $0 >= weekEnd } ?? false }),
            ("No date", items { $0 == nil }),
        ].filter { !$0.1.isEmpty }
    }

    var body: some View {
        Group {
            if groups.isEmpty {
                PanelMessage(text: "No reminders to do.")
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(groups, id: \.title) { group in
                            VStack(alignment: .leading, spacing: 0) {
                                Text(group.title)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(group.title == "Overdue" ? Color.red.opacity(0.9) : .secondary)
                                    .padding(.bottom, 4)
                                ForEach(group.items.prefix(12)) { item in
                                    row(item)
                                    if item.id != group.items.prefix(12).last?.id {
                                        Divider().opacity(0.3).padding(.leading, 26)
                                    }
                                }
                            }
                        }
                    }
                    .padding(14)
                }
            }
        }
        .task { await reminders.refresh() }
    }

    private func row(_ item: ReminderItem) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Button {
                Task { await reminders.setCompleted(item, completed: true) }
            } label: {
                Image(systemName: "circle").font(.system(size: 15, weight: .regular)).foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .disabled(!item.allowsChanges)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title).font(.system(size: 13, weight: .medium)).lineLimit(2)
                if let due = item.dueDate, item.hasDueTime {
                    Text(due.formatted(date: .omitted, time: .shortened)).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
    }
}

/// The time here and in the cities you chose, large.
struct GlanceClocksPanel: View {
    let timeZones: [String]

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            ScrollView {
                VStack(spacing: 0) {
                    row(name: "Local Time", zone: .current, now: context.date)
                    ForEach(timeZones, id: \.self) { identifier in
                        if let zone = TimeZone(identifier: identifier) {
                            Divider().opacity(0.3)
                            row(name: GlanceClocks.cityName(identifier), zone: zone, now: context.date)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }
    }

    private func row(name: String, zone: TimeZone, now: Date) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.system(size: 15, weight: .semibold))
                Text(GlanceClocks.zoneName(zone, now: now)).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(GlanceClocks.clock(now, in: zone))
                    .font(.system(size: 28, weight: .medium, design: .rounded).monospacedDigit())
                Text(GlanceClocks.meridiem(now, in: zone))
                    .font(.system(size: 13, weight: .medium))
            }
        }
        .padding(.vertical, 10)
    }
}

enum GlanceClocks {
    /// Cities offered when adding a clock.
    static let common: [(name: String, zone: String)] = [
        ("San Francisco", "America/Los_Angeles"), ("Chicago", "America/Chicago"), ("New York", "America/New_York"),
        ("Toronto", "America/Toronto"), ("São Paulo", "America/Sao_Paulo"), ("London", "Europe/London"),
        ("Paris", "Europe/Paris"), ("Berlin", "Europe/Berlin"), ("Dubai", "Asia/Dubai"), ("India", "Asia/Kolkata"),
        ("Singapore", "Asia/Singapore"), ("Hong Kong", "Asia/Hong_Kong"), ("Tokyo", "Asia/Tokyo"),
        ("Sydney", "Australia/Sydney"), ("Auckland", "Pacific/Auckland"),
    ]

    static func cityName(_ identifier: String) -> String {
        if let known = common.first(where: { $0.zone == identifier }) { return known.name }
        return (identifier.split(separator: "/").last.map(String.init) ?? identifier).replacingOccurrences(of: "_", with: " ")
    }

    /// "9:41" (12-hour clocks) or "21:41".
    static func clock(_ date: Date, in zone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = zone
        formatter.setLocalizedDateFormatFromTemplate("jmm")
        let text = formatter.string(from: date)
        let marker = meridiem(date, in: zone)
        return marker.isEmpty ? text : text.replacingOccurrences(of: marker, with: "").trimmingCharacters(in: .whitespaces)
    }

    /// "AM"/"PM" where the clock is 12-hour, else nothing.
    static func meridiem(_ date: Date, in zone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = zone
        formatter.setLocalizedDateFormatFromTemplate("jmm")
        guard formatter.dateFormat.contains("a") else { return "" }
        formatter.dateFormat = "a"
        return formatter.string(from: date)
    }

    /// "Eastern Time", "UK Time".
    static func zoneName(_ zone: TimeZone, now: Date) -> String {
        zone.localizedName(for: .generic, locale: .current) ?? zone.identifier
    }

    static func time(_ date: Date, in zone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = zone
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    static func dayDifference(_ zone: TimeZone, now: Date) -> String {
        var local = Calendar.current
        local.timeZone = .current
        var there = Calendar.current
        there.timeZone = zone
        let hereDay = local.ordinality(of: .day, in: .era, for: now) ?? 0
        let thereDay = there.ordinality(of: .day, in: .era, for: now) ?? 0
        let hours = Double(zone.secondsFromGMT(for: now) - TimeZone.current.secondsFromGMT(for: now)) / 3600
        let offset = hours == 0 ? "Same time" : String(format: "%@%g h", hours > 0 ? "+" : "", hours)
        switch thereDay - hereDay {
        case 1: return "Tomorrow, " + offset
        case -1: return "Yesterday, " + offset
        default: return "Today, " + offset
        }
    }
}

/// Promises still open, soonest first.
struct GlancePromisesPanel: View {
    @ObservedObject private var keeper = PromiseKeeper.shared

    var body: some View {
        if keeper.open.isEmpty {
            PanelMessage(text: "No open promises.")
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(keeper.open.prefix(20)) { promise in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(promise.title).font(.system(size: 13, weight: .medium)).lineLimit(2)
                            Text([promise.person, promise.due.formatted(date: .abbreviated, time: promise.hasExplicitTime ? .shortened : .omitted)]
                                    .filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.system(size: 11))
                                .foregroundStyle(promise.due < Date() ? Color.orange : .secondary)
                        }
                    }
                }
                .padding(12)
            }
        }
    }
}

/// Your window setups: click one to open it.
struct GlanceSetupsPanel: View {
    @ObservedObject private var manager = WorkspaceManager.shared

    var body: some View {
        if manager.workspaces.isEmpty {
            PanelMessage(text: "No setups yet. Save one from the Flow tab.")
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(manager.workspaces) { workspace in
                        Button {
                            GlanceManager.shared.hide()
                            manager.open(workspace)
                        } label: {
                            HStack {
                                Image(systemName: "rectangle.3.group")
                                Text(workspace.name).lineLimit(1)
                                Spacer()
                                Text("\(workspace.apps.count) apps").font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 6).padding(.horizontal, 8)
                            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(12)
            }
        }
    }
}

/// Stashed windows: click one to bring it back.
struct GlanceStashPanel: View {
    @ObservedObject private var stash = WindowStash.shared

    var body: some View {
        if stash.items.isEmpty {
            PanelMessage(text: "No stashed windows.")
        } else {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(stash.items) { item in
                        Button {
                            GlanceManager.shared.hide()
                            stash.restore(item)
                        } label: {
                            VStack(spacing: 4) {
                                if let preview = item.preview {
                                    Image(nsImage: preview).resizable().scaledToFit().frame(height: 54)
                                } else {
                                    Image(systemName: "macwindow").font(.title2).frame(height: 54)
                                }
                                Text(item.appName).font(.system(size: 11)).lineLimit(1)
                            }
                            .frame(width: 96)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(12)
            }
        }
    }
}

/// Recent WhatsApp chats, unread first.
struct GlanceWhatsAppPanel: View {
    @ObservedObject private var whatsApp = WhatsAppManager.shared

    var body: some View {
        if !whatsApp.state.isLinked {
            PanelMessage(text: "Link WhatsApp in Settings › WhatsApp.")
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(whatsApp.visibleChats.prefix(12)) { chat in
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(chat.displayName).font(.system(size: 13, weight: chat.unreadCount > 0 ? .semibold : .regular)).lineLimit(1)
                                Text(chat.preview ?? "").font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            if chat.unreadCount > 0 {
                                Text("\(chat.unreadCount)")
                                    .font(.system(size: 10, weight: .bold))
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Color.whatsAppGreen, in: Capsule())
                                    .foregroundStyle(.black)
                            }
                        }
                    }
                }
                .padding(12)
            }
        }
    }
}

// MARK: - Stocks

/// Prices with today's change and a small chart of the day.
struct GlanceStocksPanel: View {
    let symbols: [String]
    @ObservedObject private var stocks = GlanceStocks.shared

    var body: some View {
        if symbols.isEmpty {
            PanelMessage(text: "Add symbols in Settings › Glance (AAPL, RELIANCE.NS, ^NSEI, BTC-USD).")
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(symbols, id: \.self) { symbol in
                        row(symbol)
                    }
                }
                .padding(12)
            }
        }
    }

    @ViewBuilder
    private func row(_ symbol: String) -> some View {
        if let quote = stocks.quotes[symbol] {
            let up = (quote.change ?? 0) >= 0
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(quote.symbol).font(.system(size: 13, weight: .semibold))
                    Text(quote.name).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                GlanceSparkline(points: quote.points, color: up ? .green : .red)
                    .frame(width: 64, height: 24)
                VStack(alignment: .trailing, spacing: 1) {
                    Text(Self.price(quote.price, currency: quote.currency))
                        .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    if let percent = quote.changePercent {
                        Text(String(format: "%@%.2f%%", up ? "+" : "", percent))
                            .font(.system(size: 11, weight: .medium).monospacedDigit())
                            .foregroundStyle(up ? Color.green : Color.red)
                    }
                }
            }
        } else {
            HStack {
                Text(symbol).font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(stocks.failed.contains(symbol) ? "Not found" : "…")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private static func price(_ value: Double, currency: String?) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = currency == nil ? .decimal : .currency
        if let currency { formatter.currencyCode = currency }
        formatter.maximumFractionDigits = value < 10 ? 4 : 2
        formatter.minimumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
    }
}

/// A day's prices as a line.
struct GlanceSparkline: View {
    let points: [Double]
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            if points.count > 1, let low = points.min(), let high = points.max() {
                let span = max(high - low, 0.000001)
                Path { path in
                    for (index, value) in points.enumerated() {
                        let x = geometry.size.width * CGFloat(index) / CGFloat(points.count - 1)
                        let y = geometry.size.height * (1 - CGFloat((value - low) / span))
                        if index == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
                    }
                }
                .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }
        }
    }
}

// MARK: - Live window

/// Another app's window, live; click it to go to that window.
struct GlanceLiveWindowPanel: View {
    let panel: GlancePanel
    @ObservedObject private var live = GlanceLiveWindows.shared

    var body: some View {
        ZStack {
            GlanceLiveWindowLayer(panel: panel)
            if let problem = live.problems[panel.id] {
                PanelMessage(text: problem)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.regularMaterial)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            GlanceManager.shared.hide()
            GlanceLiveWindows.shared.bringForward(panel)
        }
        .help("Click to go to this window")
    }
}

private struct GlanceLiveWindowLayer: NSViewRepresentable {
    let panel: GlancePanel

    func makeNSView(context: Context) -> NSView {
        // A layer-hosting view: the layer first, then wantsLayer.
        let view = NSView()
        let layer = CALayer()
        layer.contentsGravity = .resizeAspect
        view.layer = layer
        view.wantsLayer = true
        GlanceLiveWindows.shared.register(panel, layer: layer)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        if let layer = view.layer { GlanceLiveWindows.shared.register(panel, layer: layer) }
    }
}

// MARK: - Now playing

/// What's playing (Spotify, Apple Music, a browser…): artwork, progress and controls.
struct GlanceNowPlayingPanel: View {
    @ObservedObject private var music = MusicManager.shared

    var body: some View {
        if music.isPlayerIdle && !music.isPlaying && music.songDuration == 0 {
            PanelMessage(text: "Nothing is playing.")
        } else {
            GeometryReader { geometry in
                VStack(alignment: .leading, spacing: 10) {
                    Image(nsImage: music.albumArt)
                        .resizable()
                        .aspectRatio(1, contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: max(60, geometry.size.height - 150))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .shadow(color: Color(nsColor: music.avgColor).opacity(0.5), radius: 16)
                        .frame(maxWidth: .infinity)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(music.songTitle).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                        Text(music.artistName).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let elapsed = currentElapsed(at: context.date)
                        VStack(spacing: 3) {
                            ProgressView(value: music.songDuration > 0 ? min(elapsed / music.songDuration, 1) : 0)
                                .progressViewStyle(.linear)
                                .tint(.white)
                            HStack {
                                Text(Self.time(elapsed))
                                Spacer()
                                Text(Self.time(music.songDuration))
                            }
                            .font(.system(size: 9).monospacedDigit())
                            .foregroundStyle(.secondary)
                        }
                    }
                    HStack {
                        control("shuffle", active: music.isShuffled) { music.toggleShuffle() }
                        Spacer()
                        control("backward.end.fill") { music.previousTrack() }
                        Spacer()
                        Button {
                            music.togglePlay()
                        } label: {
                            Image(systemName: music.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.black)
                                .frame(width: 40, height: 40)
                                .background(Color.white, in: Circle())
                        }
                        .buttonStyle(.plain)
                        Spacer()
                        control("forward.end.fill") { music.nextTrack() }
                        Spacer()
                        control("repeat", active: music.repeatMode != .off) { music.toggleRepeat() }
                    }
                }
                .padding(14)
            }
        }
    }

    private func currentElapsed(at date: Date) -> TimeInterval {
        guard music.isPlaying else { return music.elapsedTime }
        return min(music.songDuration, music.elapsedTime + date.timeIntervalSince(music.timestampDate) * music.playbackRate)
    }

    private func control(_ symbol: String, active: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(active ? Color.accentColor : .white)
        }
        .buttonStyle(.plain)
    }

    private static func time(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.isFinite ? seconds : 0))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
