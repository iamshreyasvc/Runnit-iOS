//
//  TripLiveActivity.swift
//  Runnit iOS
//
//  Starts, updates, and ends the Lock Screen / Dynamic Island Live Activity for a
//  trip that's happening now. It's a thin bridge: `TripStatus` already distills a
//  trip into "what's happening" — this converts that into the SwiftUI-free
//  `TripActivityAttributes.ContentState` the widget draws, and manages exactly one
//  activity per trip.
//
//  Requires: the app's Info.plist to carry `NSSupportsLiveActivities = YES`, and
//  the widget-extension target to render `TripActivityAttributes` (see SETUP.md).
//  All ActivityKit use is compiled out where the framework isn't available.
//

import Foundation

#if canImport(ActivityKit)
import ActivityKit

@MainActor
enum TripLiveActivity {

    /// Bring the live activity for this trip in line with its current status:
    /// start one if the trip is underway and none exists, update the running one,
    /// or end it once the trip is no longer live. Gated by the traveler's pref and
    /// the system-wide Live Activities switch. Safe to call repeatedly.
    static func sync(trip: Trip, records: [FlightStatusRecord], now: Date = Date()) {
        guard enabledByUser, ActivityAuthorizationInfo().areActivitiesEnabled else {
            // If the traveler turned the feature off, tidy up anything running.
            if !enabledByUser { endAll() }
            return
        }

        let existing = Activity<TripActivityAttributes>.activities
            .first { $0.attributes.tripID == trip.id.uuidString }

        // No live status → the trip isn't happening right now. End if we had one.
        guard let status = TripStatus(trip: trip, records: records, now: now) else {
            if let existing {
                Task { await existing.end(nil, dismissalPolicy: .immediate) }
            }
            return
        }

        let state = contentState(from: status)
        // Let the system dim the activity if we somehow stop updating; the end of
        // the current stretch (or an hour out) is a sensible horizon.
        let stale = state.rangeEnd ?? now.addingTimeInterval(3600)
        let content = ActivityContent(state: state, staleDate: stale)

        if let existing {
            Task { await existing.update(content) }
        } else {
            let attributes = attributes(from: trip, status: status)
            _ = try? Activity.request(attributes: attributes, content: content, pushType: nil)
        }
    }

    /// End every Runnit live activity immediately — used when the feature is
    /// switched off, or on a hard reset.
    static func endAll() {
        for activity in Activity<TripActivityAttributes>.activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }

    // MARK: Preference

    private static var enabledByUser: Bool {
        // Default on: the flagship feature shouldn't need opting into. The key is
        // only present once the traveler has toggled it.
        UserDefaults.standard.object(forKey: PrefKey.liveActivitiesEnabled) == nil
            ? true
            : UserDefaults.standard.bool(forKey: PrefKey.liveActivitiesEnabled)
    }

    // MARK: Mapping TripStatus → the activity payload

    private static func attributes(from trip: Trip, status: TripStatus) -> TripActivityAttributes {
        TripActivityAttributes(
            tripID: trip.id.uuidString,
            originCode: trip.startPlace.codeLabel,
            destinationCode: trip.endPlace.codeLabel,
            originName: trip.startPlace.displayName,
            destinationName: trip.endPlace.displayName,
            overallMode: mode(trip.type)
        )
    }

    private static func contentState(from status: TripStatus) -> TripActivityAttributes.ContentState {
        let (start, end) = status.endpoints
        let interval = status.progressInterval
        return TripActivityAttributes.ContentState(
            headline: status.headline,
            subtitle: status.subtitle,
            phase: phase(status.phase),
            legMode: mode(status.focusSegment.type),
            tint: accent(for: status),
            departureCode: start.code,
            arrivalCode: end.code,
            departureTime: start.time,
            arrivalTime: end.time,
            rangeStart: interval?.start,
            rangeEnd: interval?.end,
            delayMinutes: status.delayMinutes,
            punctuality: status.punctuality.0,
            isUnderway: status.isUnderway
        )
    }

    private static func mode(_ type: TripType) -> TripActivityAttributes.Mode {
        switch type {
        case .flight:   return .flight
        case .train:    return .train
        case .roadTrip: return .roadTrip
        case .other:    return .other
        }
    }

    private static func phase(_ phase: TripStatus.Phase) -> TripActivityAttributes.Phase {
        switch phase {
        case .boarding:  return .boarding
        case .inTransit: return .inTransit
        case .waiting:   return .waiting
        case .arrived:   return .arrived
        }
    }

    /// Mirror `TripStatus.tint`'s decision as a serializable accent: cancelled is
    /// red, a delay is orange, arrival is green, otherwise the leg's mode color.
    private static func accent(for status: TripStatus) -> TripActivityAttributes.Accent {
        if status.isCancelled { return .red }
        if (status.delayMinutes ?? 0) > 0 { return .orange }
        if case .arrived = status.phase { return .green }
        switch status.focusSegment.type {
        case .flight:   return .blue
        case .train:    return .orange
        case .roadTrip: return .green
        case .other:    return .purple
        }
    }
}
#endif
