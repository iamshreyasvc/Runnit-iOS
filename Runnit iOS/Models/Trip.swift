//
//  Trip.swift
//  Runnit iOS
//
//  The core SwiftData model. A Trip covers every travel mode (flight, train,
//  road trip, other). Transit-only fields are optional so they can stay empty
//  for road trips.
//

import Foundation
import SwiftData
import SwiftUI
import CoreLocation

enum TripType: String, Codable, CaseIterable, Identifiable {
    case flight
    case train
    case roadTrip
    case other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .flight:   return "Flight"
        case .train:    return "Train"
        case .roadTrip: return "Road Trip"
        case .other:    return "Other"
        }
    }

    var symbol: String {
        switch self {
        case .flight:   return "airplane"
        case .train:    return "tram.fill"
        case .roadTrip: return "car.fill"
        case .other:    return "location.fill"
        }
    }

    /// Whether this mode captures carrier / vehicle-number style details.
    var isScheduledTransit: Bool {
        self == .flight || self == .train
    }

    /// Noun for the vehicle identifier field.
    var numberLabel: String {
        switch self {
        case .flight: return "Flight Number"
        case .train:  return "Train Number"
        default:      return "Number"
        }
    }

    /// Noun for the boarding-point field (gate vs platform).
    var boardingLabel: String {
        switch self {
        case .flight: return "Gate / Terminal"
        case .train:  return "Platform"
        default:      return "Boarding"
        }
    }
}

/// Where a trip stands with iCloud.
enum TripSyncState: Equatable {
    /// Everything about this trip is on the server.
    case saved
    /// Edited (or brand new) and still waiting to upload.
    case pending
    /// Can't upload at all — iCloud isn't signed in or set up on this device.
    case unavailable
    /// Never syncs at all — the seeded demo trips.
    case localOnly
}

extension TripSyncState {
    /// Fold in whether iCloud is usable at all.
    ///
    /// Only `pending` changes: "waiting to upload" and "nothing can upload,
    /// ever, until you sign in" look identical to someone waiting for a badge
    /// to flip, and only the second is worth acting on.
    ///
    /// `saved` deliberately survives — a trip already on the server stays saved
    /// whether or not this device is signed in right now — and `localOnly`
    /// survives because demo trips were never going anywhere anyway.
    func resolved(cloudAvailable: Bool) -> TripSyncState {
        guard self == .pending, !cloudAvailable else { return self }
        return .unavailable
    }
}

@Model
final class Trip {
    var id: UUID = UUID()
    private var typeRaw: String = TripType.flight.rawValue
    var title: String = ""

    /// The ordered legs of this trip. Simple point-to-point trips have exactly
    /// one segment; multi-modal trips chain several (e.g. flight → train → drive).
    @Relationship(deleteRule: .cascade, inverse: \TripSegment.trip)
    var segments: [TripSegment] = []

    // MARK: Denormalized "overall" summary
    //
    // These flat fields mirror the whole journey — first leg's origin/departure,
    // last leg's destination/arrival, and the primary (first) leg's mode and
    // transit details. They exist so the SwiftData schema change stays additive
    // (lightweight migration) and so `@Query` can sort by `departureDate`. Keep
    // them in sync with `segments` via `refreshSummary()` on every write.
    var origin: Place = Place(name: "", latitude: 0, longitude: 0)
    var destination: Place = Place(name: "", latitude: 0, longitude: 0)

    var departureDate: Date = Date()
    var arrivalDate: Date?

    // Scheduled-transit details of the primary (first) leg.
    var operatorName: String?
    var vehicleNumber: String?
    var boardingPoint: String?
    var seat: String?
    var confirmation: String?

    var notes: String?
    var createdAt: Date = Date()

    // MARK: CloudKit sync & sharing
    //
    // All additive with defaults, so the schema change stays a lightweight
    // migration. Nothing here is meaningful until the trip has synced once.

    /// Last local edit, used to settle conflicts (last writer wins). Bumped by
    /// `touch()` on every write path.
    var updatedAt: Date = Date()

    /// A seeded demo trip. Never uploaded — accounts shouldn't fill with fake data.
    var isSample: Bool = false

    /// The CloudKit zone this trip owns, `trip-<id>`. Every trip gets its own so
    /// sharing is just attaching a CKShare to the zone — records never move.
    var zoneName: String?

