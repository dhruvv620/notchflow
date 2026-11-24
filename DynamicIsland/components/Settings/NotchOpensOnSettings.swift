// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620

import Defaults
import SwiftUI

/// Settings > General: which tab the notch opens on.
struct NotchOpensOnSettings: View {
    @Default(.notchOpenTabMode) private var modeValue
    @Default(.notchContextAwareTab) private var legacySmart
    @Default(.notchOpenFixedTab) private var fixedTab
    @Default(.notchSmartTabSkips) private var skips
    @Default(.notchOpenUrgentFirst) private var urgentFirst
    @ObservedObject private var preferences = NotchTabPreferences.shared

    private var mode: NotchOpenTabMode {
        _ = (modeValue, legacySmart)  // redraw when either changes
        return NotchOpenTab.mode
    }

    private var modeBinding: Binding<NotchOpenTabMode> {
        Binding(get: { mode }, set: { NotchOpenTab.setMode($0) })
    }

    /// Tabs you can pick for "Always this tab": the ones that are on.
    private var tabs: [NotchBuiltinTab] {
        _ = preferences.revision
        return preferences.orderedBuiltins.filter { $0.featureIsEnabled && preferences.isShown($0.rawValue) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Opens on", selection: modeBinding) {
                ForEach(NotchOpenTabMode.allCases, id: \.self) { option in
                    Text(option.title).tag(option)
                }
            }
            Text(explanation)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if mode == .fixed {
                Picker("Tab", selection: $fixedTab) {
                    ForEach(tabs) { tab in
                        Label(tab.title, systemImage: tab.symbol).tag(tab.rawValue)
                    }
                }
                .padding(.leading, 16)
            }

            if mode == .smart {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Smart may open:").font(.caption).foregroundStyle(.secondary)
                    smartToggle("Calendar, five minutes before a meeting", reason: "calendar")
                    smartToggle("Timers, while one runs", reason: "timer")
                    smartToggle("WhatsApp, when there are unread messages", reason: "whatsapp")
                    smartToggle("Notifications, when something new arrived", reason: "notifications")
                    smartToggle("Music, while something plays", reason: "music")
                }
                .padding(.leading, 16)
            }

            Toggle(isOn: $urgentFirst) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Something that needs you opens its tab first")
                    Text("An AI agent waiting for approval, a promise coming due, the weekly report, or something you just copied.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var explanation: String {
        switch mode {
        case .music: return String(localized: "Every time, the notch opens on Music.")
        case .fixed: return String(localized: "Every time, the notch opens on the tab you pick below.")
        case .last: return String(localized: "The notch opens where you left it.")
        case .smart: return String(localized: "The notch picks the tab for what's happening, and opens on Music otherwise. Turn off any reason you don't want below.")
        }
    }

    private func smartToggle(_ title: String, reason: String) -> some View {
        Toggle(title, isOn: Binding(
            get: { !skips.contains(reason) },
            set: { on in
                var next = Set(skips)
                if on { next.remove(reason) } else { next.insert(reason) }
                skips = next.sorted()
            }
        ))
        .toggleStyle(.checkbox)
    }
}
