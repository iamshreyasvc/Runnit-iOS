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

    var type: TripType {
        get { TripType(rawValue: typeRaw) ?? .other }
        set { typeRaw = newValue.rawValue }
    }

    /// The moment the trip is "done" — arrival if set, otherwise departure.
    var endDate: Date { arrivalDate ?? departureDate }

    var isPast: Bool { endDate < Date() }
    var isUpcoming: Bool { !isPast }

    /// Great-circle distance between origin and destination.
    var distanceMeters: Double {
        origin.clLocation.distance(from: destination.clLocation)
    }

    /// A human display title, falling back to "Origin → Destination".
    var displayTitle: String {
        if !title.isEmpty { return title }
        let from = origin.displayName
        let to = destination.displayName
        return "\(from) → \(to)"
    }
}
