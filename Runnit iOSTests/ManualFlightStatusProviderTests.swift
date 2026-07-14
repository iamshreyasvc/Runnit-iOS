//
//  ManualFlightStatusProviderTests.swift
//  Runnit iOSTests
//
//  Covers the v1 no-network status provider: it reflects only typed-in
//  details and reports non-transit trips as unknown.
//

import Foundation
import Testing
@testable import Runnit_iOS

@MainActor
struct ManualFlightStatusProviderTests {

    private let provider = ManualFlightStatusProvider()

    private func trip(_ type: TripType, departure: Date, arrival: Date?, boarding: String? = nil) -> Trip {
        let seg = TripSegment(type: type, origin: .sfo, destination: .jfk,
                              departureDate: departure, arrivalDate: arrival,
                              boardingPoint: boarding)
        return Trip.make(segments: [seg])
    }

    @Test func upcomingFlightIsScheduled() async throws {
        let depart = Date(timeIntervalSinceNow: 86_400)
        let status = try await provider.status(for: trip(.flight, departure: depart,
                                                         arrival: depart.addingTimeInterval(3_600),
                                                         boarding: "Gate B12"))
        #expect(status.state == .scheduled)
        #expect(status.scheduledDeparture == depart)
        #expect(status.boardingPoint == "Gate B12")
    }

    @Test func pastFlightHasLanded() async throws {
        let depart = Date(timeIntervalSince1970: 1_000_000)
        let status = try await provider.status(for: trip(.flight, departure: depart,
                                                         arrival: depart.addingTimeInterval(3_600)))
        #expect(status.state == .landed)
    }

    @Test func roadTripIsUnknown() async throws {
        let depart = Date(timeIntervalSinceNow: 86_400)
        let status = try await provider.status(for: trip(.roadTrip, departure: depart,
                                                         arrival: depart.addingTimeInterval(3_600)))
        #expect(status == .unknown)
    }
}
