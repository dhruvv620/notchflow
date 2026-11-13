// SPDX-License-Identifier: GPL-3.0-or-later
import ApplicationServices
import Foundation
import CoreGraphics

/// Synchronous AX primitives. Callers own a serial worker queue; never traverse
/// another application's UI on the SwiftUI/main thread.
enum CommunicationsAX {
    struct Node {
        let element: AXUIElement
        let parentIndex: Int?
        let role: String
        let identifier: String
        let title: String
        let description: String
        let value: String
        let labels: [String]
        let isEnabled: Bool
        let actionNames: [String]
    }
    static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }
    static func children(_ element: AXUIElement) -> [AXUIElement] {
        let visible = elements(element, "AXVisibleChildren")
        return visible.isEmpty ? elements(element, kAXChildrenAttribute) : visible
    }
    static func elements(_ element: AXUIElement, _ attribute: String) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return [] }
        return value as? [AXUIElement] ?? []
    }
    static func role(_ element: AXUIElement) -> String { string(element, kAXRoleAttribute) ?? "" }
    static func identifier(_ element: AXUIElement) -> String { string(element, kAXIdentifierAttribute) ?? "" }
    static func boolean(_ element: AXUIElement, _ attribute: String) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return (value as? NSNumber)?.boolValue
    }
    static func enabled(_ element: AXUIElement) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXEnabledAttribute as CFString, &value) == .success else { return false }
        return (value as? NSNumber)?.boolValue ?? false
    }
    static func actions(_ element: AXUIElement) -> [String] {
        var value: CFArray?
        guard AXUIElementCopyActionNames(element, &value) == .success else { return [] }
        return value as? [String] ?? []
    }
    static func press(_ element: AXUIElement) -> Bool {
        guard enabled(element), actions(element).contains(kAXPressAction) else { return false }
        return AXUIElementPerformAction(element, kAXPressAction as CFString) == .success
    }
    static func setValue(_ value: String, on element: AXUIElement) -> Bool {
        var settable: DarwinBoolean = false
        guard enabled(element), AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable) == .success,
              settable.boolValue else { return false }
        return AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, value as CFString) == .success
    }
    static func rect(_ element: AXUIElement) -> CGRect? {
        var position: CFTypeRef?
        var size: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &position) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &size) == .success,
              let position, let size, CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        var dimensions = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &point),
              AXValueGetValue(size as! AXValue, .cgSize, &dimensions), dimensions.width > 0, dimensions.height > 0 else { return nil }
        return CGRect(origin: point, size: dimensions)
    }
    static func onScreenWindowRects(pid: pid_t) -> [CGRect] {
        guard let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] else { return [] }
        return windows.compactMap { window in
            guard (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid,
                  let bounds = window[kCGWindowBounds as String] as? [String: Any] else { return nil }
            return CGRect(dictionaryRepresentation: bounds as CFDictionary)
        }
    }
    static func isOnScreen(_ element: AXUIElement, windowRects: [CGRect]) -> Bool {
        guard let rect = rect(element) else { return false }
        return windowRects.contains { !$0.intersection(rect).isEmpty }
    }
    static func snapshot(_ root: AXUIElement, maxDepth: Int = 8, maxNodes: Int = 220, budget: TimeInterval = 0.25) -> [Node] {
        let deadline = Date().addingTimeInterval(max(0, budget))
        var result: [Node] = []
        var pending: [(AXUIElement, Int?, Int)] = [(root, nil, 0)]
        var seen = Set<CFHashCode>()
        while let (element, parent, depth) = pending.popLast(), result.count < maxNodes, Date() < deadline {
            guard seen.insert(CFHash(element)).inserted else { continue }
            AXUIElementSetMessagingTimeout(element, 0.05)
            let role = role(element)
            guard !role.isEmpty, Date() < deadline else { continue }
            func read(_ attribute: String) -> String {
                Date() < deadline ? (string(element, attribute) ?? "") : ""
            }
            let identifier = read(kAXIdentifierAttribute)
            let title = read(kAXTitleAttribute)
            let description = read(kAXDescriptionAttribute)
            let value = read(kAXValueAttribute)
            let labels = [title, description, value].filter { !$0.isEmpty }
            let index = result.count
            result.append(Node(element: element, parentIndex: parent, role: role, identifier: identifier,
                               title: title, description: description, value: value, labels: labels,
                               isEnabled: Date() < deadline && enabled(element),
                               actionNames: Date() < deadline ? actions(element) : []))
            guard depth < maxDepth, Date() < deadline else { continue }
            for child in children(element).prefix(maxNodes - result.count).reversed() {
                pending.append((child, index, depth + 1))
            }
        }
        return result
    }
}
