//
//  FlightStatusRecord.swift
//  Runnit iOS
//
//  A cached, parsed snapshot of one flight leg's live status. There is at most
//  one record per TripSegment (keyed by `segmentID`). Records are the ONLY thing
//  the UI reads for live status — fetching is gated by FlightTracker. Once a
//  flight is landed/cancelled the record is frozen (`isFinal`) and never
//  refetched, so past flights cost zero API calls.
//

import Foundation
import SwiftData
import CoreLocation

/// Coarse phase derived from the API's `flight_status`.
enum FlightPhase: String {
    case scheduled
    case active      // airborne
    case landed
    case cancelled
    case diverted
    case incident
    case unknown

    init(apiStatus: String?) {
        switch apiStatus?.lowercased() {
        case "scheduled": self = .scheduled
        case "active":    self = .active
        case "landed":    self = .landed
        case "cancelled": self = .cancelled
        case "diverted":  self = .diverted
        case "incident":  self = .incident
        default:          self = .unknown
        }
    }

    var label: String {
        switch self {
        case .scheduled: return "Scheduled"
        case .active:    return "In the air"
        case .landed:    return "Landed"
        case .cancelled: return "Cancelled"
        case .diverted:  return "Diverted"
        case .incident:  return "Incident"
        case .unknown:   return "—"
        }
    }

    /// Terminal states we freeze on — no further tracking needed.
    var isFinal: Bool { self == .landed || self == .cancelled || self == .diverted }
}

@Model
final class FlightStatusRecord {
    /// The segment this snapshot belongs to (TripSegment.id).
    var segmentID: UUID = UUID()

    var statusRaw: String = FlightPhase.unknown.rawValue
    var flightIata: String?
    var airlineName: String?

    // Departure
    var depScheduled: Date?
    var depEstimated: Date?
    var depActual: Date?
    var depTerminal: String?
    var depGate: String?
    var depDelayMinutes: Int?

    // Arrival
    var arrScheduled: Date?
    var arrEstimated: Date?
    var arrActual: Date?
    var arrTerminal: String?
    var arrGate: String?
    var arrBaggage: String?
    var arrDelayMinutes: Int?

    // Live (only meaningful while airborne)
    var liveLatitude: Double?
    var liveLongitude: Double?
    var liveAltitude: Double?
    var liveDirection: Double?
    var liveSpeed: Double?
    var liveIsGround: Bool?
    var liveUpdated: Date?

    /// When we last fetched (success or empty).
    var fetchedAt: Date = Date()
    /// Frozen: a terminal status was captured; never refetch.
    var isFinal: Bool = false
    /// The API answered but had no matching flight (negative cache).
    var didFindData: Bool = true

    init(segmentID: UUID) {
        self.segmentID = segmentID
    }

    var phase: FlightPhase { FlightPhase(rawValue: statusRaw) ?? .unknown }

    var hasLivePosition: Bool {
        phase == .active && liveLatitude != nil && liveLongitude != nil
            && (liveIsGround ?? false) == false
    }

    var liveCoordinate: CLLocationCoordinate2D? {
        guard let lat = liveLatitude, let lon = liveLongitude else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    /// Populate from a decoded API flight and freeze if terminal.
    func apply(_ flight: ASFlight) {
        let phase = FlightPhase(apiStatus: flight.flightStatus)
        statusRaw = phase.rawValue
        flightIata = flight.flight?.iata
        airlineName = flight.airline?.name

        depScheduled = ASDate.parse(flight.departure?.scheduled)
        depEstimated = ASDate.parse(flight.departure?.estimated)
        depActual = ASDate.parse(flight.departure?.actual)
        depTerminal = flight.departure?.terminal
        depGate = flight.departure?.gate
        depDelayMinutes = flight.departure?.delay

        arrScheduled = ASDate.parse(flight.arrival?.scheduled)
        arrEstimated = ASDate.parse(flight.arrival?.estimated)
        arrActual = ASDate.parse(flight.arrival?.actual)
        arrTerminal = flight.arrival?.terminal
        arrGate = flight.arrival?.gate
        arrBaggage = flight.arrival?.baggage
        arrDelayMinutes = flight.arrival?.delay

        liveLatitude = flight.live?.latitude
        liveLongitude = flight.live?.longitude
        liveAltitude = flight.live?.altitude
        liveDirection = flight.live?.direction
        liveSpeed = flight.live?.speedHorizontal
        liveIsGround = flight.live?.isGround
        liveUpdated = ASDate.parse(flight.live?.updated)

        fetchedAt = Date()
        didFindData = true
        isFinal = phase.isFinal
    }

    /// Mark that a fetch returned no matching flight (negative cache).
    func markEmpty() {
        fetchedAt = Date()
        didFindData = false
    }
}
