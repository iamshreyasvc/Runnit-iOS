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

    var isPast: Bool { endDate < Date() }
    var isUpcoming: Bool { !isPast }

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
