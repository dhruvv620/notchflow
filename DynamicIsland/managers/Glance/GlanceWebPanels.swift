// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620

import AppKit
import Defaults
import PDFKit
import WebKit

/// The web pages and HTML widgets on Glance boards, kept loaded so the
/// board appears instantly. They have their own sign-ins and cookies (a data
/// store of their own on this Mac, apart from Safari or Chrome), reload
/// when the board opens if older than their refresh time (an HTML widget
/// when its file changed), skip ads, trackers and cookie banners when
/// that's on, and hide the parts of a page you picked.
///
/// Pages are kept by "instance": the panel's id, or the panel's id and a
/// display when the same board is on several displays at once.
@MainActor
final class GlanceWebPanels {
    static let shared = GlanceWebPanels()

    private struct Loaded {
        let view: WKWebView
        let panelID: UUID
        var address: String
        var mobile: Bool
        var hidden: [String]
        var loadedAt: Date?
        var fileDate: Date?
    }

    private var pages: [String: Loaded] = [:]
    private var rules: WKContentRuleList?
    private var rulesRequested = false
    private var pdfs: [String: PDFDocument] = [:]
    /// The store web panels share (fixed id, so sign-ins last between launches).
    private lazy var dataStore = WKWebsiteDataStore(forIdentifier: UUID(uuidString: "6F1D2C1E-6A55-4C49-9E2B-4E7B1D2A9C01")!)

    private static let mobileUserAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

