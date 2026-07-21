//
//  ErailClient.swift
//  Runnit iOS
//
//  A thin URLSession wrapper over erail.in's public train endpoint, used to
//  auto-fill Indian Railways legs from a train number. erail is free and needs
//  no key, so this is the train-side analogue of `FR24Client` — except it speaks
//  a legacy tilde/caret-delimited text format rather than JSON.
//
//  Only the by-number schedule is used here (getTrains.aspx?TrainNo=…). It
//  carries the train's own origin and destination stations, their codes, the
//  origin departure and destination arrival (both in IST wall-clock), the
//  journey duration, and a 7-character running-days mask. erail publishes a real
//  weekly timetable, so — unlike FR24 flights — a *future* date fills correctly.
//
//  The delimited parser is a pure static function so it can be unit-tested with
//  captured payloads, no network involved.
//

import Foundation
import CoreLocation

// MARK: - Result

/// The facts a train-number lookup yields. Times are the raw "HH.MM" wall-clock
/// strings erail prints (Indian Standard Time); the caller stamps them onto a
/// chosen travel date.
nonisolated struct TrainScheduleResult: Equatable, Sendable {
    var trainNumber: String
    /// erail's *internal* train id (not the public number). It's what the route
    /// endpoint keys on — passing the public number there returns an unrelated
    /// train — so it's captured here to drive `trainRoute(trainID:)`. Nil when
    /// the payload didn't carry it.
    var trainID: String?
    var trainName: String
    var sourceName: String
    var sourceCode: String
    var destinationName: String
    var destinationCode: String
    /// Origin departure, "HH.MM" in IST.
    var departureTime: String
    /// Destination arrival, "HH.MM" in IST.
    var arrivalTime: String
    /// Journey time, "HH.MM" (hours.minutes) — the authoritative span, since a
    /// long-distance train can run well over 24 hours.
    var duration: String
    /// 7-character mask, Sunday-first (index = Swift weekday − 1); '1' = runs.
    var runningDays: String

    /// The journey length as a duration, parsed from the "HH.MM" `duration`
    /// string. Nil if erail printed something unparseable.
    var durationInterval: TimeInterval? {
        let parts = duration.split(separator: ".")
        guard let h = Int(parts.first ?? "") else { return nil }
        let m = parts.count > 1 ? (Int(parts[1]) ?? 0) : 0
        return TimeInterval(h * 3600 + m * 60)
    }

    /// Whether this train runs on `date`, judged on the calendar day in India
    /// (the running-days mask is about the origin's local day). Returns `true`
    /// when the mask is malformed, so a parsing quirk never hides a real train.
    func runs(on date: Date) -> Bool {
        guard runningDays.count == 7 else { return true }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TrainAutofill.indiaTimeZone
        let weekday = cal.component(.weekday, from: date) // 1 = Sunday … 7 = Saturday
        let index = runningDays.index(runningDays.startIndex, offsetBy: weekday - 1)
        return runningDays[index] == "1"
    }
}

