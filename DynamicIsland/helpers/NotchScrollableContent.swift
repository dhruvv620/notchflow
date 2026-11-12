// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// Vertical scrolling belongs to a utility's content, while horizontal swipes
/// remain available for tab navigation. Each transitioning page owns its token.
struct NotchScrollableContent<Content: View>: View {
    @EnvironmentObject private var vm: DynamicIslandViewModel
    @State private var token = UUID()
    let content: Content

    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        ScrollView { content }
            .onHover { vm.setScrollGestureSuppression($0, token: token) }
            .onDisappear { vm.setScrollGestureSuppression(false, token: token) }
    }
}
