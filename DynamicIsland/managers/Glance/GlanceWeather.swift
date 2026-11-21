// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620

import Foundation

/// Weather for Weather panels, from Open-Meteo (free, no account): the
/// city's place once, then the forecast when the board opens if it's more
/// than 15 minutes old.
@MainActor
final class GlanceWeather: ObservableObject {
    static let shared = GlanceWeather()

    @Published private(set) var reports: [String: GlancePolicy.WeatherReport] = [:]
    @Published private(set) var placeNames: [String: String] = [:]
    @Published private(set) var failed: Set<String> = []

    private var places: [String: GlancePolicy.WeatherPlace] = [:]
    private var fetchedAt: [String: Date] = [:]

    /// Fahrenheit where the Mac uses US units.
    private var fahrenheit: Bool { Locale.current.measurementSystem == .us }

    func refresh(_ boards: [GlanceBoard]) {
        let cities = Set(boards.flatMap(\.panels).filter { $0.isShown && $0.kind == .weather }.map { Self.key($0.address) })
        for city in cities where !city.isEmpty && Date().timeIntervalSince(fetchedAt[city] ?? .distantPast) > 15 * 60 {
            fetchedAt[city] = Date()
            Task { await fetch(city) }
        }
    }

    func report(for city: String) -> GlancePolicy.WeatherReport? { reports[Self.key(city)] }
    func placeName(for city: String) -> String? { placeNames[Self.key(city)] }
    func hasFailed(_ city: String) -> Bool { failed.contains(Self.key(city)) }

    static func key(_ city: String) -> String { city.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

    private func fetch(_ city: String) async {
        if places[city] == nil {
            guard let url = GlancePolicy.geocodeURL(city),
                  let data = try? await URLSession.shared.data(from: url).0,
                  let place = GlancePolicy.place(from: data) else {
                failed.insert(city)
                fetchedAt[city] = nil
                return
            }
            places[city] = place
            placeNames[city] = place.name
        }
        guard let place = places[city], let url = GlancePolicy.forecastURL(place, fahrenheit: fahrenheit),
              let data = try? await URLSession.shared.data(from: url).0,
              let report = GlancePolicy.weather(from: data) else {
            if reports[city] == nil { failed.insert(city) }
            fetchedAt[city] = nil
            return
        }
        reports[city] = report
        failed.remove(city)
    }
}
