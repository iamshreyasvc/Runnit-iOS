//
//  FR24StaticCache.swift
//  Runnit iOS
//
//  Airport and airline reference data from FR24's `static/*` endpoints, memoized
//  for the lifetime of the launch.
//
//  AviationStack returned the airline name and both airport timezones inline with
//  every flight. FR24 doesn't — it hands back ICAO/IATA codes and expects a
//  separate call per code. Without memoization a single refresh would spend three
//  extra credits re-fetching facts that haven't changed since the airport was
//  built, so every lookup goes through here.
//
//  Deliberately in-memory only: FR24's terms cap stored API data at 30 days, and
//  a cache that dies with the process can't outlive that.
//

import Foundation

@MainActor
final class FR24StaticCache {
    static let shared = FR24StaticCache()

    private let client: FR24Client
    /// Memoized answers. A stored `nil` value means "the API answered and doesn't
    /// know this code" — remembered so an unknown code isn't re-billed on every
    /// refresh. Transient failures (offline, credits, auth) are never cached.
    private var airports: [String: FR24Airport?] = [:]
    private var airlines: [String: String?] = [:]

    init(client: FR24Client = FR24Client()) {
        self.client = client
    }

    /// Airport reference data for an IATA (3-char) or ICAO (4-char) code.
    /// Returns `nil` rather than throwing: a missing timezone degrades to the
    /// `Place`'s own, which is a worse answer but never a broken screen.
    func airport(code: String?) async -> FR24Airport? {
        guard let code = code?.uppercased(), (3...4).contains(code.count) else { return nil }
        if let cached = airports[code] { return cached }
        do {
            let fetched = try await client.airport(code: code)
            airports.updateValue(fetched, forKey: code)
            return fetched
        } catch FR24Error.http, FR24Error.decoding {
            airports.updateValue(nil, forKey: code)   // definitively unknown
            return nil
        } catch {
            return nil                                // transient — retry later
        }
    }

    /// The airline's display name for an ICAO code such as "UAL". Falls back to
    /// `nil`, letting the caller use the operator name the user typed.
    func airlineName(icao: String?) async -> String? {
        guard let icao = icao?.uppercased(), !icao.isEmpty else { return nil }
        if let cached = airlines[icao] { return cached }
        do {
            let fetched = try await client.airline(icao: icao)
            let name = (fetched.name?.isEmpty == false) ? fetched.name : nil
            airlines.updateValue(name, forKey: icao)
            return name
        } catch FR24Error.http, FR24Error.decoding {
            airlines.updateValue(nil, forKey: icao)   // definitively unknown
            return nil
        } catch {
            return nil                                // transient — retry later
        }
    }
}
