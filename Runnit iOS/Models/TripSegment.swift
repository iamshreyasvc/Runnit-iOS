//
//  TripSegment.swift
//  Runnit iOS
//
//  One leg of a (possibly multi-modal) trip: a single mode of travel between
//  two places. A Trip owns an ordered list of these. Simple point-to-point
//  trips are just a Trip with a single segment.
//

import Foundation
import SwiftData
import CoreLocation

@Model
final class TripSegment {
    var id: UUID = UUID()
    private var typeRaw: String = TripType.flight.rawValue

    var origin: Place = Place(name: "", latitude: 0, longitude: 0)
    var destination: Place = Place(name: "", latitude: 0, longitude: 0)

    var departureDate: Date = Date()
    var arrivalDate: Date?

    // Scheduled-transit details (flight / train)
    var operatorName: String?
    var vehicleNumber: String?
    var boardingPoint: String?
    var seat: String?
    var confirmation: String?

    /// Intermediate stops along a road-trip leg, in travel order. Empty for every
    /// other mode. Additive with a default so existing segments migrate cleanly.
    var stops: [RoadStop] = []

    /// The actual route the map draws instead of a straight line: Apple Maps
    /// driving directions (through origin, each stop, destination) for a
    /// `.roadTrip`, the real flown track (from Flightradar24) for a `.flight`,
    /// or the published rail route through the train's halts for an Indian
    /// `.train`. Empty until computed; modes without a real path leave it empty.
    /// Additive with a default so existing segments migrate cleanly.
    var routePolyline: [RoutePoint] = []

    /// The geometry the cached `routePolyline` was built for. When it no longer
    /// matches `geometrySignature` — origin, a stop, or destination moved — the
    /// route is stale and gets recomputed. Nil means "never computed".
    var routeSignature: String?

    /// When the flown-track fetch was last attempted for a `.flight` leg. Throttles
    /// repeat calls that came back empty (a flight FR24 hasn't tracked yet), so a
    /// map that keeps reappearing doesn't burn API credits re-asking. Unused by
    /// road trips, whose routing is free.
    var routeCheckedAt: Date?

    /// Position of this leg within its trip (0-based).
    var order: Int = 0

    /// Owning trip (inverse of `Trip.segments`).
    var trip: Trip?

    init(
        id: UUID = UUID(),
        type: TripType = .flight,
        origin: Place,
        destination: Place,
        departureDate: Date = Date(),
        arrivalDate: Date? = nil,
        operatorName: String? = nil,
        vehicleNumber: String? = nil,
        boardingPoint: String? = nil,
        seat: String? = nil,
        confirmation: String? = nil,
        order: Int = 0
    ) {
        self.id = id
        self.typeRaw = type.rawValue
        self.origin = origin
        self.destination = destination
        self.departureDate = departureDate
        self.arrivalDate = arrivalDate
        self.operatorName = operatorName
        self.vehicleNumber = vehicleNumber
        self.boardingPoint = boardingPoint
        self.seat = seat
        self.confirmation = confirmation
        self.order = order
    }

    var type: TripType {
        get { TripType(rawValue: typeRaw) ?? .other }
        set { typeRaw = newValue.rawValue }
    }

    /// The moment this leg is "done" — arrival if known, otherwise departure.
    var endDate: Date { arrivalDate ?? departureDate }

    /// Whether this leg has any intermediate stops.
    var hasStops: Bool { !stops.isEmpty }

    /// Every place the leg passes through, in order: origin, each stop, destination.
    var routePlaces: [Place] { [origin] + stops.map(\.place) + [destination] }

    /// The real path for this leg when we have one (a road trip's driving route or
    /// a flight's flown track), otherwise nil so a map falls back to its own
    /// straight line through `routePlaces`.
    var routedCoordinates: [CLLocationCoordinate2D]? {
        guard routePolyline.count >= 2 else { return nil }
        return routePolyline.map(\.coordinate)
    }

    /// A stable fingerprint of the leg's geometry input (origin, stops,
    /// destination). Changes whenever any of those move, invalidating a cached
    /// route. A train's route also depends on *which* train runs it — two trains
    /// between the same pair of stations can take quite different lines — so the
    /// number joins the fingerprint there.
    var geometrySignature: String {
        let places = routePlaces.map { "\($0.latitude),\($0.longitude)" }.joined(separator: "|")
        guard type == .train else { return places }
        return places + "#" + (vehicleNumber ?? "")
    }

    /// Whether this leg draws a fetched path (road trips: driving directions;
    /// flights: the flown track; Indian trains: the published rail route) and
    /// that cached path is missing or stale. Modes with no real route never
    /// qualify.
    var needsRouteRefresh: Bool {
        guard type == .roadTrip || type == .flight || type == .train else { return false }
        return routePolyline.count < 2 || routeSignature != geometrySignature
    }

    /// Great-circle distance along this leg. With intermediate stops it sums the
    /// hops through each one, so a detour is reflected rather than ignored.
    var distanceMeters: Double {
        guard hasStops else { return origin.clLocation.distance(from: destination.clLocation) }
        let places = routePlaces
        return zip(places, places.dropFirst())
            .reduce(0) { $0 + $1.0.clLocation.distance(from: $1.1.clLocation) }
    }

    /// A human label, e.g. "SFO → JFK".
    var displayTitle: String {
        "\(origin.displayName) → \(destination.displayName)"
    }
}
