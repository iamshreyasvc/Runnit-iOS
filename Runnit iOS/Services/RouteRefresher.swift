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

    /// While the flight is plausibly in the air, the track is re-fetched this
    /// often instead — that's what keeps the travelled line growing behind the
    /// live aircraft.
    private static let liveRetryInterval: TimeInterval = 10 * 60

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

            switch segment.type {
            case .roadTrip:
                guard let route = await RouteEstimator.drivingRoute(through: segment.routePlaces),
                      segment.geometrySignature == signature
                else { continue }
                segment.routePolyline = route
                segment.routeSignature = signature

            case .flight:
                guard let tracker, FlightTracker.isWithinTrackingReach(segment) else { continue }
                // Throttle so we don't re-spend a credit each appearance: hours
                // after an empty answer, minutes while the flight is in the air.
                let interval = FlightTracker.couldBeAirborneNow(segment)
                    ? liveRetryInterval : flightRetryInterval
                if let checkedAt = segment.routeCheckedAt,
                   Date().timeIntervalSince(checkedAt) < interval { continue }
                do {
                    let result = try await tracker.flightPath(for: segment)
                    // The API answered — stamp the throttle so an empty answer
                    // isn't re-billed on every map appearance.
                    segment.routeCheckedAt = Date()
                    guard let result, segment.geometrySignature == signature else { continue }
                    segment.routePolyline = result.points
                    // A track still being flown stays refreshable; the signature
                    // is stamped — freezing the route as final — only once the
                    // flight has actually ended. Without this, opening the map
                    // mid-flight would cache a truncated route forever.
                    if result.isComplete { segment.routeSignature = signature }
                } catch {
                    // Transient failure (offline, credits, server error): don't
                    // start the lockout; the next appearance retries.
                    continue
                }

            default:
                continue
            }
        }
        if context.hasChanges {
            try? context.save()
        }
    }
}
