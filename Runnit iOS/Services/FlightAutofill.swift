//
//  FlightAutofill.swift
//  Runnit iOS
//
//  Turns a flight number + travel date into fully-resolved trip details:
//  airline, both airports (as map-ready Places), and departure/arrival stamped
//  onto the chosen date in each airport's local timezone. Backed by
//  FlightTracker.lookup plus free Apple local-search for coordinates.
//
//  Caveat worth knowing: Flightradar24 publishes no forward schedules, so the
//  times here are lifted from the most recent completed operation of the same
//  flight number (see FlightTracker.lookup). For a daily service that lands
//  within a few minutes of the truth; it is not a published timetable.
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
        case insufficientCredits
        case failed

        static func == (l: Outcome, r: Outcome) -> Bool {
            switch (l, r) {
            case (.notFound, .notFound), (.invalidNumber, .invalidNumber),
                 (.noKey, .noKey), (.insufficientCredits, .insufficientCredits),
                 (.failed, .failed), (.filled, .filled):
                return true
            default: return false
            }
        }

        /// A user-facing message for the non-success cases.
        var message: String? {
            switch self {
            case .filled:        return nil
            case .invalidNumber: return "Enter a flight number like \u{201C}AA 100\u{201D}."
            case .notFound:      return "Couldn't find that flight number in the last week. Flightradar24 has no data on flights that haven't flown yet — enter the details manually."
            case .noKey:         return "Add your Flightradar24 API token (Account tab) to look flights up automatically."
            case .insufficientCredits: return "Flightradar24 credits exhausted — top up your plan, or enter the flight details manually."
            case .failed:        return "Lookup failed. Check your connection or enter the details manually."
            }
        }
    }

    static func run(flightNumber: String, date: Date, tracker: FlightTracker) async -> Outcome {
        switch await tracker.lookup(flightNumber: flightNumber) {
        case .invalidNumber:       return .invalidNumber
        case .noKey:               return .noKey
        case .insufficientCredits: return .insufficientCredits
        case .failed:              return .failed
        case .notFound:            return .notFound
        case .success(let r):
            let search = LocationSearchService()
            var origin = await search.resolveAirport(name: r.departureAirportName, iata: r.departureIata)
            var destination = await search.resolveAirport(name: r.arrivalAirportName, iata: r.arrivalIata)
            // The API is authoritative about each airport's clock — keep it, so the
            // leg can render local times even when there's no live status record.
            // Only overwrite when the API actually named a zone; never clear one the
            // airport lookup already resolved.
            if let zone = r.departureTimeZone { origin?.timeZoneIdentifier = zone }
            if let zone = r.arrivalTimeZone { destination?.timeZoneIdentifier = zone }

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