    /// Where agents (Claude Code, Codex…) put HTML widgets for Glance.
    static var agentWidgetsFolder: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("NotchFlow", isDirectory: true)
            .appendingPathComponent(GlancePolicy.agentWidgetsFolder, isDirectory: true)
    }

    /// The HTML widgets in that folder, newest first.
    static func agentWidgets() -> [URL] {
        let folder = agentWidgetsFolder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return files.filter { ["html", "htm"].contains($0.pathExtension.lowercased()) }
            .sorted { modified($0) ?? .distantPast > modified($1) ?? .distantPast }
    }

    private static func modified(_ url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    /// Before the boards show: due reloads happen, and pages of panels no
    /// longer on any board are dropped.
    func prepare(_ boards: [GlanceBoard]) {
        compileRulesIfNeeded()
        let keep = Set(GlanceManager.shared.boards.flatMap(\.panels).filter { $0.kind == .web || $0.kind == .html }.map(\.id))
        for (key, loaded) in pages where !keep.contains(loaded.panelID) { pages[key] = nil }
    }

    /// The page for a panel: created on first use, reloaded when its
    /// address, layout or hidden parts changed or it's due.
    func view(for panel: GlancePanel, instance: String) -> WKWebView {
        if var loaded = pages[instance] {
            var reload = false
            if loaded.mobile != panel.mobileLayout {
                loaded.view.customUserAgent = panel.mobileLayout ? Self.mobileUserAgent : nil
                loaded.mobile = panel.mobileLayout
                reload = true
            }
            if loaded.address != panel.address {
                loaded.address = panel.address
                reload = true
            }
            if loaded.hidden != panel.hiddenSelectors {
                loaded.hidden = panel.hiddenSelectors
                install(hidden: panel.hiddenSelectors, in: loaded.view)
                loaded.view.evaluateJavaScript(GlancePolicy.hideElementsScript(panel.hiddenSelectors), completionHandler: nil)
            }
            if panel.kind == .html {
                let date = Self.modified(URL(fileURLWithPath: (panel.address as NSString).expandingTildeInPath))
                if date != loaded.fileDate { loaded.fileDate = date; reload = true }
            } else if GlancePolicy.needsReload(loadedAt: loaded.loadedAt, refreshMinutes: panel.refreshMinutes, now: Date()) {
                reload = true
            }
            if reload {
                load(loaded.view, panel)
                loaded.loadedAt = Date()
            }
            pages[instance] = loaded
            return loaded.view
        }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = dataStore
        configuration.userContentController.add(GlanceScriptHandler(), name: "glanceHide")
        if Defaults[.glanceHideAds], let rules { configuration.userContentController.add(rules) }
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.allowsBackForwardNavigationGestures = true
        view.allowsMagnification = true
        view.setValue(false, forKey: "drawsBackground")
        if panel.mobileLayout { view.customUserAgent = Self.mobileUserAgent }
        install(hidden: panel.hiddenSelectors, in: view)
        load(view, panel)
        let fileDate = panel.kind == .html ? Self.modified(URL(fileURLWithPath: (panel.address as NSString).expandingTildeInPath)) : nil
        pages[instance] = Loaded(view: view, panelID: panel.id, address: panel.address, mobile: panel.mobileLayout,
                                 hidden: panel.hiddenSelectors, loadedAt: Date(), fileDate: fileDate)
        return view
    }

    // MARK: Controls

    func reload(_ instance: String) {
        guard var loaded = pages[instance] else { return }
        loaded.view.reload()
        loaded.loadedAt = Date()
        pages[instance] = loaded
    }

    func goBack(_ instance: String) { pages[instance]?.view.goBack() }
    func goForward(_ instance: String) { pages[instance]?.view.goForward() }

    /// The page's address now (after you clicked around in it).
    func currentURL(_ instance: String) -> URL? { pages[instance]?.view.url }

    /// Click the part of the page to hide (Esc cancels).
    func startPickingElement(_ instance: String) {
        pages[instance]?.view.evaluateJavaScript(GlancePolicy.pickElementScript, completionHandler: nil)
    }

    /// A part of a page was picked to hide (from the page's picker script).
    func hide(_ selector: String, from source: WKWebView?) {
        guard !selector.isEmpty, let loaded = pages.values.first(where: { $0.view === source }) else { return }
        GlanceManager.shared.updatePanel(loaded.panelID) { panel in
            if !panel.hiddenSelectors.contains(selector) { panel.hiddenSelectors.append(selector) }
        }
    }

    /// Frees the pages' memory; they load again the next time the board opens.
    func unloadAll() {
        pages = [:]
    }

    private func install(hidden: [String], in view: WKWebView) {
        let controller = view.configuration.userContentController
        controller.removeAllUserScripts()
        guard !hidden.isEmpty else { return }
        controller.addUserScript(WKUserScript(source: GlancePolicy.hideElementsScript(hidden), injectionTime: .atDocumentEnd,
                                              forMainFrameOnly: true))
    }

    private func load(_ view: WKWebView, _ panel: GlancePanel) {
        if panel.kind == .html {
            let file = URL(fileURLWithPath: (panel.address as NSString).expandingTildeInPath)
            guard FileManager.default.fileExists(atPath: file.path) else {
                view.loadHTMLString(Self.message("This widget's file isn't there any more."), baseURL: nil)
                return
            }
            view.loadFileURL(file, allowingReadAccessTo: file.deletingLastPathComponent())
            return
        }
        guard let url = GlancePolicy.webURL(panel.address) else {
            view.loadHTMLString(Self.message("Add this panel's address in Settings › Glance."), baseURL: nil)
            return
        }
        view.load(URLRequest(url: url))
    }

    private static func message(_ text: String) -> String {
        "<body style=\"font:13px -apple-system;color:#999;padding:16px\">\(text)</body>"
    }

    private func compileRulesIfNeeded() {
        guard Defaults[.glanceHideAds], !rulesRequested else { return }
        rulesRequested = true
        WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "NotchFlowGlance2",
                                                               encodedContentRuleList: GlancePolicy.contentRules()) { list, _ in
            Task { @MainActor in
                guard let list else { return }
                GlanceWebPanels.shared.rules = list
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

/// Receives the picked part of a page from the picker script.
@MainActor
private final class GlanceScriptHandler: NSObject, WKScriptMessageHandler {
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "glanceHide", let selector = message.body as? String else { return }
        GlanceWebPanels.shared.hide(selector, from: message.webView)
    }
}
