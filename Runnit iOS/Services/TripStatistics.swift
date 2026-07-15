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
            for place in trip.allPlaces {
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
            for place in trip.allPlaces {
                if let locality = place.locality, !locality.isEmpty {
                    cities.insert(locality)
                }
            }
        }
        return cities.count
    }

    /// Counts every leg's mode, so a multi-modal trip contributes to each mode
    /// it uses.
    var modeBreakdown: [ModeBreakdown] {
        TripType.allCases.compactMap { type in
            let count = pastTrips.reduce(0) { total, trip in
                total + trip.modeSequence.filter { $0 == type }.count
            }
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

    // MARK: Richer analytics (drive fun facts, coverage, and achievements)

    /// Distinct inhabited continents touched, ordered by how many visits each has.
    var continents: [Continent] {
        var counts: [Continent: Int] = [:]
        for trip in pastTrips {
            var seen = Set<Continent>()
            for place in trip.allPlaces {
                guard let code = place.isoCountryCode,
                      let continent = Continent.of(isoCode: code),
                      continent != .antarctica else { continue }
                seen.insert(continent)
            }
            for continent in seen { counts[continent, default: 0] += 1 }
        }
        return counts.keys.sorted { (counts[$0] ?? 0) > (counts[$1] ?? 0) }
    }

    /// Total number of individual legs across every completed trip.
    var totalLegs: Int { pastTrips.reduce(0) { $0 + $1.legCount } }

    /// How many of those legs were flights.
    var flightCount: Int {
        pastTrips.reduce(0) { $0 + $1.modeSequence.filter { $0 == .flight }.count }
    }

    /// Total time spent actually in transit, summed over legs that record both a
    /// departure and an arrival. Legs without an arrival contribute nothing.
    var totalTravelTime: TimeInterval {
        pastTrips.reduce(0) { total, trip in
            total + trip.displaySegments.reduce(0) { legTotal, seg in
                guard let arrival = seg.arrivalDate else { return legTotal }
                return legTotal + max(0, arrival.timeIntervalSince(seg.departureDate))
            }
        }
    }

    /// Average distance of a completed trip, or zero when there are none.
    var averageDistanceMeters: Double {
        totalTrips == 0 ? 0 : totalDistanceMeters / Double(totalTrips)
    }

    /// The most-visited country, if any trips carry country data.
    var favoriteCountry: CountryVisit? { uniqueCountries.first }

    /// The most-visited city and its visit count.
    var favoriteCity: (name: String, count: Int)? {
        var counts: [String: Int] = [:]
        for trip in pastTrips {
            var seen = Set<String>()
            for place in trip.allPlaces {
                if let locality = place.locality, !locality.isEmpty { seen.insert(locality) }
            }
            for city in seen { counts[city, default: 0] += 1 }
        }
        guard let best = counts.max(by: { $0.value < $1.value }) else { return nil }
        return (best.key, best.value)
    }

    /// The calendar month a traveler leaves most often, e.g. "July".
    var busiestMonth: (name: String, count: Int)? {
        var counts: [Int: Int] = [:]
        for trip in pastTrips {
            let month = Calendar.current.component(.month, from: trip.departureDate)
            counts[month, default: 0] += 1
        }
        guard let best = counts.max(by: { $0.value < $1.value }) else { return nil }
        let symbols = DateFormatter().monthSymbols ?? []
        let name = symbols.indices.contains(best.key - 1) ? symbols[best.key - 1] : ""
        return name.isEmpty ? nil : (name, best.value)
    }
}
