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

/// The board itself: your panels over a dimmed, blurred screen.
struct GlanceBoardView: View {
    /// The display this board is on.
    let displayKey: String
    @ObservedObject private var glance = GlanceManager.shared

    var body: some View {
        if let board = glance.board(onDisplay: displayKey) {
            content(board)
        } else {
            Color.clear
        }
    }

    private func content(_ board: GlanceBoard) -> some View {
        GeometryReader { geometry in
            let area = CGRect(x: 36, y: 72, width: max(200, geometry.size.width - 72), height: max(200, geometry.size.height - 108))
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .overlay(Color.black.opacity(0.35))
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { glance.hide() }

                header(board)
                    .frame(width: geometry.size.width)
                    .padding(.top, 34)

                let shown = board.panels.filter(\.isShown)
                if shown.isEmpty {
                    Text("Nothing on this board yet. Add panels in Settings › Glance.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .allowsHitTesting(false)
                }
                ForEach(shown) { panel in
                    let rect = GlanceLayout.rect(for: panel.frame, in: area, gap: 16)
                    GlancePanelCard(panel: panel)
                        .frame(width: rect.width, height: rect.height)
                        .offset(x: rect.minX, y: rect.minY)
                }
            }
        }
        .environment(\.colorScheme, .dark)
    }

    private func header(_ board: GlanceBoard) -> some View {
        HStack(spacing: 12) {
            if glance.boards.count > 1 {
                Menu {
                    ForEach(glance.boards) { other in
                        Button(other.name) { glance.switchBoard(other.id, onDisplay: displayKey) }
                    }
                } label: {
                    Label(board.name, systemImage: "square.grid.2x2")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            } else {
                Label(board.name, systemImage: "square.grid.2x2")
                    .font(.headline)
            }
            Text(glance.isPinned ? "Esc or the shortcut closes it" : "Let go to close · tap the shortcut to keep it open")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer().frame(width: 12)
            Button("Edit Layout") {
                glance.hide()
                SettingsWindowController.shared.showWindow()
            }
            .buttonStyle(.borderless)
            if glance.isPinned {
                Button {
                    glance.hide()
                } label: {
                    Image(systemName: "xmark.circle.fill").font(.title3)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
        .frame(maxWidth: .infinity)
    }
}

/// One panel: a title bar and what it shows.
struct GlancePanelCard: View {
    let panel: GlancePanel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: panel.kind.symbol)
                    .foregroundStyle(.secondary)
                Text(panel.title.isEmpty ? panel.kind.defaultTitle : panel.title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
                if panel.kind == .web {
                    Button {
                        GlanceWebPanels.shared.reload(panel.id)
                    } label: {
                        Image(systemName: "arrow.clockwise").font(.system(size: 10, weight: .semibold))
                    }
                    .buttonStyle(.borderless)
                    .help("Reload")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            Divider().opacity(0.4)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.08)))
        .shadow(color: .black.opacity(0.3), radius: 18, y: 8)
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

/// Today's events from your calendars.
struct GlanceTodayPanel: View {
    @State private var events: [EKEvent] = []
    @State private var allowed = true
    private static let store = EKEventStore()

    var body: some View {
        Group {
            if !allowed {
                PanelMessage(text: "Allow Calendar access in Settings › Calendar & Todos.")
            } else if events.isEmpty {
                PanelMessage(text: "Nothing else today.")
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(events, id: \.self) { event in
                            HStack(alignment: .top, spacing: 8) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color(cgColor: event.calendar.cgColor))
                                    .frame(width: 4, height: 30)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(event.title ?? "Event")
                                        .font(.system(size: 13, weight: .medium))
                                        .lineLimit(2)
                                    Text(event.isAllDay ? "All day" : Self.time(event.startDate) + " – " + Self.time(event.endDate))
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .opacity(event.endDate < Date() ? 0.45 : 1)
                        }
                    }
                    .padding(12)
                }
            }
        }
        .onAppear(perform: load)
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

    private static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }
}

/// Reminders still to do, soonest first; tick one off from here.
struct GlanceRemindersPanel: View {
    @ObservedObject private var reminders = RemindersManager.shared

    private var open: [ReminderItem] {
        reminders.reminders.filter { !$0.isCompleted }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    }

    var body: some View {
        Group {
            if open.isEmpty {
                PanelMessage(text: "No reminders to do.")
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(open.prefix(20)) { item in
                            HStack(spacing: 8) {
                                Button {
                                    Task { await reminders.setCompleted(item, completed: true) }
                                } label: {
                                    Image(systemName: "circle").font(.system(size: 14))
                                }
                                .buttonStyle(.borderless)
                                .disabled(!item.allowsChanges)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.title).font(.system(size: 13)).lineLimit(2)
                                    if let due = item.dueDate {
                                        Text(due.formatted(date: .abbreviated, time: item.hasDueTime ? .shortened : .omitted))
                                            .font(.system(size: 11))
                                            .foregroundStyle(due < Date() ? Color.red : .secondary)
                                    }
                                }
                            }
                        }
                    }
                    .padding(12)
                }
            }
        }
        .task { await reminders.refresh() }
    }
}

/// The time here and in the cities you chose.
struct GlanceClocksPanel: View {
    let timeZones: [String]

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    row(name: "Here", zone: .current, now: context.date)
                    ForEach(timeZones, id: \.self) { identifier in
                        if let zone = TimeZone(identifier: identifier) {
                            row(name: GlanceClocks.cityName(identifier), zone: zone, now: context.date)
                        }
                    }
                }
                .padding(12)
            }
        }
    }

    private func row(name: String, zone: TimeZone, now: Date) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(.system(size: 13, weight: .medium))
                Text(GlanceClocks.dayDifference(zone, now: now)).font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer()
            Text(GlanceClocks.time(now, in: zone))
                .font(.system(size: 20, weight: .semibold, design: .rounded).monospacedDigit())
        }
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
