//
//  Trip+Samples.swift
//  Runnit iOS
//
//  Sample trips for previews and first-launch seeding.
//

import Foundation
import SwiftData

extension Trip {
    static func daysFromNow(_ days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: days, to: Date()) ?? Date()
    }
}

#if DEBUG
extension Trip {
    static var sampleFlight: Trip {
        .make(segments: [
            TripSegment(
                type: .flight, origin: .sfo, destination: .jfk,
                departureDate: daysFromNow(4),
                arrivalDate: daysFromNow(4).addingTimeInterval(6 * 3600),
                operatorName: "United", vehicleNumber: "UA 523",
                boardingPoint: "Gate B12", seat: "14A", confirmation: "ABC123"
            )
        ])
    }

    static var sampleTrain: Trip {
        .make(segments: [
            TripSegment(
                type: .train, origin: .lhr, destination: .paris,
                departureDate: daysFromNow(12),
                arrivalDate: daysFromNow(12).addingTimeInterval(2.5 * 3600),
                operatorName: "Eurostar", vehicleNumber: "ES 9024",
                boardingPoint: "Platform 5", seat: "Coach 8, 32"
            )
        ])
    }

    static var sampleRoadTrip: Trip {
        .make(title: "Coast Weekend", segments: [
            TripSegment(type: .roadTrip, origin: .sfo, destination: .bigSur,
                        departureDate: daysFromNow(20))
        ])
    }

    /// A multi-modal trip: fly, then take the train, then drive.
    static var sampleMultiModal: Trip {
        let dep = daysFromNow(28)
        return .make(title: "Euro Loop", segments: [
            TripSegment(type: .flight, origin: .sfo, destination: .lhr,
                        departureDate: dep,
                        arrivalDate: dep.addingTimeInterval(10 * 3600),
                        operatorName: "British Airways", vehicleNumber: "BA 286"),
            TripSegment(type: .train, origin: .lhr, destination: .paris,
                        departureDate: dep.addingTimeInterval(24 * 3600),
                        arrivalDate: dep.addingTimeInterval(24 * 3600 + 2.5 * 3600),
                        operatorName: "Eurostar", vehicleNumber: "ES 9024"),
            TripSegment(type: .roadTrip, origin: .paris, destination: .bigSur,
                        departureDate: dep.addingTimeInterval(4 * 24 * 3600))
        ])
    }

    static var samplePastFlight: Trip {
        .make(segments: [
            TripSegment(type: .flight, origin: .jfk, destination: .lhr,
                        departureDate: daysFromNow(-45),
                        arrivalDate: daysFromNow(-45).addingTimeInterval(7 * 3600),
                        operatorName: "British Airways", vehicleNumber: "BA 178")
        ])
    }

    static var samplePastRoadTrip: Trip {
        .make(title: "Yosemite Escape", segments: [
            TripSegment(type: .roadTrip, origin: .sfo, destination: .yosemite,
                        departureDate: daysFromNow(-120))
        ])
    }

    static var allSamples: [Trip] {
        [sampleFlight, sampleTrain, sampleRoadTrip, sampleMultiModal, samplePastFlight, samplePastRoadTrip]
    }
}

/// An in-memory container preloaded with samples, for SwiftUI previews.
@MainActor
enum PreviewData {
    static let container: ModelContainer = {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: Trip.self, TripSegment.self, configurations: config)
        for trip in Trip.allSamples {
            container.mainContext.insert(trip)
        }
        return container
    }()
}
#endif
