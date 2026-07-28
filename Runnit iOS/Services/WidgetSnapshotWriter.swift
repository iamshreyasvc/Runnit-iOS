//
//  WidgetSnapshotWriter.swift
//  Runnit iOS
//
//  Publishes the "next trips" snapshot the Home Screen / Lock Screen widget reads.
//  Called whenever the trips change (RootTabView), it distils the store down to a
//  few entries — an underway trip first, then the soonest upcoming ones — writes
//  them to the shared App Group, and nudges WidgetKit to reload.
//

import Foundation
import WidgetKit

@MainActor
enum WidgetSnapshotWriter {
    /// How many trips to hand the widget. It only ever shows one or two, but a
    /// small buffer lets its timeline roll forward as each departs.
    private static let maxEntries = 5

    static func write(trips: [Trip], records: [FlightStatusRecord], now: Date = Date()) {
        // Trips worth showing: real ones that are either underway or still ahead.
        let candidates = trips.filter { trip in
            guard !trip.isSample else { return false }
            let underway = TripStatus(trip: trip, records: records, now: now) != nil
            return underway || trip.isUpcoming
        }

        let entries = candidates
            .map { trip -> (trip: Trip, status: TripStatus?) in
                (trip, TripStatus(trip: trip, records: records, now: now))
            }
            .sorted { lhs, rhs in
                // Underway trips come first; within a group, soonest start wins.
                let lhsLive = lhs.status != nil
                let rhsLive = rhs.status != nil
                if lhsLive != rhsLive { return lhsLive }
                return lhs.trip.startDate < rhs.trip.startDate
            }
            .prefix(maxEntries)
            .map { pair in entry(from: pair.trip, status: pair.status) }

        let snapshot = TripWidgetSnapshot(generatedAt: now, trips: Array(entries))
        if let data = snapshot.encoded() {
            WidgetSharing.defaults.set(data, forKey: WidgetSharing.snapshotKey)
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    private static func entry(from trip: Trip, status: TripStatus?) -> TripWidgetSnapshot.Entry {
        TripWidgetSnapshot.Entry(
            tripID: trip.id.uuidString,
            title: trip.displayTitle,
            originCode: trip.startPlace.codeLabel,
            destinationCode: trip.endPlace.codeLabel,
            originName: trip.startPlace.displayName,
            destinationName: trip.endPlace.displayName,
            mode: mode(trip.type),
            departureDate: trip.startDate,
            arrivalDate: trip.arrivalDate,
            isUnderway: status != nil,
            headline: status?.headline
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
}
