// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

@main
struct NotchTabOrderRegression {
    static func main() throws {
        func require(_ value: @autoclosure () -> Bool, _ message: String) throws {
            if !value() { throw NSError(domain: "NotchTabOrderRegression", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        let known = ["music", "timers", "clipboard", "todos", "calendar"]
        let restored = NotchTabOrderPolicy.normalizedOrder(["todos", "missing", "music", "todos"], known: known)
        try require(restored == ["todos", "music", "timers", "clipboard", "calendar"], "Restored order retained unknown/duplicate IDs or lost new tabs")
        let order = ["todos", "clipboard", "music", "timers", "calendar"]
        let available = ["music", "timers", "clipboard", "todos"]
        try require(NotchTabOrderPolicy.visibleIDs(order: order, hidden: ["clipboard"], available: available, fallback: "music") == ["todos", "music", "timers"], "Visibility/order was not shared with available feature tabs")
        try require(NotchTabOrderPolicy.visibleIDs(order: order, hidden: available, available: available, fallback: "music") == ["music"], "All-hidden choices did not preserve a usable Music fallback")
        try require(NotchTabOrderPolicy.visibleIDs(order: [], hidden: [], available: [], fallback: "music").isEmpty, "Empty catalog created a phantom tab")
        try require(NotchTabOrderPolicy.moving("music", before: "todos", in: order) == ["music", "todos", "clipboard", "timers", "calendar"], "Drag reorder lost relative order")
        try require(NotchTabOrderPolicy.moving("missing", before: "todos", in: order) == order, "External drag corrupted saved order")
        try require(NotchTabOrderPolicy.moving("music", over: "calendar", in: order) == ["todos", "clipboard", "timers", "calendar", "music"], "Downward drag could not reach final row")
        try require(NotchTabOrderPolicy.moving("calendar", over: "todos", in: order) == ["calendar", "todos", "clipboard", "music", "timers"], "Upward drag could not reach first row")
        let extensions = NotchTabOrderPolicy.normalizedOrder(["extension-editor", "music"], known: ["music", "extension-editor", "extension-build"])
        try require(extensions == ["extension-editor", "music", "extension-build"], "Extension IDs lost stable ordering")
        try require(NotchTabOrderPolicy.movingRows(from: IndexSet(integer: 0), to: 4, in: ["music", "timers", "clipboard", "todos"]) == ["timers", "clipboard", "todos", "music"], "Native drag destination did not account for removed rows")
        try require(NotchTabOrderPolicy.movingRows(from: IndexSet([1, 3]), to: 0, in: ["music", "timers", "clipboard", "todos"]) == ["timers", "todos", "music", "clipboard"], "Native multi-row drag changed selection order")
        try require(NotchTabOrderPolicy.movingRows(from: IndexSet(integer: 1), to: 2, in: known) == known, "Dropping a row into its own gap should keep its order")
        print("Notch tab order/visibility checks passed")
    }
}
