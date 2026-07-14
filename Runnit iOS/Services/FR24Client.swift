//
//  FR24Client.swift
//  Runnit iOS
//
//  A thin URLSession wrapper over the Flightradar24 API (fr24api.flightradar24.com).
//  HTTPS-only, bearer token, and an `Accept-Version` header on every request.
//
//  FR24 is an ADS-B *tracking* API, not a *schedules* API. Where AviationStack
//  answered everything in one call, FR24 splits it:
//
//    • live/flight-positions/full — telemetry + route, ONLY while airborne
//    • flight-summary/full        — actual takeoff/landing, live and historical
//    • static/airports/{code}/full — airport name + IANA timezone
//    • static/airlines/{icao}/light — airline name
//
//  And it simply does not carry gate, terminal, baggage, published schedules, or
//  cancellations. `FlightTracker` composes these endpoints into one snapshot and
//  is the only thing that talks to this type.
//

import Foundation

// MARK: - Errors

nonisolated enum FR24Error: Error, Equatable {
    case noToken
    case unauthorized
    case insufficientCredits
    case http(Int)
    case transport
    case decoding
}

// MARK: - Response DTOs

/// Every list endpoint wraps its rows in `{ "data": [...] }`.
private nonisolated struct FR24Envelope<T: Decodable>: Decodable {
    let data: [T]?
}

/// A row from `live/flight-positions/full`. Only exists while the aircraft is
/// actually being tracked in the air — there is no "upcoming flight" row.
nonisolated struct FR24Position: Decodable, Equatable, Sendable {
    let fr24ID: String?
    let flight: String?
    let callsign: String?
    let lat: Double?
    let lon: Double?
    /// True track over ground, degrees. Note: 0 can mean "unknown".
    let track: Double?
    /// Barometric altitude in **feet**.
    let alt: Double?
    /// Ground speed in **knots**.
    let gspeed: Double?
    /// Vertical rate in feet per minute.
    let vspeed: Double?
    let timestamp: String?
    let origIata: String?
    let destIata: String?
    /// ICAO code of the carrier per FR24's database.
    let paintedAs: String?
    /// ICAO code of the carrier derived from the callsign.
    let operatingAs: String?
    /// Estimated arrival, ISO-8601.
    let eta: String?

    enum CodingKeys: String, CodingKey {
        case fr24ID = "fr24_id"
        case flight, callsign, lat, lon, track, alt, gspeed, vspeed, timestamp, eta
        case origIata = "orig_iata"
        case destIata = "dest_iata"
        case paintedAs = "painted_as"
        case operatingAs = "operating_as"
    }
}

/// A row from `flight-summary/full` — one completed (or in-progress) flight leg.
nonisolated struct FR24Summary: Decodable, Equatable, Sendable {
    let fr24ID: String?
    let flight: String?
    let operatingAs: String?
    let paintedAs: String?
    let origIata: String?
    let destIata: String?
    /// Differs from `destIata` when the flight was diverted.
    let destIataActual: String?
    /// Actual wheels-up, UTC. Nil until the flight departs.
    let datetimeTakeoff: String?
    /// Actual touchdown, UTC. Nil until the flight lands.
    let datetimeLanded: String?
    let firstSeen: String?
    let lastSeen: String?
    /// False while the leg is still being tracked live.
    let flightEnded: Bool?

    enum CodingKeys: String, CodingKey {
        case fr24ID = "fr24_id"
        case flight
        case operatingAs = "operating_as"
        case paintedAs = "painted_as"
        case origIata = "orig_iata"
        case destIata = "dest_iata"
        case destIataActual = "dest_iata_actual"
        case datetimeTakeoff = "datetime_takeoff"
        case datetimeLanded = "datetime_landed"
        case firstSeen = "first_seen"
        case lastSeen = "last_seen"
        case flightEnded = "flight_ended"
    }
}

/// `static/airports/{code}/full`. The `timezone.name` is the whole reason we call
/// this: it's the only place FR24 tells us what clock an airport runs on.
nonisolated struct FR24Airport: Decodable, Equatable, Sendable {
    let name: String?
    let iata: String?
    let icao: String?
    let lat: Double?
    let lon: Double?
    let city: String?
    let timezone: FR24Timezone?
}

