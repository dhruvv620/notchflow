import Foundation

@main
enum ShelfCleanupRegression {
    static func main() {
        let removedWhileValidating = UUID()
        let unchangedInvalidItem = UUID()
        let refreshedWhileValidating = UUID()

        let oldBookmark = Data("old".utf8)
        let refreshedBookmark = Data("refreshed".utf8)

        let removable = ShelfCleanupPolicy.removableIDs(
            invalidCandidates: [
                removedWhileValidating: oldBookmark,
                unchangedInvalidItem: oldBookmark,
                refreshedWhileValidating: oldBookmark,
            ],
            currentBookmarks: [
                unchangedInvalidItem: oldBookmark,
                refreshedWhileValidating: refreshedBookmark,
            ]
        )

        precondition(removable == Set([unchangedInvalidItem]))
        precondition(!removable.contains(removedWhileValidating), "A removed item must not be resurrected or processed again")
        precondition(!removable.contains(refreshedWhileValidating), "A stale validation must not remove a refreshed bookmark")

        print("Shelf cleanup regression checks passed")
    }
}