/// One halt on a train's published route, in travel order. erail prints the
/// station's coordinates inline, so a route needs no extra geocoding — not even
/// the bundled `StationDatabase`.
nonisolated struct TrainRouteStation: Equatable, Sendable {
    var code: String
    var name: String
    var latitude: Double
    var longitude: Double
    /// Kilometres from the train's origin, as erail prints it.
    var distanceKm: Int

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

// MARK: - Client

/// `nonisolated` like `FR24Client`: a stateless HTTP client has no reason to pin
/// itself to the main actor.
nonisolated struct ErailClient {
    private static let base = "https://erail.in/rail/getTrains.aspx"
    private static let routeBase = "https://erail.in/data.aspx"

    private let session: URLSession
    init(session: URLSession = .shared) { self.session = session }

    /// Every halt on a train's published route, origin-first, each with the
    /// station's own coordinates. `trainID` is erail's internal id (from
    /// `TrainScheduleResult.trainID`), *not* the public train number — the route
    /// endpoint keys on the internal id and returns an unrelated train for the
    /// public number. Returns `nil` when erail doesn't recognise the id or
    /// prints something unparseable; throws only on a transport failure the
    /// caller may retry.
    func trainRoute(trainID: String) async throws -> [TrainRouteStation]? {
        var comps = URLComponents(string: Self.routeBase)
        comps?.queryItems = [
            URLQueryItem(name: "Action", value: "TRAINROUTE"),
            URLQueryItem(name: "Password", value: "2012"),
            URLQueryItem(name: "Data1", value: trainID),
            URLQueryItem(name: "Data2", value: "0"),
            URLQueryItem(name: "Cache", value: "true"),
        ]
        guard let url = comps?.url else { return nil }

        let (data, _) = try await session.data(from: url)
        return Self.parseRoute(String(decoding: data, as: UTF8.self))
    }

    /// Look up a train's schedule by number. Returns `nil` when erail doesn't
    /// recognise the number (its "Train not found" answer) or the payload can't
    /// be parsed; throws only on a transport failure the caller may retry.
    func trainDetails(trainNumber: String) async throws -> TrainScheduleResult? {
        var comps = URLComponents(string: Self.base)
        comps?.queryItems = [
            URLQueryItem(name: "TrainNo", value: trainNumber),
            URLQueryItem(name: "DataSource", value: "0"),
            URLQueryItem(name: "Language", value: "0"),
            URLQueryItem(name: "Cache", value: "true"),
        ]
        guard let url = comps?.url else { return nil }

        let (data, _) = try await session.data(from: url)
        let text = String(decoding: data, as: UTF8.self)
        return Self.parse(text)
    }

    /// Parse erail's tilde/caret-delimited schedule payload. Exposed for tests.
    ///
    /// Shape: `…header…^<num>~<name>~<srcName>~<srcCode>~<dstName>~<dstCode>~…`
    /// where the fields after the single `^` are what we want. A "Train not
    /// found" answer carries no `^`, so the split below rejects it.
    static func parse(_ raw: String) -> TrainScheduleResult? {
        let parts = raw.components(separatedBy: "^")
        guard parts.count >= 2 else { return nil }
        let body = parts.dropFirst().joined(separator: "^")
        let f = body.components(separatedBy: "~")
        // Need through the running-days field (index 13); guard the number too so
        // a stray non-schedule body can't slip through.
        guard f.count > 13, !f[0].isEmpty, Int(f[0]) != nil else { return nil }

        // erail's internal train id trails the schedule columns (index 33). It's
        // what the route endpoint keys on; absent on a short/odd payload, in
        // which case the route just falls back to a straight line.
        let trainID = f.count > 33 ? f[33].trimmingCharacters(in: .whitespaces) : ""

        return TrainScheduleResult(
            trainNumber: f[0],
            trainID: trainID.isEmpty ? nil : trainID,
            trainName: f[1].trimmingCharacters(in: .whitespaces),
            sourceName: f[2].trimmingCharacters(in: .whitespaces),
            sourceCode: f[3],
            destinationName: f[4].trimmingCharacters(in: .whitespaces),
            destinationCode: f[5],
            departureTime: f[10],
            arrivalTime: f[11],
            duration: f[12],
            runningDays: f[13]
        )
    }

    /// Parse erail's tilde/caret-delimited route payload. Exposed for tests.
    ///
    /// One `^`-separated record per halt, each a `~`-separated row:
    /// `<seq>~<code>~<name>~<arr>~<dep>~<halt>~<km>~<day>~…~<lat>~<lng>~…`.
    /// Rows without usable coordinates are dropped rather than failing the whole
    /// route — a single unmapped halt shouldn't cost the map its line.
    static func parseRoute(_ raw: String) -> [TrainRouteStation]? {
        let stations = raw.components(separatedBy: "^").compactMap { record -> TrainRouteStation? in
            let f = record.components(separatedBy: "~")
            guard f.count > 15,
                  let latitude = Double(f[14]), let longitude = Double(f[15]),
                  // (0, 0) is erail's stand-in for "we don't have this station".
                  latitude != 0 || longitude != 0
            else { return nil }

            return TrainRouteStation(
                code: f[1].trimmingCharacters(in: .whitespaces).uppercased(),
                name: f[2].trimmingCharacters(in: .whitespaces),
                latitude: latitude,
                longitude: longitude,
                distanceKm: Int(f[6]) ?? 0
            )
        }
        return stations.count >= 2 ? stations : nil
    }
}
