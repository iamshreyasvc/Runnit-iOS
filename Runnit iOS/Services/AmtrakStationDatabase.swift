//
//  AmtrakStationDatabase.swift
//  Runnit iOS
//
//  An offline lookup from an Amtrak station code (e.g. "NYP", "CHI", "LAX") to
//  its coordinates and timezone — the US-train counterpart to the Indian
//  `StationDatabase`. Bundled as `AmtrakStations.json`, generated from Amtrak's
//  free GTFS feed (see Scripts/generate_amtrak_data.py).
//
//  Codes are GTFS `stop_id`s, matching what `AmtrakSchedule` carries, so the join
//  is exact — no fuzzy name matching. Unlike Indian stations (all one clock),
//  each US station keeps its own timezone, since a single train crosses several.
//

import Foundation
import CoreLocation

nonisolated struct AmtrakStationDatabase {
    struct Entry: Decodable {
        let name: String
        let lat: Double
        let lon: Double
        /// IANA id, e.g. "America/Chicago". Empty in the feed for a handful of
        /// stops; treated as unknown.
        let tz: String
    }

    /// Loaded once, lazily, and shared. Small (~56 KB) so it parses eagerly on
    /// first use; every subsequent lookup is a dictionary hit.
    private static let entries: [String: Entry] = {
        guard let url = Bundle.main.url(forResource: "AmtrakStations", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: Entry].self, from: data)
        else { return [:] }
        return decoded
    }()

    /// Resolve a station code into a map-ready `Place`, or `nil` when the code
    /// isn't in the dataset. Every Amtrak station is in the US or (a few) Canada;
    /// the country is left as "US" for the flag, which is correct for the vast
    /// majority and only cosmetic.
    static func place(code: String?) -> Place? {
        guard let entry = entry(for: code),
              let raw = normalize(code)
        else { return nil }
        return Place(
            name: "\(entry.name) (\(raw))",
            subtitle: entry.name,
            latitude: entry.lat,
            longitude: entry.lon,
            isoCountryCode: "US",
            country: "United States",
            locality: nil,
            timeZoneIdentifier: entry.tz.isEmpty ? nil : entry.tz
        )
    }

    /// The station's coordinate, for tracing a route through its stops.
    static func coordinate(code: String) -> CLLocationCoordinate2D? {
        guard let entry = entry(for: code) else { return nil }
        return CLLocationCoordinate2D(latitude: entry.lat, longitude: entry.lon)
    }

    /// The station's timezone, for stamping a stop's local arrival/departure.
    static func timeZone(code: String) -> TimeZone? {
        guard let tz = entry(for: code)?.tz, !tz.isEmpty else { return nil }
        return TimeZone(identifier: tz)
    }

    static func entry(for code: String?) -> Entry? {
        guard let raw = normalize(code) else { return nil }
        return entries[raw]
    }

    private static func normalize(_ code: String?) -> String? {
        guard let raw = code?.trimmingCharacters(in: .whitespaces).uppercased(),
              !raw.isEmpty
        else { return nil }
        return raw
    }
}
