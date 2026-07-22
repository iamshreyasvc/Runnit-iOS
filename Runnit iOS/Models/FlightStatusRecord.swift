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
    /// IANA id of the departure airport's timezone, e.g. "America/Los_Angeles".
    /// Flight times are always shown on the clock at the airport they happen at.
    var depTimeZoneID: String?

    // Arrival
    var arrScheduled: Date?
    var arrEstimated: Date?
    var arrActual: Date?
    var arrTerminal: String?
    var arrGate: String?
    var arrBaggage: String?
    var arrDelayMinutes: Int?
    var arrTimeZoneID: String?

    // Live (only meaningful while airborne). Units follow Flightradar24:
    // altitude in feet, ground speed in knots, direction in degrees true.
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

    // MARK: CloudKit sync
    //
    // Snapshots ride along in their trip's zone so everyone invited sees the
    // same gate and delay without each device spending the shared API budget.

    /// Last local write, for last-writer-wins conflict resolution.
    var updatedAt: Date = Date()

    /// The trip zone this snapshot belongs in. There's no relationship to walk
    /// (records are keyed by `segmentID` alone), so the zone is stored directly.
    var zoneName: String?

    /// Archived CKRecord system fields.
    var ckSystemFields: Data?

    /// The `updatedAt` CloudKit last confirmed for this snapshot. See
    /// `Trip.syncedAt`.
    var syncedAt: Date?

    init(segmentID: UUID) {
        self.segmentID = segmentID
    }

    var phase: FlightPhase { FlightPhase(rawValue: statusRaw) ?? .unknown }

    /// The clock at the departure airport.
    var depTimeZone: TimeZone? { depTimeZoneID.flatMap(TimeZone.init(identifier:)) }
    /// The clock at the arrival airport.
    var arrTimeZone: TimeZone? { arrTimeZoneID.flatMap(TimeZone.init(identifier:)) }

    var hasLivePosition: Bool {
        phase == .active && liveLatitude != nil && liveLongitude != nil
            && (liveIsGround ?? false) == false
    }

    var liveCoordinate: CLLocationCoordinate2D? {
        guard let lat = liveLatitude, let lon = liveLongitude else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    /// Populate from a composed Flightradar24 snapshot and freeze if terminal.
    ///
    /// The segment is required, not incidental: FR24 publishes no schedules, so
    /// the times the traveler entered on the leg *are* the schedule here. That's
    /// what makes a delay computable at all — actual takeoff minus planned
    /// departure. Terminal, gate, and baggage have no FR24 source and stay nil.
    func apply(_ snapshot: FR24Snapshot, for segment: TripSegment) {
        statusRaw = snapshot.phase.rawValue
        flightIata = snapshot.flightIata
        // The API's airline name is better than the user's, but never lose the
        // one we already have to a lookup that came back empty.
        airlineName = snapshot.airlineName ?? airlineName

        // FR24 timestamps are true UTC instants, so the clock each end is shown on
        // comes from the airport itself — resolved once at autofill time.
        depTimeZoneID = segment.origin.timeZoneIdentifier
        arrTimeZoneID = segment.destination.timeZoneIdentifier

        depScheduled = segment.departureDate
        depEstimated = nil
        depActual = snapshot.takeoff
        depDelayMinutes = Self.delayMinutes(planned: segment.departureDate, actual: snapshot.takeoff)

        arrScheduled = segment.arrivalDate
        // While airborne FR24's ETA is the live arrival estimate; once down, the
        // landing time is the answer.
        arrEstimated = snapshot.landed == nil ? snapshot.eta : nil
        arrActual = snapshot.landed
        arrDelayMinutes = Self.delayMinutes(planned: segment.arrivalDate,
                                            actual: snapshot.landed ?? snapshot.eta)

        // Not available from Flightradar24 at any price — it's an ADS-B tracking
        // API, not an airline schedule feed.
        depTerminal = nil
        depGate = nil
        arrTerminal = nil
        arrGate = nil
        arrBaggage = nil

        let live = snapshot.position
        liveLatitude = live?.lat
        liveLongitude = live?.lon
        liveAltitude = live?.alt          // feet
        liveDirection = live?.track
        liveSpeed = live?.gspeed          // knots
        // FR24 reports no ground flag; a position row only exists while tracked.
        liveIsGround = nil
        liveUpdated = FR24Date.parse(live?.timestamp)

        fetchedAt = Date()
        didFindData = true
        isFinal = snapshot.phase.isFinal
        // Stamped here rather than at each call site, so a snapshot always
        // syncs to everyone on the trip whichever path refreshed it.
        updatedAt = Date()
    }

    /// Minutes late, or nil when it isn't late (or we can't tell). Early
    /// departures are not a delay and shouldn't render as one.
    private static func delayMinutes(planned: Date?, actual: Date?) -> Int? {
        guard let planned, let actual else { return nil }
        let minutes = Int((actual.timeIntervalSince(planned) / 60).rounded())
        return minutes > 0 ? minutes : nil
    }

    /// Mark that a fetch returned no matching flight (negative cache).
    func markEmpty() {
        fetchedAt = Date()
        didFindData = false
        updatedAt = Date()
    }

    /// Whether this snapshot should drive the UI for `segment`: a captured final
    /// snapshot is always valid; live/scheduled data only when the flight is within
    /// tracking reach and the snapshot is recent (never a prior day's instance).
    /// Recency is judged by age, not calendar day — a same-day rule hid a
    /// perfectly fresh mid-flight snapshot the moment a red-eye crossed midnight.
    func isDisplayable(for segment: TripSegment, now: Date = Date()) -> Bool {
        guard didFindData else { return false }
        if isFinal { return true }
        guard FlightTracker.isWithinTrackingReach(segment, now: now) else { return false }
        return now.timeIntervalSince(fetchedAt) < 12 * 3600
    }
}
