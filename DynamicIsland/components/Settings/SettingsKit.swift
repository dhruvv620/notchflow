// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620

import Defaults
import SwiftUI

// The Settings kit: the pieces every Settings page is built from, so all
// pages look and behave the same. The rules for using them are in
// docs/SETTINGS_DESIGN.md; read it before adding or changing a page.

/// The colours Settings uses, each with one meaning.
enum SettingsPalette {
    /// Main actions and switches: the user's macOS accent colour.
    static let accent = Color.accentColor
    /// Working, connected, done.
    static let ok = Color(red: 0.20, green: 0.78, blue: 0.35)
    /// Needs you: disconnected, waiting, not set up.
    static let warn = Color(red: 1.0, green: 0.62, blue: 0.04)
    /// Remove, errors.
    static let danger = Color(red: 1.0, green: 0.35, blue: 0.32)

    /// Sidebar groups: one colour each.
    static let general = Color(red: 0.30, green: 0.55, blue: 1.0)
    static let notch = Color(red: 0.13, green: 0.66, blue: 0.60)
    static let work = Color(red: 0.55, green: 0.42, blue: 1.0)
    static let system = Color(red: 0.43, green: 0.47, blue: 0.53)
}

/// A one-line status with a coloured dot: "Connected as Dhruv".
struct SettingsStatus: View {
    enum Kind { case ok, warn, error, neutral }
    let text: String
    var kind: Kind = .neutral

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text)
                .font(.caption)
                .foregroundStyle(kind == .neutral ? Color.secondary : color)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var color: Color {
        switch kind {
        case .ok: return SettingsPalette.ok
        case .warn: return SettingsPalette.warn
        case .error: return SettingsPalette.danger
        case .neutral: return .secondary
        }
    }
}

/// The top of every page: icon, title, one plain sentence, an optional
/// status line, and (on a feature's page) its main on/off switch.
struct SettingsPageHeader: View {
    let symbol: String
    let tint: Color
    let title: String
    let detail: String
    var status: SettingsStatus? = nil
    /// The feature's main switch; nil on pages without one.
    var isOn: Binding<Bool>? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(tint.gradient)
                .frame(width: 40, height: 40)
                .overlay {
                    Image(systemName: symbol)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.title2.weight(.bold))
                Text(detail).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let status { status.padding(.top, 2) }
            }
            Spacer(minLength: 8)
            if let isOn {
                Toggle(title, isOn: isOn)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.large)
                    .accessibilityLabel("Use \(title)")
            }
        }
        .padding(.vertical, 6)
    }
}

/// A row's title with an optional one-line explanation under it.
struct SettingsRowLabel: View {
    let title: String
    var detail: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// A switch row bound to a setting, with its explanation and search tag.
struct SettingsToggle: View {
    let key: Defaults.Key<Bool>
    let title: String
    var detail: String? = nil
    /// The search tag ("<page>-<title>"); nil when the row isn't searchable.
    var highlightID: String? = nil

    var body: some View {
        let toggle = Defaults.Toggle(key: key) { SettingsRowLabel(title: title, detail: detail) }
        if let highlightID {
            toggle.settingsHighlight(id: highlightID)
        } else {
            toggle
        }
    }
}

/// The three kinds of buttons.
extension View {
    /// The one main action of a section (filled, accent colour).
    func settingsPrimaryButton() -> some View {
        buttonStyle(.borderedProminent).tint(SettingsPalette.accent)
    }

    /// Removes or resets something. Pair it with a confirmation.
    func settingsDestructiveButton() -> some View {
        buttonStyle(.bordered).tint(SettingsPalette.danger)
    }
}
