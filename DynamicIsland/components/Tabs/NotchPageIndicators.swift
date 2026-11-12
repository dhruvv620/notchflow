// SPDX-License-Identifier: GPL-3.0-or-later

import Defaults
import SwiftUI

/// Reuses the existing bottom inset; it never enlarges the expanded panel.
struct NotchPageIndicators: View {
    @ObservedObject private var coordinator = DynamicIslandViewCoordinator.shared
    @ObservedObject private var appearance = NotchAppearanceModel.shared
    @Default(.notchActivityIndicators) private var enabled
    @Default(.notchIndicatorStyle) private var style

    var body: some View {
        let tabs = TabSelectionView.availableTabs
        if enabled && tabs.count > 1 {
            HStack(spacing: style == .dots ? 5 : 7) {
                ForEach(tabs) { tab in
                    let selected = tab.view == coordinator.currentView
                        && (tab.view != .extensionExperience || tab.experienceID == coordinator.selectedExtensionExperienceID)
                    Button {
                        coordinator.selectedExtensionExperienceID = tab.experienceID
                        coordinator.currentView = tab.view
                    } label: {
                        Group {
                            if style == .icons {
                                Image(systemName: tab.icon).font(.system(size: 9, weight: .semibold))
                            } else {
                                Capsule().frame(width: selected ? 12 : 4, height: 4)
                            }
                        }
                        .foregroundStyle(selected ? appearance.accentColor : Color.gray.opacity(0.65))
                        .frame(height: 10).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).help(tab.label).accessibilityLabel(tab.label)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
    }
}
