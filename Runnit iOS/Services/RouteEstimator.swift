//
//  RouteEstimator.swift
//  Runnit iOS
//
//  Talks to Apple Maps (MKDirections) for road-trip legs: an estimated driving
//  time (to auto-fill arrival) and the actual road-following route geometry (so
//  the map draws the real roads rather than a straight line).
//

import MapKit

/// A single lat/long on a cached route. Kept as plain doubles (Codable) so a
/// segment's road-following polyline can be persisted with SwiftData, the same
/// way `Place` stores its coordinate.
nonisolated struct RoutePoint: Codable, Hashable {
    var latitude: Double
    var longitude: Double

    init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    init(_ coordinate: CLLocationCoordinate2D) {
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

enum RouteEstimator {
    /// Fastest driving time in seconds between two places, or nil if Apple Maps
    /// can't route it (e.g. across an ocean).
    static func drivingTime(from origin: Place, to destination: Place) async -> TimeInterval? {
        let request = MKDirections.Request()
        request.source = MKMapItem(location: origin.clLocation, address: nil)
        request.destination = MKMapItem(location: destination.clLocation, address: nil)
        request.transportType = .automobile

        do {
            let response = try await MKDirections(request: request).calculate()
            return response.routes.map(\.expectedTravelTime).min()
        } catch {
            return nil
        }
    }

    /// The road-following route through an ordered list of places (origin, each
    /// intermediate stop, destination). Requests driving directions for every
    /// consecutive pair and stitches the polylines into one continuous path.
    ///
    /// Returns nil if the leg has fewer than two places or any hop can't be
    /// routed — callers then fall back to a straight line, so a failure (or no
    /// network) never leaves a leg with no line at all.
    static func drivingRoute(through places: [Place]) async -> [RoutePoint]? {
        guard places.count >= 2 else { return nil }

        var points: [RoutePoint] = []
        for (start, end) in zip(places, places.dropFirst()) {
            let request = MKDirections.Request()
            request.source = MKMapItem(location: start.clLocation, address: nil)
            request.destination = MKMapItem(location: end.clLocation, address: nil)
            request.transportType = .automobile

            do {
                let response = try await MKDirections(request: request).calculate()
                guard let route = response.routes.min(by: { $0.expectedTravelTime < $1.expectedTravelTime })
                else { return nil }

                let hop = route.polyline.coordinates.map(RoutePoint.init)
                // Drop the first point of every hop after the first: it's the
                // shared waypoint the previous hop already ended on.
                points.append(contentsOf: points.isEmpty ? hop : Array(hop.dropFirst()))
            } catch {
                return nil
            }
        }
        return points.count >= 2 ? points : nil
    }
}

extension MKPolyline {
    /// The polyline's vertices as coordinates.
    var coordinates: [CLLocationCoordinate2D] {
        var coords = [CLLocationCoordinate2D](repeating: CLLocationCoordinate2D(),
                                              count: pointCount)
        getCoordinates(&coords, range: NSRange(location: 0, length: pointCount))
        return coords
    }
}
