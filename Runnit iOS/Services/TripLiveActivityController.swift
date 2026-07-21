//
//  TripLiveActivityController.swift
//  Runnit iOS
//
//  Keeps the Lock Screen in step with the "Happening Now" box. One Live Activity
//  per active trip, started when a trip becomes live and ended the moment it
//  stops being — which is exactly the window `TripStatus.init?` already defines,
//  so the card on the Lock Screen appears and disappears on the same rule as the
//  box in the Upcoming tab.
//
//  Cache-only, like the box: it reads whatever snapshots exist and never fetches.
//  The system owns the activity list, so that list is the state — nothing is
//  mirrored here, and a relaunch reconciles against what's actually on screen.
//

#if os(iOS)

import Foundation
import ActivityKit
import SwiftUI

@MainActor
enum TripLiveActivityController {

    /// How long a pushed state stays believable. Past this the system dims the
    /// card, which is the right signal: the app hasn't been able to refresh it.
    private static let staleAfter: TimeInterval = 45 * 60

    /// Reconcile the running activities against the trips that are live right
    /// now: start what's missing, update what's changed, end what's over.
    static func sync(trips: [Trip], records: [FlightStatusRecord], now: Date = Date()) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            await endAll()
            return
        }

        let live: [UUID: TripActivityAttributes.ContentState] = trips.reduce(into: [:]) { result, trip in
            guard let status = TripStatus(trip: trip, records: records, now: now) else { return }
            result[trip.id] = status.activityState(tripTitle: trip.displayTitle)
        }

        var running: Set<UUID> = []
        for activity in Activity<TripActivityAttributes>.activities {
            let id = activity.attributes.tripID
            running.insert(id)
            if let state = live[id] {
                await activity.update(content(state, now: now))
            } else {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }

        for (id, state) in live where !running.contains(id) {
            _ = try? Activity.request(
                attributes: TripActivityAttributes(tripID: id),
                content: content(state, now: now),
                pushType: nil
            )
        }
    }

    /// Tear every card down — used when the user has switched Live Activities
    /// off, so nothing of ours is left behind.
    static func endAll() async {
        for activity in Activity<TripActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    private static func content(
        _ state: TripActivityAttributes.ContentState, now: Date
    ) -> ActivityContent<TripActivityAttributes.ContentState> {
        // A card that's counting down to something is believable until it gets
        // there; one that isn't gets the ordinary window.
        let stale = state.countdownEnd ?? now.addingTimeInterval(staleAfter)
        return ActivityContent(state: state, staleDate: stale)
    }
}

// MARK: - TripStatus → live card

extension TripType {
    var activityAccent: TripActivityAccent {
        switch self {
        case .flight:   return .blue
        case .train:    return .orange
        case .roadTrip: return .green
        case .other:    return .purple
        }
    }
}

extension TripStatus {

    /// The same reading the active-trips row draws, flattened into the values the
    /// widget process can render on its own. Mirrors `tint`, `punctuality`,
    /// `countdown` and `endpoints` — change one and change this.
    func activityState(tripTitle: String) -> TripActivityAttributes.ContentState {
        let ends = endpoints
        let (prefix, suffix, fallback) = countdownPhrasing

        return TripActivityAttributes.ContentState(
            headline: headline,
            tripTitle: tripTitle,
            punctuality: punctuality.0,
            accent: activityAccent,
            icon: puckIcon,
            progress: progress,
            countdownStart: timeRemaining == nil ? nil : now,
            countdownEnd: timeRemaining.map { now.addingTimeInterval($0) },
            countdownPrefix: prefix,
            countdownSuffix: suffix,
            countdownFallback: fallback,
            startCode: ends.start.code,
            endCode: ends.end.code,
            endTitle: ends.end.title,
            endTime: ends.end.time.map { Format.time($0, in: ends.end.zone) },
            endIsLate: ends.end.isLate
        )
    }

    /// `tint`, resolved to a name the widget can decode.
    private var activityAccent: TripActivityAccent {
        if isCancelled { return .red }
        if (delayMinutes ?? 0) > 0 { return .orange }
        if case .arrived = phase { return .green }
        return focusSegment.type.activityAccent
    }

    /// `countdown`, split so the widget can put a live clock in the middle.
    private var countdownPhrasing: (prefix: String, suffix: String, fallback: String?) {
        switch phase {
        case .boarding:  return ("Departs in ", "", nil)
        case .inTransit: return ("", " left", nil)
        case .waiting:   return ("", " to boarding", nil)
        case .arrived:   return ("", "", "Complete")
        }
    }
}

#endif