    /// The zone owner's CloudKit user record name. Nil means this trip is ours;
    /// a value means someone shared it with us.
    var ownerName: String?

    /// Archived system fields of the trip's CKShare. Non-nil once shared.
    var shareRecordData: Data?

    /// The share's people, mirrored for instant, offline rendering.
    var participantSummaries: [ShareParticipantSummary] = []

    /// Archived CKRecord system fields (change tag, etc.) so updates don't
    /// clobber the server copy.
    var ckSystemFields: Data?

    /// The `updatedAt` of the version CloudKit last confirmed — either sent by
    /// us or received from someone else. Anything newer than this is an
    /// unsynced local edit; equal means the server already has this exact
    /// version, which is what stops a freshly downloaded trip from immediately
    /// uploading itself back.
    var syncedAt: Date?

    init(
        id: UUID = UUID(),
        type: TripType = .flight,
        title: String = "",
        origin: Place,
        destination: Place,
        departureDate: Date = Date(),
        arrivalDate: Date? = nil,
        operatorName: String? = nil,
        vehicleNumber: String? = nil,
        boardingPoint: String? = nil,
        seat: String? = nil,
        confirmation: String? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.typeRaw = type.rawValue
        self.title = title
        self.origin = origin
        self.destination = destination
        self.departureDate = departureDate
        self.arrivalDate = arrivalDate
        self.operatorName = operatorName
        self.vehicleNumber = vehicleNumber
        self.boardingPoint = boardingPoint
        self.seat = seat
        self.confirmation = confirmation
        self.notes = notes
        self.createdAt = Date()
    }

    /// Primary (first-leg) mode, used for tinting and the overall summary.
    var type: TripType {
        get { TripType(rawValue: typeRaw) ?? .other }
        set { typeRaw = newValue.rawValue }
    }

    // MARK: Segment-derived accessors

    /// Legs in travel order.
    var orderedSegments: [TripSegment] {
        segments.sorted { $0.order < $1.order }
    }

    /// Legs for display. Falls back to a single synthesized leg built from the
    /// legacy flat fields when a trip has no segments yet (e.g. a brand-new or
    /// not-yet-backfilled trip), so every screen renders consistently.
    var displaySegments: [TripSegment] {
        let segs = orderedSegments
        if !segs.isEmpty { return segs }
        return [TripSegment(
            type: type, origin: origin, destination: destination,
            departureDate: departureDate, arrivalDate: arrivalDate,
            operatorName: operatorName, vehicleNumber: vehicleNumber,
            boardingPoint: boardingPoint, seat: seat, confirmation: confirmation,
            order: 0
        )]
    }

    /// True when the trip chains more than one leg.
    var isMultiModal: Bool { orderedSegments.count > 1 }

    /// Number of legs (at least 1).
    var legCount: Int { max(orderedSegments.count, 1) }

    /// Modes in travel order — drives the card's mode-icon chain.
    var modeSequence: [TripType] { displaySegments.map(\.type) }

    /// Overall starting point (first leg's origin).
    var startPlace: Place { displaySegments.first?.origin ?? origin }

    /// Overall final destination (last leg's destination).
    var endPlace: Place { displaySegments.last?.destination ?? destination }

    /// Every place the trip touches, in order — for Passport aggregation.
    var allPlaces: [Place] { displaySegments.flatMap { [$0.origin, $0.destination] } }

    /// When the trip begins (first leg's departure).
    var startDate: Date { displaySegments.first?.departureDate ?? departureDate }

    /// The moment the trip is "done" — last leg's arrival, else its departure.
    var endDate: Date { displaySegments.last?.endDate ?? (arrivalDate ?? departureDate) }

    var isPast: Bool { isPast(now: Date()) }
    var isUpcoming: Bool { !isPast }

    /// Whether the trip is over. A final leg entered without an arrival (an
    /// open-ended drive, a flight added without times) is assumed to run for
    /// `TripStatus.openEndedDuration` rather than ending the instant it departs —
    /// otherwise a trip would file itself under Past while it's still happening.
    func isPast(now: Date) -> Bool {
        var end = endDate
        if displaySegments.last?.arrivalDate == nil {
            end = end.addingTimeInterval(TripStatus.openEndedDuration)
        }
        return end < now
    }

