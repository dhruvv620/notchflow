import SwiftUI

/// Keeps the camera area black and brings color into the expanded surface.
struct NotchFlowSurface: View {
    let theme: String
    let expanded: Bool

    private var colors: [Color] {
        switch theme {
        case "aurora": return [.black, Color(red: 0.05, green: 0.14, blue: 0.22), Color(red: 0.12, green: 0.25, blue: 0.25)]
        case "sunset": return [.black, Color(red: 0.19, green: 0.10, blue: 0.18), Color(red: 0.31, green: 0.19, blue: 0.17)]
        default: return [.black, Color(white: 0.15), Color(white: 0.34)]
        }
    }

    var body: some View {
        ZStack {
            Color.black
            if expanded && theme != "classic" {
                LinearGradient(stops: [
                    .init(color: colors[0], location: 0),
                    .init(color: colors[0], location: 0.12),
                    .init(color: colors[1], location: 0.48),
                    .init(color: colors[2], location: 1)
                ], startPoint: .top, endPoint: .bottom)
            }
        }
        .allowsHitTesting(false)
    }
}
