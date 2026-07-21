//
//  TrainRouteProvider.swift
//  Runnit iOS
//
//  The real path an Indian Railways leg takes, so the map draws the journey the
//  train actually makes rather than a straight line between the two stations —
//  the train-side counterpart to `RouteEstimator` (road trips) and
//  `FlightTracker.flightPath` (flights).
//
//  There's no free rail-geometry service, but erail publishes every halt on a
//  train's route with coordinates attached. Chaining those halts approximates
//  the track closely: consecutive stops are tens of kilometres apart, so the
//  line follows the rail corridor — around the coast, through the ghats, via the
//  junction the train actually detours through — instead of cutting straight
//  across the country.
//
//  The published route covers the whole train; a passenger usually rides part of
//  it. So the route is trimmed to the stretch between the leg's own boarding and
//  alighting stations before it's drawn.
//

import Foundation
import CoreLocation

@MainActor
enum TrainRouteProvider {
    /// How far a leg's station may sit from a halt on the published route and
    /// still be considered the same station. Generous enough to absorb the
    /// difference between a station's erail coordinate and the one the app
    /// resolved for it, tight enough that a station genuinely not on this route
    /// fails to match.
    private static let stationMatchTolerance: CLLocationDistance = 30_000

    /// The path for a train leg: the published route between the leg's own two
    /// stations. Returns nil when the number isn't an Indian Railways one, erail
    /// doesn't know it, or the leg's stations don't lie on the route — callers
    /// then keep the straight-line fallback.
    static func route(for segment: TripSegment, client: ErailClient = ErailClient()) async -> [RoutePoint]? {
        guard let number = trainNumber(for: segment) else { return nil }

        // The route endpoint keys on erail's internal train id, not the public
        // number, so the schedule is fetched first purely to read that id off it.
        let stations: [TrainRouteStation]?
        do {
            guard let trainID = try await client.trainDetails(trainNumber: number)?.trainID
            else { return nil }
            stations = try await client.trainRoute(trainID: trainID)
        } catch {
            return nil
        }
        guard let stations else { return nil }
        return trim(stations, from: segment.origin, to: segment.destination)
    }

    /// The 5-digit Indian Railways number for a train leg, or nil if this isn't
    /// one. Both stations must be in India, so a European train that happens to
    /// carry a 5-digit number can't collide with an Indian number.
    static func trainNumber(for segment: TripSegment) -> String? {
        guard segment.type == .train,
              isIndian(segment.origin), isIndian(segment.destination),
              let raw = segment.vehicleNumber,
              let number = TrainAutofill.normalizedNumber(from: raw)
        else { return nil }
        return number
    }

    /// Whether a place sits in India. Falls back to the timezone when a place
    /// predates country-code resolution.
    private static func isIndian(_ place: Place) -> Bool {
        place.isoCountryCode?.uppercased() == "IN"
            || place.timeZoneIdentifier == "Asia/Kolkata"
    }

    /// Narrow the train's full published route to the stretch this leg rides, by
    /// matching the leg's two places to the nearest halt. Exposed (and pure) so
    /// it can be unit-tested without the network.
    static func trim(_ stations: [TrainRouteStation], from origin: Place, to destination: Place) -> [RoutePoint]? {
        guard stations.count >= 2,
              let boarding = nearestIndex(in: stations, to: origin, within: stations.indices)
        else { return nil }

        // The alighting halt has to come after the boarding one — the same
        // station can appear twice on a route that loops, and a leg always runs
        // forward along the train's direction of travel.
        guard let alighting = nearestIndex(in: stations,
                                           to: destination,
                                           within: (boarding + 1)..<stations.count)
        else { return nil }

        let ridden = stations[boarding...alighting].map { RoutePoint($0.coordinate) }
        return ridden.count >= 2 ? ridden : nil
    }

    /// The halt in `range` closest to `place`, or nil if the closest is still
    /// too far to be the same station.
    private static func nearestIndex(
        in stations: [TrainRouteStation],
        to place: Place,
        within range: Range<Int>
    ) -> Int? {
        let target = place.clLocation
        let best = range
            .map { ($0, CLLocation(latitude: stations[$0].latitude,
                                   longitude: stations[$0].longitude).distance(from: target)) }
            .min { $0.1 < $1.1 }
        guard let best, best.1 <= stationMatchTolerance else { return nil }
        return best.0
    }
}
