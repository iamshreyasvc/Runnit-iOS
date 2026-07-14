//
//  Secrets.swift
//  Runnit iOS
//
//  Reads local, uncommitted secrets from a bundled `Secrets.plist`. That file is
//  gitignored; a committed `Secrets.example.plist` template documents the format.
//  When a key is missing or left as the placeholder, the feature it powers is
//  simply disabled — the app still runs.
//

import Foundation

/// `nonisolated` so the (also nonisolated) FR24 client can read the token off the
/// main actor. Reading a bundled plist needs no isolation.
nonisolated enum Secrets {
    private static let placeholder = "PASTE_YOUR_KEY_HERE"

    /// The Flightradar24 API bearer token, or `nil` when unconfigured.
    /// This is the only credential live flight tracking uses.
    static var flightRadarToken: String? { value(forKey: "FlightRadarAPIToken") }

    /// Whether a usable Flightradar24 token is present.
    static var hasFlightRadarToken: Bool { flightRadarToken != nil }

    /// Retained so the AviationStack client still compiles, but nothing calls it:
    /// live tracking moved to Flightradar24. Kept for reference only.
    static var aviationStackKey: String? { value(forKey: "AviationStackAPIKey") }

    // MARK: Plist

    private static func value(forKey key: String) -> String? {
        guard
            let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
            let data = try? Data(contentsOf: url),
            let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
            let raw = dict[key] as? String
        else { return nil }

        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != placeholder else { return nil }
        return trimmed
    }
}
