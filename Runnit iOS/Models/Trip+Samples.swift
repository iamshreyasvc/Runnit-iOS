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

    /// The shipped example of a connection under pressure: SFO → ORD → JFK on
    /// United, departing today. The inbound lands 55 minutes late into Terminal 1
    /// while the outbound leaves Terminal 2, so a booked 1 h 50 m layover collapses
    /// to 55 minutes against a 65-minute requirement — "At risk", with the terminal
    /// change called out.
    ///
    /// The legs must depart *today*: outside real-time reach the seeded snapshots
    /// aren't displayable and the gates and delay would never show. The snapshots
    /// are ordinary records on the ordinary code path — with an API key, a Refresh
    /// simply replaces them with live data.
    ///
    /// Returns fresh instances each call; the caller inserts them into a context.
    static func makeSampleConnection(
        origin: Place, connectingAt hub: Place, destination: Place
    ) -> (trip: Trip, records: [FlightStatusRecord]) {
        let now = Date()
        func hours(_ h: Double) -> Date { now.addingTimeInterval(h * 3600) }
        func minutes(_ m: Double) -> TimeInterval { m * 60 }

        let inbound = TripSegment(
            type: .flight, origin: origin, destination: hub,
            departureDate: hours(2), arrivalDate: hours(6),
            operatorName: "United", vehicleNumber: "UA 355",
            boardingPoint: "G8", seat: "22C", confirmation: "RN4K2P", order: 0
        )
        // A booked 1 h 50 m layover — generous, until the inbound runs 55 min late.
        let outbound = TripSegment(
            type: .flight, origin: hub, destination: destination,
            departureDate: hours(6).addingTimeInterval(minutes(110)), arrivalDate: hours(10),
            operatorName: "United", vehicleNumber: "UA 1290",
            boardingPoint: "E5", seat: "18F", confirmation: "RN4K2P", order: 1
        )
        let trip = Trip.make(title: "Chicago Connection", segments: [inbound, outbound])

        // Inbound: running 55 minutes late, landing at Terminal 1 / Gate B8.
        let inboundStatus = FlightStatusRecord(segmentID: inbound.id)
        inboundStatus.statusRaw = FlightPhase.scheduled.rawValue
        inboundStatus.flightIata = "UA355"
        inboundStatus.airlineName = "United"
        inboundStatus.depScheduled = inbound.departureDate
        inboundStatus.depTerminal = "3"
        inboundStatus.depGate = "G8"
        inboundStatus.depTimeZoneID = origin.timeZoneIdentifier
        inboundStatus.arrTimeZoneID = hub.timeZoneIdentifier
        inboundStatus.arrScheduled = inbound.arrivalDate
        inboundStatus.arrEstimated = hours(6).addingTimeInterval(minutes(55))
        inboundStatus.arrDelayMinutes = 55
        inboundStatus.arrTerminal = "1"
        inboundStatus.arrGate = "B8"

        // Outbound: on time out of Terminal 2 / Gate E5 — a terminal change.
        let outboundStatus = FlightStatusRecord(segmentID: outbound.id)
        outboundStatus.statusRaw = FlightPhase.scheduled.rawValue
        outboundStatus.flightIata = "UA1290"
        outboundStatus.airlineName = "United"
        outboundStatus.depScheduled = outbound.departureDate
        outboundStatus.depTerminal = "2"
        outboundStatus.depGate = "E5"
        outboundStatus.depTimeZoneID = hub.timeZoneIdentifier
        outboundStatus.arrTimeZoneID = destination.timeZoneIdentifier
        outboundStatus.arrScheduled = outbound.arrivalDate

        return (trip, [inboundStatus, outboundStatus])
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
        let leg = TripSegment(type: .roadTrip, origin: .sfo, destination: .bigSur,
                              departureDate: daysFromNow(20))
        leg.stops = [
            RoadStop(place: Place(name: "Half Moon Bay", subtitle: "California",
                                  latitude: 37.4636, longitude: -122.4286,
                                  isoCountryCode: "US", country: "United States",
                                  locality: "Half Moon Bay"),
                     category: .coffee),
            RoadStop(place: Place(name: "Monterey", subtitle: "California",
                                  latitude: 36.6002, longitude: -121.8947,
                                  isoCountryCode: "US", country: "United States",
                                  locality: "Monterey"),
                     category: .food, note: "Lunch on the wharf")
        ]
        return .make(title: "Coast Weekend", segments: [leg])
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

    /// A tight SFO → ORD → JFK connection. Shared (not rebuilt per access) so the
    /// seeded records in `PreviewData.container`, keyed by segment id, keep matching.
    @MainActor static var sampleConnection: Trip { PreviewData.connection.trip }

    /// The live snapshots that make `sampleConnection` read as "At risk".
    @MainActor static var sampleConnectionRecords: [FlightStatusRecord] { PreviewData.connection.records }

    @MainActor static var allSamples: [Trip] {
        [sampleFlight, sampleTrain, sampleRoadTrip, sampleMultiModal,
         sampleConnection, samplePastFlight, samplePastRoadTrip]
    }
}

/// An in-memory container preloaded with samples, for SwiftUI previews.
@MainActor
enum PreviewData {
    static let connection = Trip.makeSampleConnection(
        origin: .sfo, connectingAt: .ord, destination: .jfk
    )

    static let container: ModelContainer = {
        // `.none` matches the app's real container: with the iCloud entitlement
        // present, SwiftData would otherwise turn its own CloudKit mirroring on
        // and fail to load (`Trip.segments` is not optional).
        let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try! ModelContainer(
            for: Trip.self, TripSegment.self, FlightStatusRecord.self, configurations: config
        )
        for trip in Trip.allSamples {
            container.mainContext.insert(trip)
        }
        for record in Trip.sampleConnectionRecords {
            container.mainContext.insert(record)
        }
        return container
    }()

    /// A sync engine for previews. Never started, so it stays `.idle` and makes
    /// no CloudKit calls — previews run without an iCloud account.
    @MainActor
    static let sync = SyncEngine(modelContainer: container)
}
#endif
