//
//  RouteRefresher.swift
//  Runnit iOS
//
//  Keeps a leg's cached "real route" up to date, so every map draws the true path
//  rather than a straight line. A map surface calls `refresh` when it appears; any
//  leg that has never been routed — or whose geometry has since changed — gets its
//  path fetched and persisted on the segment:
//
//    • road trips — Apple Maps driving directions (free), recomputed when a stop
//      is added, moved, or removed;
//    • flights — the actual flown track from Flightradar24, which works for
//      historical flights too, so Past Trips draw their real route.
//

import Foundation
import SwiftData

@MainActor
enum RouteRefresher {
    /// A flight track that came back empty is retried no more often than this, to
    /// protect FR24 API credits against a map that keeps reappearing.
    private static let flightRetryInterval: TimeInterval = 12 * 3600

    /// Fetch and persist real routes for any of `segments` that are stale. No-ops
    /// for legs already up to date, so it's cheap to call on every map appearance.
    /// Best-effort: a leg that can't be routed keeps its straight-line fallback and
    /// is retried later. `tracker` is required to fetch flight tracks; without it
    /// (or its FR24 token) only road trips are routed.
    static func refresh(_ segments: [TripSegment], in context: ModelContext, tracker: FlightTracker? = nil) async {
        for segment in segments where segment.needsRouteRefresh {
            // Capture the input before the await so we can tell whether the leg
            // changed again while the request was in flight.
            let signature = segment.geometrySignature

            let route: [RoutePoint]?
            switch segment.type {
            case .roadTrip:
                route = await RouteEstimator.drivingRoute(through: segment.routePlaces)

            case .flight:
                guard let tracker, FlightTracker.isWithinTrackingReach(segment) else { continue }
                // Throttle empty results so we don't re-spend a credit each appearance.
                if let checkedAt = segment.routeCheckedAt,
                   Date().timeIntervalSince(checkedAt) < flightRetryInterval { continue }
                segment.routeCheckedAt = Date()
                route = await tracker.flightPath(for: segment)

            default:
                continue
            }

            guard let route, segment.geometrySignature == signature else { continue }
            segment.routePolyline = route
            segment.routeSignature = signature
        }
        if context.hasChanges {
            try? context.save()
        }
    }
}
