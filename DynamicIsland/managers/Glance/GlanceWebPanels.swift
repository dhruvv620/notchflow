// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620

import AppKit
import Defaults
import PDFKit
import WebKit

/// The web pages on Glance boards, kept loaded so the board appears
/// instantly. They have their own sign-ins and cookies (a data store of
/// their own on this Mac, apart from Safari or Chrome), reload when the
/// board opens if older than their refresh time, and skip ads and cookie
/// banners when that's on.
@MainActor
final class GlanceWebPanels {
    static let shared = GlanceWebPanels()

    private struct Loaded {
        let view: WKWebView
        var address: String
        var mobile: Bool
        var loadedAt: Date?
    }

    private var pages: [UUID: Loaded] = [:]
    private var rules: WKContentRuleList?
    private var rulesRequested = false
    private var pdfs: [String: PDFDocument] = [:]
    /// The store web panels share (fixed id, so sign-ins last between launches).
    private lazy var dataStore = WKWebsiteDataStore(forIdentifier: UUID(uuidString: "6F1D2C1E-6A55-4C49-9E2B-4E7B1D2A9C01")!)

    private static let mobileUserAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

    /// Loads the board's pages that aren't loaded yet, without showing them.
    func preload(_ board: GlanceBoard) {
        prepare(board)
    }

    /// Before the board shows: every shown web panel has its page, due
    /// reloads happen, and pages of panels no longer on any board are dropped.
    func prepare(_ board: GlanceBoard) {
        compileRulesIfNeeded()
        let webPanels = board.panels.filter { $0.isShown && $0.kind == .web }
        for panel in webPanels { _ = view(for: panel) }
        let keep = Set(GlanceManager.shared.boards.flatMap(\.panels).filter { $0.kind == .web }.map(\.id))
        for id in pages.keys where !keep.contains(id) { pages[id] = nil }
    }

    /// The page for a panel: created on first use, reloaded when its
    /// address or layout changed or it's due.
    func view(for panel: GlancePanel) -> WKWebView {
        if var loaded = pages[panel.id] {
            if loaded.mobile != panel.mobileLayout {
                loaded.view.customUserAgent = panel.mobileLayout ? Self.mobileUserAgent : nil
                loaded.mobile = panel.mobileLayout
                loaded.loadedAt = nil
            }
            if loaded.address != panel.address {
                loaded.address = panel.address
                loaded.loadedAt = nil
            }
            if GlancePolicy.needsReload(loadedAt: loaded.loadedAt, refreshMinutes: panel.refreshMinutes, now: Date()) {
                load(loaded.view, panel.address)
                loaded.loadedAt = Date()
            }
            pages[panel.id] = loaded
            return loaded.view
        }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = dataStore
        if Defaults[.glanceHideAds], let rules { configuration.userContentController.add(rules) }
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.allowsBackForwardNavigationGestures = true
        view.setValue(false, forKey: "drawsBackground")
        if panel.mobileLayout { view.customUserAgent = Self.mobileUserAgent }
        load(view, panel.address)
        pages[panel.id] = Loaded(view: view, address: panel.address, mobile: panel.mobileLayout, loadedAt: Date())
        return view
    }

    func reload(_ id: UUID) {
        guard var loaded = pages[id] else { return }
        loaded.view.reload()
        loaded.loadedAt = Date()
        pages[id] = loaded
    }

    /// Frees the pages' memory; they load again the next time the board opens.
    func unloadAll() {
        pages = [:]
    }

    private func load(_ view: WKWebView, _ address: String) {
        guard let url = GlancePolicy.webURL(address) else {
            view.loadHTMLString("<body style=\"font:13px -apple-system;color:#999;padding:16px\">Add this panel's address in Settings › Glance.</body>", baseURL: nil)
            return
        }
        view.load(URLRequest(url: url))
    }

    private func compileRulesIfNeeded() {
        guard Defaults[.glanceHideAds], !rulesRequested else { return }
        rulesRequested = true
        WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "NotchFlowGlance",
                                                               encodedContentRuleList: GlancePolicy.contentRules()) { list, _ in
            Task { @MainActor in
                guard let list else { return }
                GlanceWebPanels.shared.rules = list
                // Pages already open get the rules from their next load.
                for loaded in GlanceWebPanels.shared.pages.values {
                    loaded.view.configuration.userContentController.add(list)
                }
            }
        }
    }

    // MARK: PDFs

    func pdf(at path: String) -> PDFDocument? {
        let expanded = (path as NSString).expandingTildeInPath
        if let document = pdfs[expanded] { return document }
        guard let document = PDFDocument(url: URL(fileURLWithPath: expanded)) else { return nil }
        pdfs[expanded] = document
        return document
    }
}
