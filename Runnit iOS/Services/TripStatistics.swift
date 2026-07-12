//
//  TripStatistics.swift
//  Runnit iOS
//
//  Pure computations over a set of trips, driving the Passport screen. All
//  figures come from data already stored on each Trip (no geocoding here).
//

import Foundation

struct CountryVisit: Identifiable, Hashable {
    var id: String { isoCode }
    let isoCode: String
    let name: String
    let flag: String
    let tripCount: Int
}

struct ModeBreakdown: Identifiable, Hashable {
    var id: String { type.rawValue }
    let type: TripType
    let count: Int
}

struct TripStatistics {
    let trips: [Trip]

    /// Only completed trips count toward the Passport.
    var pastTrips: [Trip] { trips.filter(\.isPast) }

    var totalTrips: Int { pastTrips.count }

    var totalDistanceMeters: Double {
        pastTrips.reduce(0) { $0 + $1.distanceMeters }
    }

    var uniqueCountries: [CountryVisit] {
        var counts: [String: (name: String, flag: String, count: Int)] = [:]
        for trip in pastTrips {
            for place in [trip.origin, trip.destination] {
                guard let code = place.isoCountryCode, !code.isEmpty else { continue }
                let existing = counts[code]
                counts[code] = (
                    name: place.country ?? existing?.name ?? code,
                    flag: place.flag ?? existing?.flag ?? "🏳️",
                    count: (existing?.count ?? 0) + 1
                )
            }
        }
        return counts
            .map { CountryVisit(isoCode: $0.key, name: $0.value.name, flag: $0.value.flag, tripCount: $0.value.count) }
            .sorted { $0.tripCount > $1.tripCount || ($0.tripCount == $1.tripCount && $0.name < $1.name) }
    }

    var uniqueCities: Int {
        var cities = Set<String>()
        for trip in pastTrips {
            for place in [trip.origin, trip.destination] {
                if let locality = place.locality, !locality.isEmpty {
                    cities.insert(locality)
                }
            }
        }
        return cities.count
    }

    var modeBreakdown: [ModeBreakdown] {
        TripType.allCases.compactMap { type in
            let count = pastTrips.filter { $0.type == type }.count
            return count > 0 ? ModeBreakdown(type: type, count: count) : nil
        }
    }

    var longestTrip: Trip? {
        pastTrips.max { $0.distanceMeters < $1.distanceMeters }
    }

    var firstTrip: Trip? {
        pastTrips.min { $0.departureDate < $1.departureDate }
    }

    var mostRecentTrip: Trip? {
        pastTrips.max { $0.departureDate < $1.departureDate }
    }

    var tripsThisYear: Int {
        let year = Calendar.current.component(.year, from: Date())
        return pastTrips.filter {
            Calendar.current.component(.year, from: $0.departureDate) == year
        }.count
    }
}
