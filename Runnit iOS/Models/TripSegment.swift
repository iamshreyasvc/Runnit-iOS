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

    /// Great-circle distance between this leg's endpoints.
    var distanceMeters: Double {
        origin.clLocation.distance(from: destination.clLocation)
    }

    /// A human label, e.g. "SFO → JFK".
    var displayTitle: String {
        "\(origin.displayName) → \(destination.displayName)"
    }
}
