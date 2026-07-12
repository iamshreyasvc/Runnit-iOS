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
        Trip(
            type: .flight,
            title: "",
            origin: .sfo,
            destination: .jfk,
            departureDate: daysFromNow(4),
            arrivalDate: daysFromNow(4).addingTimeInterval(6 * 3600),
            operatorName: "United",
            vehicleNumber: "UA 523",
            boardingPoint: "Gate B12",
            seat: "14A",
            confirmation: "ABC123"
        )
    }

    static var sampleTrain: Trip {
        Trip(
            type: .train,
            origin: .lhr,
            destination: .paris,
            departureDate: daysFromNow(12),
            arrivalDate: daysFromNow(12).addingTimeInterval(2.5 * 3600),
            operatorName: "Eurostar",
            vehicleNumber: "ES 9024",
            boardingPoint: "Platform 5",
            seat: "Coach 8, 32"
        )
    }

    static var sampleRoadTrip: Trip {
        Trip(
            type: .roadTrip,
            title: "Coast Weekend",
            origin: .sfo,
            destination: .bigSur,
            departureDate: daysFromNow(20)
        )
    }

    static var samplePastFlight: Trip {
        Trip(
            type: .flight,
            origin: .jfk,
            destination: .lhr,
            departureDate: daysFromNow(-45),
            arrivalDate: daysFromNow(-45).addingTimeInterval(7 * 3600),
            operatorName: "British Airways",
            vehicleNumber: "BA 178"
        )
    }

    static var samplePastRoadTrip: Trip {
        Trip(
            type: .roadTrip,
            title: "Yosemite Escape",
            origin: .sfo,
            destination: .yosemite,
            departureDate: daysFromNow(-120)
        )
    }

    static var allSamples: [Trip] {
        [sampleFlight, sampleTrain, sampleRoadTrip, samplePastFlight, samplePastRoadTrip]
    }
}

/// An in-memory container preloaded with samples, for SwiftUI previews.
@MainActor
enum PreviewData {
    static let container: ModelContainer = {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: Trip.self, configurations: config)
        for trip in Trip.allSamples {
            container.mainContext.insert(trip)
        }
        return container
    }()
}
#endif
