//
//  AviationStackClient.swift
//  Runnit iOS
//
//  RETAINED, BUT NOT USED. Live flight tracking moved to Flightradar24 (see
//  FR24Client / FlightTracker); nothing in the app calls anything in this file.
//  It is kept intact — client, DTOs, the `ASDate` timezone handling, and the
//  `FlightStatusRecord` mapping at the bottom — so the AviationStack integration
//  can be revived without rebuilding it from scratch.
//
//  A thin URLSession wrapper over AviationStack's real-time `/flights` endpoint.
//  Its free tier was HTTP-only and capped at 100 calls/month, which is why the
//  old code paths were built around a quota tracker. Reviving it needs an App
//  Transport Security exception for api.aviationstack.com in Info.plist again;
//  that exception was removed when we moved to FR24, which is HTTPS.
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
            let sameDay = pool.filter { Self.isSameFlightDay($0, as: target) }
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
            distance(of: a, from: target) < distance(of: b, from: target)
        } ?? byAirport.first
    }

    private func distance(of flight: ASFlight, from target: Date) -> TimeInterval {
        guard let scheduled = ASDate.parse(flight.departure?.scheduled,
                                           timeZone: flight.departure?.timezone)
        else { return .greatestFiniteMagnitude }
        return abs(scheduled.timeIntervalSince(target))
    }

    /// Is this the instance of the flight number the traveler means?
    ///
    /// "The same day" only means anything on the clock at the departure airport.
    /// DL 537 leaves Atlanta at 21:59 ET on Jul 14 — which is 01:59 **UTC on Jul
    /// 15**. Comparing calendar days in UTC would reject the very flight we asked
    /// for and cache it as "no data", and it would do that to every US evening
    /// departure. So the comparison happens in the departure airport's zone.
    static func isSameFlightDay(_ flight: ASFlight, as target: Date) -> Bool {
        let zoneID = flight.departure?.timezone
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zoneID.flatMap(TimeZone.init(identifier:)) ?? TimeZone(identifier: "UTC")!

        // Prefer the scheduled departure itself — it's the precise instant.
        if let scheduled = ASDate.parse(flight.departure?.scheduled, timeZone: zoneID) {
            return cal.isDate(scheduled, inSameDayAs: target)
        }
        // Otherwise fall back to `flight_date`, read on that same clock.
        guard let raw = flight.flightDate else { return false }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = cal.timeZone
        f.dateFormat = "yyyy-MM-dd"
        guard let day = f.date(from: raw) else { return false }
        return cal.isDate(day, inSameDayAs: target)
    }
}

/// AviationStack timestamps look like ISO-8601 with an offset, but the offset is
/// not to be trusted: the API emits the **airport's local wall clock** and staples
/// a `+00:00` onto it. A LAX departure at 1:15 PM arrives as
/// "2026-07-14T13:15:00+00:00" — read as UTC that's 6:15 AM Pacific, seven hours
/// wrong. The endpoint's `timezone` field ("America/Los_Angeles") is what makes
/// the timestamp meaningful, so every flight time must be parsed against it.
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
    /// Reads the wall-clock part only — the trailing offset is deliberately ignored.
    private static let wallClock: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return f
    }()

    /// Parse a timestamp that carries a genuine UTC offset (e.g. `live.updated`).
    static func parse(_ s: String?) -> Date? {
        guard let s, !s.isEmpty else { return nil }
        return formatter.date(from: s) ?? fractional.date(from: s)
    }

    /// Parse a flight time by interpreting its wall clock in the airport's own
    /// timezone. Falls back to trusting the offset when no timezone is supplied,
    /// which is the best we can do but is usually wrong — pass the timezone.
    static func parse(_ s: String?, timeZone identifier: String?) -> Date? {
        guard let s, !s.isEmpty else { return nil }
        guard let identifier, let zone = TimeZone(identifier: identifier) else {
            return parse(s)
        }
        wallClock.timeZone = zone
        // Trim any offset/fractional suffix; we want the first 19 characters.
        let clock = String(s.prefix(19))
        return wallClock.date(from: clock) ?? parse(s)
    }
}

// MARK: - Record mapping (unused)

extension FlightStatusRecord {
    /// The AviationStack half of `apply`, kept beside its client rather than in
    /// the model, so the live model file has no AviationStack surface. Nothing
    /// calls this; `apply(_:for:)` on the FR24 path replaced it.
    ///
    /// Note what AviationStack supplied that Flightradar24 cannot: published
    /// scheduled times, terminals, gates, baggage belts, airline-reported delay
    /// minutes, and cancellations.
    func apply(_ flight: ASFlight) {
        let phase = FlightPhase(apiStatus: flight.flightStatus)
        statusRaw = phase.rawValue
        flightIata = flight.flight?.iata
        airlineName = flight.airline?.name

        // Each endpoint's times are wall clocks at *that* airport — parse them
        // against its timezone, never the device's and never UTC.
        let depZone = flight.departure?.timezone
        let arrZone = flight.arrival?.timezone

        depTimeZoneID = depZone
        depScheduled = ASDate.parse(flight.departure?.scheduled, timeZone: depZone)
        depEstimated = ASDate.parse(flight.departure?.estimated, timeZone: depZone)
        depActual = ASDate.parse(flight.departure?.actual, timeZone: depZone)
        depTerminal = flight.departure?.terminal
        depGate = flight.departure?.gate
        depDelayMinutes = flight.departure?.delay

        arrTimeZoneID = arrZone
        arrScheduled = ASDate.parse(flight.arrival?.scheduled, timeZone: arrZone)
        arrEstimated = ASDate.parse(flight.arrival?.estimated, timeZone: arrZone)
        arrActual = ASDate.parse(flight.arrival?.actual, timeZone: arrZone)
        arrTerminal = flight.arrival?.terminal
        arrGate = flight.arrival?.gate
        arrBaggage = flight.arrival?.baggage
        arrDelayMinutes = flight.arrival?.delay

        // AviationStack reported metres and km/h here; the FR24 path stores feet
        // and knots, so reviving this means reconciling units with the card.
        liveLatitude = flight.live?.latitude
        liveLongitude = flight.live?.longitude
        liveAltitude = flight.live?.altitude
        liveDirection = flight.live?.direction
        liveSpeed = flight.live?.speedHorizontal
        liveIsGround = flight.live?.isGround
        liveUpdated = ASDate.parse(flight.live?.updated)

        fetchedAt = Date()
        didFindData = true
        isFinal = phase.isFinal
    }
}
