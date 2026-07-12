//
//  FlightStatusProvider.swift
//  Runnit iOS
//
//  Seam for future live tracking. v1 ships a manual (no-op) provider; a real
//  implementation backed by an aviation API (AeroAPI / AviationStack) can be
//  dropped in behind this protocol without touching the views.
//

import Foundation

/// A point-in-time status for a scheduled-transit trip.
struct FlightStatus: Equatable {
    enum State: String {
        case scheduled = "Scheduled"
        case boarding  = "Boarding"
        case departed  = "Departed"
        case enRoute   = "En route"
        case landed    = "Landed"
        case delayed   = "Delayed"
        case cancelled = "Cancelled"
        case unknown   = "—"
    }

    var state: State = .unknown
    var scheduledDeparture: Date?
    var estimatedDeparture: Date?
    var boardingPoint: String?      // gate / platform
    var updatedAt: Date?

    static let unknown = FlightStatus()
}

@MainActor
protocol FlightStatusProvider {
    /// Best-effort live status for a trip. Returns `.unknown` when unavailable.
    func status(for trip: Trip) async throws -> FlightStatus
}

/// Default v1 provider: reflects only the details the user typed in, with no
/// network calls. Non-transit trips report `.unknown`.
struct ManualFlightStatusProvider: FlightStatusProvider {
    func status(for trip: Trip) async throws -> FlightStatus {
        guard trip.type.isScheduledTransit else { return .unknown }
        return FlightStatus(
            state: trip.isPast ? .landed : .scheduled,
            scheduledDeparture: trip.departureDate,
            estimatedDeparture: trip.departureDate,
            boardingPoint: trip.boardingPoint,
            updatedAt: nil
        )
    }
}
