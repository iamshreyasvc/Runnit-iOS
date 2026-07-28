//
//  AmtrakRouteProvider.swift
//  Runnit iOS
//
//  The real path an Amtrak leg takes, so the map draws the journey the train
//  actually makes rather than a straight line — the US-train counterpart to
//  `TrainRouteProvider` (Indian trains).
//
//  Everything is bundled (no network): the train's GTFS shape gives the surveyed
//  track geometry, and the leg is trimmed to the stretch between its own boarding
//  and alighting stations. When the shape is missing, it falls back to chaining
//  the train's stop coordinates — coarser, but still the corridor rather than a
//  straight cut across the map.
//

import Foundation
import CoreLocation

@MainActor
enum AmtrakRouteProvider {
    /// How far a leg's station may sit from a point on the route and still count
    /// as the same place. Generous enough to absorb the gap between a station's
    /// coordinate and the nearest shape vertex, tight enough that a station
    /// genuinely off this route fails to match.
    private static let stationMatchTolerance: CLLocationDistance = 30_000

    /// The path for an Amtrak leg: the train's route between the leg's own two
    /// stations. Returns nil when the number isn't an Amtrak one, the timetable
    /// doesn't know it, or the leg's stations don't lie on the route — callers
    /// then keep the straight-line fallback.
    static func route(
        for segment: TripSegment,
        schedule: AmtrakSchedule = .bundled,
        shapes: AmtrakShapes = .bundled
    ) -> [RoutePoint]? {
        guard let number = trainNumber(for: segment),
              let variant = schedule.anyVariant(forNumber: number)
        else { return nil }

        // Prefer the real shape geometry; fall back to the train's stop
        // coordinates when no shape is bundled for it.
        let full = shapes.coordinates(for: variant.shapeId)
            ?? variant.stops.compactMap { AmtrakStationDatabase.coordinate(code: $0.code) }

        return trim(full, from: segment.origin, to: segment.destination)
    }

    /// The Amtrak number for a train leg, or nil if this isn't one. Both stations
    /// must be in the Americas so a European train with a 1–4-digit number can't
    /// collide; the route lookup then further requires the number to be a real
    /// Amtrak one.
    static func trainNumber(for segment: TripSegment) -> String? {
        guard segment.type == .train,
              isAmerican(segment.origin), isAmerican(segment.destination),
              let raw = segment.vehicleNumber,
              let number = AmtrakSchedule.normalizedNumber(from: raw)
        else { return nil }
        return number
    }

    /// Whether a place sits in the US (or Canada, which Amtrak also serves). Falls
    /// back to an `America/` timezone when a place predates country-code
    /// resolution.
    private static func isAmerican(_ place: Place) -> Bool {
        let code = place.isoCountryCode?.uppercased()
        if code == "US" || code == "CA" { return true }
        return place.timeZoneIdentifier?.hasPrefix("America/") == true
    }

    /// Narrow the full route to the stretch this leg rides, by matching the leg's
    /// two places to the nearest point on the line. Pure, so it's unit-testable
    /// without the bundle.
    static func trim(_ points: [CLLocationCoordinate2D], from origin: Place, to destination: Place) -> [RoutePoint]? {
        guard points.count >= 2,
              let boarding = nearestIndex(in: points, to: origin, within: points.indices),
              let alighting = nearestIndex(in: points, to: destination, within: points.indices)
        else { return nil }

        // A leg is a contiguous run along the line; order the two matched points
        // so the slice is valid whichever way round they landed.
        let lo = min(boarding, alighting)
        let hi = max(boarding, alighting)
        let ridden = points[lo...hi].map { RoutePoint($0) }
        return ridden.count >= 2 ? ridden : nil
    }

    /// The point in `range` closest to `place`, or nil if the closest is still too
    /// far to be the same station.
    private static func nearestIndex(
        in points: [CLLocationCoordinate2D],
        to place: Place,
        within range: Range<Int>
    ) -> Int? {
        let target = place.clLocation
        let best = range
            .map { ($0, CLLocation(latitude: points[$0].latitude,
                                   longitude: points[$0].longitude).distance(from: target)) }
            .min { $0.1 < $1.1 }
        guard let best, best.1 <= stationMatchTolerance else { return nil }
        return best.0
    }
}
