// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Saved tab choices contain identifiers, never view labels or transient array indices.
enum NotchTabOrderPolicy {
    static func normalizedOrder(_ saved: [String], known: [String]) -> [String] {
        let knownIDs = Set(known)
        var seen = Set<String>()
        let retained = saved.filter { knownIDs.contains($0) && seen.insert($0).inserted }
        return retained + known.filter { seen.insert($0).inserted }
    }

    static func visibleIDs(order: [String], hidden: [String], available: [String], fallback: String) -> [String] {
        let availableIDs = Set(available)
        let hiddenIDs = Set(hidden)
        let result = normalizedOrder(order, known: available).filter { availableIDs.contains($0) && !hiddenIDs.contains($0) }
        if !result.isEmpty { return result }
        return availableIDs.contains(fallback) ? [fallback] : Array(available.prefix(1))
    }

    static func moving(_ source: String, over target: String, in order: [String]) -> [String] {
        guard source != target, let sourceIndex = order.firstIndex(of: source),
              let targetIndex = order.firstIndex(of: target) else { return order }
        var result = order
        result.remove(at: sourceIndex)
        result.insert(source, at: targetIndex)
        return result
    }

    /// Native List destinations refer to positions before removing the dragged rows.
    static func movingRows(from offsets: IndexSet, to destination: Int, in order: [String]) -> [String] {
        let valid = offsets.filter { order.indices.contains($0) }
        guard !valid.isEmpty else { return order }
        let moving = valid.map { order[$0] }
        let selected = Set(valid)
        var remaining = order.enumerated().filter { !selected.contains($0.offset) }.map(\.element)
        let adjusted = destination - valid.filter { $0 < destination }.count
        remaining.insert(contentsOf: moving, at: min(max(adjusted, 0), remaining.count))
        return remaining
    }

    /// Move before the target, preserving every other identifier's relative order.
    static func moving(_ source: String, before target: String, in order: [String]) -> [String] {
        guard source != target, order.contains(source), order.contains(target) else { return order }
        var result = order.filter { $0 != source }
        guard let index = result.firstIndex(of: target) else { return order }
        result.insert(source, at: index)
        return result
    }
}
