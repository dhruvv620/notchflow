// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import Defaults
import SwiftUI

/// The Notifications tab: every collected notification grouped by app, with
/// inline replies, per-app filters, and Clear with Undo.
struct NotchNotificationsView: View {
    @EnvironmentObject private var vm: DynamicIslandViewModel
    @ObservedObject private var hub = NotificationHub.shared
    @ObservedObject private var communications = CommunicationsManager.shared
    @ObservedObject private var fullDiskAccess = FullDiskAccessPermissionStore.shared
    @ObservedObject private var appearance = NotchAppearanceModel.shared
    @Default(.communicationsEnabled) private var enabled
    @State private var expandedGroups: Set<String> = []
    @State private var token = UUID()

    /// Header row, spacing and padding around the list.
    private static let chromeHeight: CGFloat = 36
    private static let emptyStateHeight: CGFloat = 130

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            if !enabled {
                NotchEmptyState(
                    symbol: "bell.slash",
                    title: "Notifications are off",
                    detail: "Collect notifications from your apps here, reply without switching apps, and clear them in one place."
                ) {
                    Button("Turn On") { enabled = true }
                        .buttonStyle(.borderedProminent)
                }
            } else if hub.items.isEmpty {
                emptyInbox
                    .onAppear {
                        DynamicIslandViewCoordinator.shared.reportContentHeight(Self.emptyStateHeight, for: .notifications)
                    }
            } else {
                list
            }
        }
        .notchTabPadding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay(alignment: .bottom) { undoToast }
        .environment(\.colorScheme, .dark)
        .tint(appearance.accentColor)
        .task { await hub.refresh() }
        .onAppear {
            hub.dismissAlert()
            hub.markViewed()
            if !enabled { DynamicIslandViewCoordinator.shared.reportContentHeight(nil, for: .notifications) }
        }
        .onChange(of: hub.replyingID) { _, value in
            vm.setAutoCloseSuppression(value != nil, token: token)
        }
        .onDisappear {
            hub.markViewed()
            hub.replyingID = nil
            vm.setAutoCloseSuppression(false, token: token)
            vm.setScrollGestureSuppression(false, token: token)
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 6) {
            Text("Notifications")
                .font(NotchTokens.Typography.title)
            if !hub.items.isEmpty {
                NotchBadge(text: "\(hub.items.count)")
            }
            if hub.allGroups.count > 1 {
                filterChips
            } else {
                Spacer(minLength: 0)
            }
            NotchIconButton(symbol: "arrow.clockwise", help: "Check for new notifications") {
                Task { await hub.refresh() }
            }
            NotchIconButton(symbol: "xmark.circle", help: hub.filter == nil ? "Clear all notifications" : "Clear this app's notifications") {
                withAnimation(.snappy) { hub.clearVisible() }
            }
            .disabled(hub.visibleItems.isEmpty)
        }
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                NotchChip(isSelected: hub.filter == nil, action: { withAnimation(.snappy) { hub.filter = nil } }) {
                    Text("All")
                }
                ForEach(hub.allGroups) { group in
                    NotchChip(isSelected: hub.filter == group.id, action: {
                        withAnimation(.snappy) { hub.filter = hub.filter == group.id ? nil : group.id }
                    }) {
                        HStack(spacing: 3) {
                            NotificationAppIcon(bundleIdentifier: group.bundleIdentifier, appName: group.appName, size: 13)
                            Text("\(group.items.count)").font(.system(size: 10, weight: .semibold).monospacedDigit())
                        }
                    }
                    .help(group.appName)
                }
            }
            .padding(.horizontal, 2)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: List

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(hub.groups) { group in
                        groupSection(group)
                    }
                    if let error = hub.lastError {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.orange)
                            .lineLimit(3)
                            .padding(.horizontal, 4)
                            .transition(.opacity)
                    }
                }
                .padding(.bottom, hub.undoSnapshot == nil ? 2 : 30)
                .background {
                    GeometryReader { geometry in
                        Color.clear.preference(key: NotificationListHeightKey.self, value: geometry.size.height)
                    }
                }
            }
            // The panel follows the list: a couple of notifications make a
            // short notch, a long inbox a taller one, within the tab's limits.
            .onPreferenceChange(NotificationListHeightKey.self) { height in
                DynamicIslandViewCoordinator.shared.reportContentHeight(height + Self.chromeHeight, for: .notifications)
            }
            .onHover { vm.setScrollGestureSuppression($0, token: token) }
            .onChange(of: hub.replyingID) { _, id in
                guard let id else { return }
                withAnimation(.snappy) { proxy.scrollTo(id, anchor: .center) }
            }
            .onChange(of: hub.highlightedID) { _, id in
                guard let id else { return }
                withAnimation(.snappy) { proxy.scrollTo(id, anchor: .top) }
            }
            .onAppear {
                if let id = hub.highlightedID { proxy.scrollTo(id, anchor: .top) }
            }
        }
    }

    @ViewBuilder
    private func groupSection(_ group: NotchNotificationGroup) -> some View {
        let isExpanded = expandedGroups.contains(group.id) || hub.filter == group.id
        let shown = isExpanded ? group.items : Array(group.items.prefix(2))
        VStack(alignment: .leading, spacing: 4) {
            if hub.filter == nil {
                HStack(spacing: 5) {
                    NotificationAppIcon(bundleIdentifier: group.bundleIdentifier, appName: group.appName, size: 12)
                    Text(group.appName)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    if group.items.count > 2 {
                        Button(isExpanded ? "Show less" : "Show all \(group.items.count)") {
                            withAnimation(.snappy) {
                                if isExpanded { expandedGroups.remove(group.id) } else { expandedGroups.insert(group.id) }
                            }
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(appearance.accentColor)
                    }
                    Button {
                        withAnimation(.snappy) { hub.clearGroup(group.id) }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                            .frame(width: 16, height: 16)
                            .background(Color.white.opacity(0.08), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Clear \(group.appName)")
                }
                .padding(.horizontal, 4)
                .padding(.top, 2)
            }
            ForEach(shown) { item in
                NotificationCard(item: item)
                    .id(item.id)
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .move(edge: .trailing).combined(with: .opacity)
                    ))
            }
        }
    }

    // MARK: Empty and setup states

    private var emptyInbox: some View {
        VStack(spacing: 8) {
            NotchEmptyState(
                symbol: "checkmark.circle",
                title: "You're all caught up",
                detail: sourceSummary
            ) {
                if hub.centerState == .needsFullDiskAccess {
                    Button("Allow Full Disk Access") { fullDiskAccess.requestAccessPrompt() }
                        .buttonStyle(.borderedProminent)
                }
                if !communications.accessGranted {
                    Button("Allow Accessibility") { communications.requestAccess() }
                }
            }
        }
    }

    private var sourceSummary: String {
        switch hub.centerState {
        case .reading:
            return "New notifications from your apps appear here as they arrive."
        case .off:
            return communications.accessGranted
                ? "Showing banners as they appear. Turn on Notification Center history in Settings to catch every app."
                : "Allow Accessibility so NotchFlow can see banners, or Full Disk Access to read Notification Center."
        default:
            return hub.centerState.message
        }
    }

    // MARK: Undo

    @ViewBuilder
    private var undoToast: some View {
        if let snapshot = hub.undoSnapshot {
            HStack(spacing: 10) {
                Image(systemName: "trash")
                    .font(.system(size: 10, weight: .semibold))
                Text(snapshot.count == 1 ? "Cleared 1 notification" : "Cleared \(snapshot.count) notifications")
                    .font(.system(size: 11, weight: .medium))
                Spacer(minLength: 0)
                Button("Undo") { hub.undoClear() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(appearance.accentColor)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.1)))
            .padding(.horizontal, 40)
            .padding(.bottom, 6)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

// MARK: - Card

private struct NotificationCard: View {
    let item: NotchNotification
    @ObservedObject private var hub = NotificationHub.shared
    @ObservedObject private var appearance = NotchAppearanceModel.shared
    @Default(.communicationShowPreviews) private var showPreviews
    @State private var isHovering = false
    @State private var isExpanded = false
    @State private var draft = ""
    @FocusState private var replyFocused: Bool

    private var isReplying: Bool { hub.replyingID == item.id }
    private var isSending: Bool { hub.sendingIDs.contains(item.id) }
    private var wasReplied: Bool { hub.repliedIDs.contains(item.id) }
    private var isHighlighted: Bool { hub.highlightedID == item.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                NotificationAppIcon(bundleIdentifier: item.bundleIdentifier, appName: item.appName, size: 26)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(showPreviews ? item.headline : item.appName)
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)
                        if wasReplied {
                            Label("Replied", systemImage: "arrowshape.turn.up.left.fill")
                                .labelStyle(.iconOnly)
                                .font(.system(size: 9))
                                .foregroundStyle(appearance.accentColor)
                                .help("Replied")
                        }
                        Spacer(minLength: 4)
                        TimelineView(.periodic(from: .now, by: 30)) { context in
                            Text(WhatsAppTimeFormatter.short(item.date, now: context.date))
                                .font(.system(size: 10).monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    if showPreviews, !item.subtitle.isEmpty {
                        Text(item.subtitle)
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                    }
                    Text(showPreviews ? item.body : "Preview hidden")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(isExpanded ? 8 : 2)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            // Only the text toggles the full message, so taps in the reply
            // field and on the buttons below are never intercepted.
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.snappy) { isExpanded.toggle() }
            }

            if isReplying {
                replyField
                    .transition(.move(edge: .top).combined(with: .opacity))
            } else if isHovering || isHighlighted {
                actions
                    .transition(.opacity)
            }
        }
        .padding(NotchTokens.Spacing.m)
        .background { NotchElementSurface(cornerRadius: NotchTokens.Radius.card) }
        .overlay {
            RoundedRectangle(cornerRadius: NotchTokens.Radius.card)
                .strokeBorder(appearance.accentColor.opacity(isHighlighted ? 0.7 : 0), lineWidth: 1.5)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .topTrailing) {
            if isHovering && !isReplying {
                Button {
                    withAnimation(.snappy) { hub.dismiss(item) }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .frame(width: 18, height: 18)
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.15)))
                }
                .buttonStyle(.plain)
                .offset(x: 5, y: -5)
                .transition(.scale.combined(with: .opacity))
                .help("Dismiss")
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) { isHovering = hovering }
        }
        .contextMenu { menu }
        .onChange(of: isReplying) { _, replying in
            if replying {
                replyFocused = true
            } else {
                draft = ""
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(item.appName): \(item.headline). \(item.body)")
    }

    private var actions: some View {
        HStack(spacing: 6) {
            if hub.canReply(item) {
                NotchPillButton(title: "Reply", symbol: "arrowshape.turn.up.left", prominent: true) {
                    withAnimation(.snappy) { hub.replyingID = item.id }
                }
            }
            NotchPillButton(title: "Open", symbol: "arrow.up.right.square") {
                hub.open(item)
            }
            Spacer(minLength: 0)
            if item.bundleIdentifier != nil {
                Menu {
                    menu
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 22, height: 18)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
        }
        .padding(.leading, 34)
    }

    private var replyField: some View {
        NotchComposeField(
            placeholder: "Reply to \(item.headline)",
            text: $draft,
            isSending: isSending,
            onSend: send,
            onCancel: { withAnimation(NotchTokens.Motion.standard) { hub.replyingID = nil } },
            isFocused: $replyFocused
        )
        .padding(.leading, 34)
    }

    private var canSend: Bool {
        !isSending && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func send() {
        guard canSend else { return }
        let text = draft
        Task {
            if await hub.sendReply(text, to: item) {
                draft = ""
            }
        }
    }

    @ViewBuilder
    private var menu: some View {
        if hub.canReply(item) {
            Button("Reply") { withAnimation(.snappy) { hub.replyingID = item.id } }
        }
        Button("Open \(item.appName)") { hub.open(item) }
        Button("Copy Text") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString([item.title, item.subtitle, item.body].filter { !$0.isEmpty }.joined(separator: "\n"), forType: .string)
        }
        Button("Add to Todos") {
            Task { await RemindersManager.shared.capture(TodoCapturePolicy.followUpTitle(sender: item.headline, body: item.body)) }
        }
        Divider()
        Button("Dismiss") { withAnimation(.snappy) { hub.dismiss(item) } }
        if item.bundleIdentifier != nil {
            Button("Mute \(item.appName)") { withAnimation(.snappy) { hub.mute(item) } }
        }
    }
}

// MARK: - Small parts

/// The posting app's icon, or a symbol when the app is not installed.
struct NotificationAppIcon: View {
    let bundleIdentifier: String?
    let appName: String
    var size: CGFloat = 24

    var body: some View {
        Group {
            if let image = NotificationAppIconCache.icon(for: bundleIdentifier) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                        .fill(fallbackColor.opacity(0.25))
                    Image(systemName: fallbackSymbol)
                        .font(.system(size: size * 0.5, weight: .semibold))
                        .foregroundStyle(fallbackColor)
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var isWhatsApp: Bool {
        bundleIdentifier.map { NotchNotificationPolicy.whatsAppBundleIdentifiers.contains($0) } ?? false
    }
    private var fallbackSymbol: String { isWhatsApp ? "message.fill" : "app.badge" }
    private var fallbackColor: Color { isWhatsApp ? Color(red: 0.145, green: 0.827, blue: 0.4) : .gray }
}

enum NotificationAppIconCache {
    private static let cache = NSCache<NSString, NSImage>()
    private static var missing = Set<String>()

    @MainActor
    static func icon(for bundleIdentifier: String?) -> NSImage? {
        guard let bundleIdentifier else { return nil }
        if let cached = cache.object(forKey: bundleIdentifier as NSString) { return cached }
        if missing.contains(bundleIdentifier) { return nil }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            missing.insert(bundleIdentifier)
            return nil
        }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        cache.setObject(image, forKey: bundleIdentifier as NSString)
        return image
    }
}

private struct NotificationListHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