    /// Total distance across all legs.
    var distanceMeters: Double {
        let segs = orderedSegments
        if segs.isEmpty { return origin.clLocation.distance(from: destination.clLocation) }
        return segs.reduce(0) { $0 + $1.distanceMeters }
    }

    /// A human display title, falling back to "Start → End".
    var displayTitle: String {
        if !title.isEmpty { return title }
        return "\(startPlace.displayName) → \(endPlace.displayName)"
    }

    // MARK: Sharing

    /// Whether this trip has been shared with anyone.
    var isShared: Bool { shareRecordData != nil }

    /// Whether we own the trip (as opposed to having been invited to it).
    var isOwnedByMe: Bool { ownerName == nil }

    /// Our own row in the share, when we're a participant rather than the owner.
    var myParticipation: ShareParticipantSummary? {
        participantSummaries.first(where: \.isCurrentUser)
    }

    /// Whether this device's user may change the trip. Owners always can; an
    /// invitee can only if they were given write access. CloudKit enforces this
    /// server-side too — this is so the UI doesn't offer what will be rejected.
    var canEdit: Bool {
        if isOwnedByMe { return true }
        return myParticipation?.canEdit ?? false
    }

    /// The trip's owner, for "shared with you by …" phrasing.
    var ownerParticipant: ShareParticipantSummary? {
        participantSummaries.first(where: \.isOwner)
    }

    /// Everyone on the trip except us, most-joined-first — what the participant
    /// stack and the roster show.
    var collaborators: [ShareParticipantSummary] {
        participantSummaries
            .filter { !$0.isCurrentUser }
            .sorted { lhs, rhs in
                if lhs.isOwner != rhs.isOwner { return lhs.isOwner }
                let lhsJoined = lhs.acceptance == .accepted
                let rhsJoined = rhs.acceptance == .accepted
                if lhsJoined != rhsJoined { return lhsJoined }
                return lhs.displayName < rhs.displayName
            }
    }

    /// Whether this trip's current state has reached iCloud.
    ///
    /// The trip and its legs are judged together: a leg edited but not yet
    /// uploaded means the trip as a whole isn't saved, even though the trip
    /// record itself might be.
    var syncState: TripSyncState {
        // Demo data deliberately never leaves the device, so "not saved" would
        // be alarming rather than informative.
        if isSample { return .localOnly }
        guard let syncedAt, updatedAt <= syncedAt else { return .pending }
        for segment in segments {
            guard let segmentSynced = segment.syncedAt,
                  segment.updatedAt <= segmentSynced
            else { return .pending }
        }
        return .saved
    }

    /// Stamp the trip as just-edited, so a later sync can order conflicting
    /// versions. Call from any path that changes the trip or one of its legs.
    func touch(_ date: Date = Date()) {
        updatedAt = date
    }

    /// Build a trip from ordered legs, wiring each segment's `order` and inverse
    /// relationship and deriving the denormalized summary. The caller inserts the
    /// returned trip into a ModelContext (its segments are inserted by cascade).
    static func make(title: String = "", notes: String? = nil, segments: [TripSegment]) -> Trip {
        let start = segments.first?.origin ?? Place(name: "", latitude: 0, longitude: 0)
        let end = segments.last?.destination ?? Place(name: "", latitude: 0, longitude: 0)
        let trip = Trip(origin: start, destination: end)
        trip.title = title
        trip.notes = notes
        for (i, seg) in segments.enumerated() {
            seg.order = i
            seg.trip = trip
        }
        trip.segments = segments
        trip.refreshSummary()
        return trip
    }

    /// Re-derive the denormalized flat summary fields from the current segments.
    /// Call after inserting, editing, reordering, or removing legs.
    func refreshSummary() {
        touch()
        let segs = orderedSegments
        guard let first = segs.first, let last = segs.last else { return }
        type = first.type
        origin = first.origin
        destination = last.destination
        departureDate = first.departureDate
        arrivalDate = last.arrivalDate ?? (segs.count > 1 ? last.departureDate : nil)
        operatorName = first.operatorName
        vehicleNumber = first.vehicleNumber
        boardingPoint = first.boardingPoint
        seat = first.seat
        confirmation = first.confirmation
    }
}
