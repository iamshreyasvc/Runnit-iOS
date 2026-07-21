//
//  TrainAutofill.swift
//  Runnit iOS
//
//  Turns an Indian Railways train number + travel date into fully-resolved trip
//  details: train name, both stations (as map-ready Places), and departure /
//  arrival stamped onto the chosen date in Indian Standard Time. Backed by
//  `ErailClient` for the timetable plus free Apple local-search for station
//  coordinates — the train-side counterpart to `FlightAutofill`.
//
//  Unlike flights (Flightradar24 has no forward schedules), erail publishes a
//  real weekly timetable, so a future date fills correctly. When the train
//  doesn't run on the chosen day, the leg is still filled but the outcome flags
//  it so the UI can say so.
//

import Foundation

@MainActor
enum TrainAutofill {
    /// Indian Railways runs entirely on one clock; every station is IST.
    /// `nonisolated` so the (nonisolated) schedule parser and `runs(on:)` can read
    /// it off the main actor.
    nonisolated static let indiaTimeZone = TimeZone(identifier: "Asia/Kolkata") ?? .current

    struct Filled {
        var origin: Place?
        var destination: Place?
        var trainName: String
        var trainNumber: String
        var departure: Date?
        var arrival: Date?
        /// Whether the train actually runs on the requested travel date.
        var runsOnDate: Bool

        var routeSummary: String {
            "\(origin?.displayName ?? "—") → \(destination?.displayName ?? "—")"
        }
    }

    enum Outcome: Equatable {
        case filled(Filled)
        case notFound
        case invalidNumber
        case failed

        static func == (l: Outcome, r: Outcome) -> Bool {
            switch (l, r) {
            case (.notFound, .notFound), (.invalidNumber, .invalidNumber),
                 (.failed, .failed), (.filled, .filled):
                return true
            default: return false
            }
        }

        /// A user-facing message for the non-success cases.
        var message: String? {
            switch self {
            case .filled:        return nil
            case .invalidNumber: return "Enter a 5-digit Indian Railways train number, like \u{201C}12608\u{201D}."
            case .notFound:      return "Couldn't find that train number on erail. Check the number, or enter the details manually."
            case .failed:        return "Lookup failed. Check your connection or enter the details manually."
            }
        }
    }

    /// Normalise a typed train number to erail's 5-digit form, or `nil` if it
    /// clearly isn't one.
    nonisolated static func normalizedNumber(from raw: String) -> String? {
        let digits = raw.filter(\.isNumber)
        return digits.count == 5 ? digits : nil
    }

    static func run(
        trainNumber: String,
        date: Date,
        client: ErailClient = ErailClient(),
        search: LocationSearchService? = nil
    ) async -> Outcome {
        guard let number = normalizedNumber(from: trainNumber) else { return .invalidNumber }

        let schedule: TrainScheduleResult?
        do {
            schedule = try await client.trainDetails(trainNumber: number)
        } catch {
            return .failed
        }
        guard let s = schedule else { return .notFound }

        // Prefer the bundled station database (an exact code → coordinate join —
        // instant and reliable for Indian stations). Only when a code isn't in
        // the dataset do we fall back to Apple's local search.
        let origin = await resolveStation(name: s.sourceName, code: s.sourceCode, search: search)
        let destination = await resolveStation(name: s.destinationName, code: s.destinationCode, search: search)

        let departure = stamp(s.departureTime, onto: date)
        // Prefer the published duration to place the arrival — a long-distance
        // train can run past midnight (or past a full day), and adding the
        // duration handles that correctly where a bare "HH.MM" arrival can't.
        let arrival: Date?
        if let departure, let interval = s.durationInterval {
            arrival = departure.addingTimeInterval(interval)
        } else {
            arrival = arrivalByRollover(s.arrivalTime, after: departure, onto: date)
        }

        return .filled(Filled(
            origin: origin,
            destination: destination,
            trainName: s.trainName,
            trainNumber: s.trainNumber,
            departure: departure,
            arrival: arrival,
            runsOnDate: s.runs(on: date)
        ))
    }

    /// Place a station on the map: try the bundled code → coordinate database
    /// first, then Apple's local search as a fallback for codes not in the set.
    private static func resolveStation(
        name: String,
        code: String,
        search: LocationSearchService?
    ) async -> Place? {
        if let place = StationDatabase.place(code: code, displayName: name) {
            return place
        }
        let search = search ?? LocationSearchService()
        return await search.resolveStation(name: name, code: code)
    }

    /// Combine the IST wall-clock time-of-day in `hhmm` ("HH.MM") with the
    /// calendar day of `day`, producing a correct instant.
    private static func stamp(_ hhmm: String, onto day: Date) -> Date? {
        let parts = hhmm.split(separator: ".")
        guard let hour = Int(parts.first ?? "") else { return nil }
        let minute = parts.count > 1 ? (Int(parts[1]) ?? 0) : 0

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = indiaTimeZone
        let dayComps = Calendar.current.dateComponents([.year, .month, .day], from: day)
        var merged = DateComponents()
        merged.year = dayComps.year
        merged.month = dayComps.month
        merged.day = dayComps.day
        merged.hour = hour
        merged.minute = minute
        return cal.date(from: merged)
    }

    /// Fallback when there's no usable duration: stamp the arrival time-of-day and
    /// roll to the next day if it lands before departure (an overnight train).
    private static func arrivalByRollover(_ hhmm: String, after departure: Date?, onto day: Date) -> Date? {
        guard var arrival = stamp(hhmm, onto: day) else { return nil }
        if let departure, arrival < departure {
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = indiaTimeZone
            arrival = cal.date(byAdding: .day, value: 1, to: arrival) ?? arrival.addingTimeInterval(24 * 3600)
        }
        return arrival
    }
}
