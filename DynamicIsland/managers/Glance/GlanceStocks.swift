// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620

import Foundation

/// Prices for Stocks panels, from Yahoo Finance's public chart data (no
/// account), fetched while a board with stocks is on screen: when it opens
/// and every minute after.
@MainActor
final class GlanceStocks: ObservableObject {
    static let shared = GlanceStocks()

    @Published private(set) var quotes: [String: GlancePolicy.StockQuote] = [:]
    /// Symbols Yahoo didn't know or that couldn't be fetched.
    @Published private(set) var failed: Set<String> = []

    private var symbols: [String] = []
    private var lastFetch: [String: Date] = [:]
    private var timer: Timer?

    func startRefreshing(_ boards: [GlanceBoard]) {
        var seen = Set<String>()
        symbols = boards.flatMap(\.panels).filter { $0.isShown && $0.kind == .stocks }
            .flatMap(\.symbols).filter { seen.insert($0).inserted }
        guard !symbols.isEmpty else {
            stopRefreshing()
            return
        }
        refresh()
        if timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
                Task { @MainActor in GlanceStocks.shared.refresh() }
            }
        }
    }

    func stopRefreshing() {
        timer?.invalidate()
        timer = nil
    }

    /// Fetches what's more than a minute old (opening the board twice in a row asks once).
    func refresh() {
        for symbol in symbols where Date().timeIntervalSince(lastFetch[symbol] ?? .distantPast) > 50 {
            lastFetch[symbol] = Date()
            Task { await fetch(symbol) }
        }
    }

    private func fetch(_ symbol: String) async {
        guard let url = GlancePolicy.stockURL(symbol) else {
            failed.insert(symbol)
            return
        }
        var request = URLRequest(url: url, timeoutInterval: 8)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")
        let data = try? await URLSession.shared.data(for: request).0
        if let data, let quote = GlancePolicy.quote(from: data) {
            quotes[symbol] = quote
            failed.remove(symbol)
        } else if quotes[symbol] == nil {
            failed.insert(symbol)
        }
    }
}
