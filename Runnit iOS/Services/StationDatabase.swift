//
//  StationDatabase.swift
//  Runnit iOS
//
//  An offline lookup from an Indian Railways station code (e.g. "SBC", "MAS") to
//  its coordinates. Bundled as `StationCoordinates.json` (~8.7k stations, from
//  the open datameet/railways dataset), it lets a train-number autofill place its
//  stations on the map instantly and reliably — without leaning on Apple's local
//  search, which has thin, unreliable POI coverage for Indian stations and so
//  failed to place them on nearly every lookup.
//
//  Codes are erail's authoritative station codes, matching what `ErailClient`
//  returns, so the join is exact — no fuzzy name matching involved.
//

import Foundation

nonisolated struct StationDatabase {
    struct Entry: Decodable {
        let lat: Double
        let lng: Double
        let name: String
    }

    /// Loaded once, lazily, and shared. The file is small enough (~0.5 MB) to
    /// parse eagerly on first use; every subsequent lookup is a dictionary hit.
    private static let entries: [String: Entry] = {
        guard let url = Bundle.main.url(forResource: "StationCoordinates", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: Entry].self, from: data)
        else { return [:] }
        return decoded
    }()

    /// Resolve a station code into a map-ready `Place`, or `nil` when the code
    /// isn't in the dataset. `displayName` (from erail) is preferred for the
    /// label so the pin reads the way the timetable named it; the code is
    /// appended in the app's `Name (CODE)` convention. Every Indian station runs
    /// on IST.
    static func place(code: String?, displayName: String?) -> Place? {
        guard let raw = code?.trimmingCharacters(in: .whitespaces).uppercased(),
              !raw.isEmpty,
              let entry = entries[raw]
        else { return nil }

        let cleanName = displayName?.trimmingCharacters(in: .whitespaces)
        let base = (cleanName?.isEmpty == false ? cleanName! : entry.name)
        return Place(
            name: "\(base) (\(raw))",
            subtitle: entry.name,
            latitude: entry.lat,
            longitude: entry.lng,
            isoCountryCode: "IN",
            country: "India",
            locality: nil,
            timeZoneIdentifier: "Asia/Kolkata"
        )
    }
}
