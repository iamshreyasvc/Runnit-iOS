//
//  RouteEstimator.swift
//  Runnit iOS
//
//  Computes an estimated driving time between two places using Apple Maps
//  (MKDirections). Used to auto-fill a road trip's arrival time.
//

import MapKit

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
}
