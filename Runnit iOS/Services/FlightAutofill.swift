//
//  FlightAutofill.swift
//  Runnit iOS
//
//  Turns a flight number + travel date into fully-resolved trip details:
//  airline, both airports (as map-ready Places), and departure/arrival stamped
//  onto the chosen date in each airport's local timezone. One aviation-API call
//  (via FlightTracker.lookup) plus free Apple local-search for coordinates.
//

import Foundation

@MainActor
enum FlightAutofill {
    struct Filled {
        var origin: Place?
        var destination: Place?
        var airline: String
        var flightNumber: String
        var departure: Date?
        var arrival: Date?

        var routeSummary: String {
            "\(origin?.displayName ?? "—") → \(destination?.displayName ?? "—")"
        }
    }

    enum Outcome: Equatable {
        case filled(Filled)
        case notFound
        case invalidNumber
        case noKey
        case quotaExceeded
        case failed

        static func == (l: Outcome, r: Outcome) -> Bool {
            switch (l, r) {
            case (.notFound, .notFound), (.invalidNumber, .invalidNumber),
                 (.noKey, .noKey), (.quotaExceeded, .quotaExceeded), (.failed, .failed),
                 (.filled, .filled):
                return true
            default: return false
            }
        }

        /// A user-facing message for the non-success cases.
        var message: String? {
            switch self {
            case .filled:        return nil
            case .invalidNumber: return "Enter a flight number like \u{201C}AA 100\u{201D}."
            case .notFound:      return "Couldn't find that flight operating today. On the free plan only same-day flights are searchable — enter the details manually."
            case .noKey:         return "Add your AviationStack API key (Account tab) to look flights up automatically."
            case .quotaExceeded: return "Monthly API limit reached — enter the flight details manually."
            case .failed:        return "Lookup failed. Check your connection or enter the details manually."
            }
        }
    }

    static func run(flightNumber: String, date: Date, tracker: FlightTracker) async -> Outcome {
        switch await tracker.lookup(flightNumber: flightNumber) {
        case .invalidNumber: return .invalidNumber
        case .noKey:         return .noKey
        case .quotaExceeded: return .quotaExceeded
        case .failed:        return .failed
        case .notFound:      return .notFound
        case .success(let r):
            let search = LocationSearchService()
            let origin = await search.resolveAirport(name: r.departureAirportName, iata: r.departureIata)
            let destination = await search.resolveAirport(name: r.arrivalAirportName, iata: r.arrivalIata)

            let departure = stamp(r.departureScheduled, onto: date, timeZone: r.departureTimeZone)
            var arrival = stamp(r.arrivalScheduled, onto: date, timeZone: r.arrivalTimeZone)
            // Overnight flights arrive the next calendar day.
            if let d = departure, let a = arrival, a < d {
                arrival = a.addingTimeInterval(24 * 3600)
            }

            return .filled(Filled(
                origin: origin,
                destination: destination,
                airline: r.airlineName ?? "",
                flightNumber: r.flightIata ?? "",
                departure: departure,
                arrival: arrival
            ))
        }
    }

    /// Combine the wall-clock time-of-day of `scheduled` (read in the airport's
    /// timezone) with the calendar day of `day`, producing a correct instant.
    private static func stamp(_ scheduled: Date?, onto day: Date, timeZone: String?) -> Date? {
        guard let scheduled else { return nil }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone.flatMap(TimeZone.init(identifier:)) ?? .current

        let time = cal.dateComponents([.hour, .minute], from: scheduled)
        let dayComps = Calendar.current.dateComponents([.year, .month, .day], from: day)
        var merged = DateComponents()
        merged.year = dayComps.year
        merged.month = dayComps.month
        merged.day = dayComps.day
        merged.hour = time.hour
        merged.minute = time.minute
        return cal.date(from: merged) ?? scheduled
    }
}