nonisolated struct FR24Timezone: Decodable, Equatable, Sendable {
    /// IANA identifier, e.g. "Europe/Stockholm".
    let name: String?
    let offset: Int?
}

/// `static/airlines/{icao}/light`.
nonisolated struct FR24Airline: Decodable, Equatable, Sendable {
    let name: String?
    let iata: String?
    let icao: String?
}

// MARK: - Client

/// `nonisolated` throughout: the project defaults types to `@MainActor`, and a
/// stateless HTTP client has no reason to pin its work to the main actor.
nonisolated struct FR24Client {
    private static let base = "https://fr24api.flightradar24.com/api"

    /// FR24's flight-summary history begins here; asking for anything earlier is
    /// guaranteed to come back empty.
    static let summaryFloor = Date(timeIntervalSince1970: 1_654_041_600) // 2022-06-01

    private let session: URLSession
    init(session: URLSession = .shared) { self.session = session }

    // MARK: Endpoints

    /// Live telemetry for a flight number. Empty unless the aircraft is airborne.
    func livePositions(flightIata: String) async throws -> [FR24Position] {
        let envelope: FR24Envelope<FR24Position> = try await get(
            "/live/flight-positions/full",
            query: [URLQueryItem(name: "flights", value: flightIata)]
        )
        return envelope.data ?? []
    }

    /// Flight legs for a number within a time window. `from`/`to` match against
    /// `first_seen` and may span at most 14 days.
    func summaries(flightIata: String, from: Date, to: Date) async throws -> [FR24Summary] {
        let envelope: FR24Envelope<FR24Summary> = try await get(
            "/flight-summary/full",
            query: [
                URLQueryItem(name: "flights", value: flightIata),
                URLQueryItem(name: "flight_datetime_from", value: FR24Date.query(from)),
                URLQueryItem(name: "flight_datetime_to", value: FR24Date.query(to)),
            ]
        )
        return envelope.data ?? []
    }

    /// Static airport reference data. `code` may be IATA (3) or ICAO (4).
    func airport(code: String) async throws -> FR24Airport {
        try await get("/static/airports/\(code.uppercased())/full", query: [])
    }

    /// Static airline reference data, keyed by ICAO code (e.g. "UAL").
    func airline(icao: String) async throws -> FR24Airline {
        try await get("/static/airlines/\(icao.uppercased())/light", query: [])
    }

    // MARK: Transport

    private func get<T: Decodable>(_ path: String, query: [URLQueryItem]) async throws -> T {
        guard let token = Secrets.flightRadarToken else { throw FR24Error.noToken }

        var comps = URLComponents(string: Self.base + path)
        if !query.isEmpty { comps?.queryItems = query }
        guard let url = comps?.url else { throw FR24Error.transport }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("v1", forHTTPHeaderField: "Accept-Version")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw FR24Error.transport
        }

        if let http = response as? HTTPURLResponse {
            switch http.statusCode {
            case 200...299: break
            case 401:       throw FR24Error.unauthorized
            case 402:       throw FR24Error.insufficientCredits
            default:        throw FR24Error.http(http.statusCode)
            }
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw FR24Error.decoding
        }
    }
}

// MARK: - Dates

/// FR24 timestamps are honest UTC — unlike AviationStack, which emitted an
/// airport's local wall clock stapled to a "+00:00". Two shapes appear:
/// `2023-11-08T10:10:00Z` (positions) and `2025-02-13T21:23:39` (summaries,
/// documented as UTC but with no zone suffix). Both parse to the same instant.
nonisolated enum FR24Date {
    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    /// For the zone-less summary timestamps, which the API documents as UTC.
    private static let naiveUTC: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return f
    }()

    static func parse(_ s: String?) -> Date? {
        guard let s, !s.isEmpty else { return nil }
        return iso.date(from: s)
            ?? isoFractional.date(from: s)
            ?? naiveUTC.date(from: String(s.prefix(19)))
    }

    /// Render for `flight_datetime_from` / `flight_datetime_to` (UTC, no offset).
    static func query(_ date: Date) -> String {
        naiveUTC.string(from: date)
    }
}
