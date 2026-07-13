//
//  AviationStackClient.swift
//  Runnit iOS
//
//  A thin URLSession wrapper over AviationStack's real-time `/flights` endpoint.
//  The free tier is HTTP-only (an App Transport Security exception for
//  api.aviationstack.com is declared in Info.plist) and capped at 100 calls/month,
//  so this client is only ever invoked through `FlightTracker`, which enforces
//  caching and quota rules. This type just performs one request and decodes it.
//

import Foundation

// MARK: - Errors

enum AviationStackError: Error, Equatable {
    case noKey
    case quotaExceeded
    case notFound
    case http(Int)
    case transport
    case decoding
}

// MARK: - Response DTOs

/// Top-level `/flights` response. `error` is populated on API-level failures
/// (e.g. usage limit) even when the HTTP status is 200.
struct ASResponse: Decodable {
    let error: ASError?
    let data: [ASFlight]?
}

struct ASError: Decodable {
    let code: Int?
    let type: String?
    let message: String?
    let info: String?
}

struct ASFlight: Decodable {
    let flightDate: String?
    let flightStatus: String?
    let departure: ASEndpoint?
    let arrival: ASEndpoint?
    let airline: ASAirline?
    let flight: ASFlightInfo?
    let live: ASLive?

    enum CodingKeys: String, CodingKey {
        case flightDate = "flight_date"
        case flightStatus = "flight_status"
        case departure, arrival, airline, flight, live
    }
}

struct ASEndpoint: Decodable {
    let airport: String?
    let timezone: String?
    let iata: String?
    let terminal: String?
    let gate: String?
    let baggage: String?
    let delay: Int?
    let scheduled: String?
    let estimated: String?
    let actual: String?
}

struct ASAirline: Decodable {
    let name: String?
    let iata: String?
}

struct ASFlightInfo: Decodable {
    let number: String?
    let iata: String?
    let icao: String?
}

struct ASLive: Decodable {
    let updated: String?
    let latitude: Double?
    let longitude: Double?
    let altitude: Double?
    let direction: Double?
    let speedHorizontal: Double?
    let isGround: Bool?

    enum CodingKeys: String, CodingKey {
        case updated, latitude, longitude, altitude, direction
        case speedHorizontal = "speed_horizontal"
        case isGround = "is_ground"
    }
}

// MARK: - Client

struct AviationStackClient {
    /// Free tier is HTTP-only; HTTPS requires a paid plan.
    private static let base = "http://api.aviationstack.com/v1/flights"

    private let session: URLSession
    init(session: URLSession = .shared) { self.session = session }

    /// Fetch the best-matching flight for a code. Returns `nil` when the API
    /// responds successfully but has no matching flight. Throws for missing key,
    /// quota, transport, and decoding failures.
    ///
    /// - Parameters:
    ///   - flightIata: normalized code, e.g. "UA523".
    ///   - departureIata: optional departure airport to disambiguate codeshares.
    ///   - target: the leg's scheduled departure, used to pick the nearest match.
    func fetch(flightIata: String, departureIata: String?, target: Date?) async throws -> ASFlight? {
        guard let key = Secrets.aviationStackKey else { throw AviationStackError.noKey }

        var comps = URLComponents(string: Self.base)!
        var items = [
            URLQueryItem(name: "access_key", value: key),
            URLQueryItem(name: "flight_iata", value: flightIata),
            URLQueryItem(name: "limit", value: "100"),
        ]
        if let departureIata { items.append(URLQueryItem(name: "dep_iata", value: departureIata)) }
        comps.queryItems = items
        guard let url = comps.url else { throw AviationStackError.transport }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(from: url)
        } catch {
            throw AviationStackError.transport
        }

        if let http = response as? HTTPURLResponse {
            if http.statusCode == 429 { throw AviationStackError.quotaExceeded }
            guard (200...299).contains(http.statusCode) else {
                throw AviationStackError.http(http.statusCode)
            }
        }

        let decoded: ASResponse
        do {
            decoded = try JSONDecoder().decode(ASResponse.self, from: data)
        } catch {
            throw AviationStackError.decoding
        }

        if let apiError = decoded.error {
            if apiError.type == "usage_limit_reached" || apiError.code == 104 {
                throw AviationStackError.quotaExceeded
            }
            throw AviationStackError.http(apiError.code ?? -1)
        }

        let flights = decoded.data ?? []
        guard !flights.isEmpty else { return nil }
        return bestMatch(from: flights, departureIata: departureIata, target: target)
    }

    /// Prefer a flight whose departure airport matches, then the one whose
    /// scheduled departure is closest to the leg's own departure time. Results are
    /// first constrained to the target calendar day so we never present some other
    /// day's instance of the same flight number (the free tier serves "today").
    private func bestMatch(from flights: [ASFlight], departureIata: String?, target: Date?) -> ASFlight? {
        var pool = flights
        if let target {
            let sameDay = pool.filter { flightDate($0.flightDate, matches: target) }
            // If the API didn't stamp flight_date, fall back to the full pool.
            if !sameDay.isEmpty { pool = sameDay }
            else if pool.contains(where: { $0.flightDate != nil }) { return nil }
        }

        let byAirport: [ASFlight]
        if let departureIata {
            let matches = pool.filter { $0.departure?.iata?.uppercased() == departureIata.uppercased() }
            byAirport = matches.isEmpty ? pool : matches
        } else {
            byAirport = pool
        }

        guard let target else { return byAirport.first }
        return byAirport.min { a, b in
            let da = a.departure?.scheduled.flatMap(ASDate.parse).map { abs($0.timeIntervalSince(target)) } ?? .greatestFiniteMagnitude
            let db = b.departure?.scheduled.flatMap(ASDate.parse).map { abs($0.timeIntervalSince(target)) } ?? .greatestFiniteMagnitude
            return da < db
        } ?? byAirport.first
    }

    /// Compare an API `flight_date` ("yyyy-MM-dd") to a target calendar day.
    private func flightDate(_ raw: String?, matches target: Date) -> Bool {
        guard let raw else { return false }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: raw) else { return false }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.isDate(d, inSameDayAs: target)
    }
}

/// AviationStack timestamps are ISO-8601 with a timezone offset.
enum ASDate {
    private static let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    private static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static func parse(_ s: String?) -> Date? {
        guard let s, !s.isEmpty else { return nil }
        return formatter.date(from: s) ?? fractional.date(from: s)
    }
}
