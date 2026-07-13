//
//  TripSegmentTests.swift
//  Runnit iOSTests
//
//  Covers the derived accessors on a single leg.
//

import Foundation
import Testing
@testable import Runnit_iOS

@MainActor
struct TripSegmentTests {

    @Test func typeRoundTripsThroughRawValue() {
        let seg = TripSegment(type: .train, origin: .lhr, destination: .paris)
        #expect(seg.type == .train)
        seg.type = .roadTrip
        #expect(seg.type == .roadTrip)
    }

    @Test func endDateUsesArrivalWhenPresent() {
        let depart = Date(timeIntervalSince1970: 1_000)
        let arrive = Date(timeIntervalSince1970: 5_000)
        let seg = TripSegment(origin: .sfo, destination: .jfk,
                              departureDate: depart, arrivalDate: arrive)
        #expect(seg.endDate == arrive)
    }

    @Test func endDateFallsBackToDeparture() {
        let depart = Date(timeIntervalSince1970: 1_000)
        let seg = TripSegment(origin: .sfo, destination: .jfk, departureDate: depart)
        #expect(seg.endDate == depart)
    }

    @Test func distanceIsPositiveBetweenDistinctPlaces() {
        let seg = TripSegment(origin: .sfo, destination: .jfk)
        // SFO → JFK is roughly 4,000 km; assert a generous lower bound.
        #expect(seg.distanceMeters > 3_000_000)
    }

    @Test func displayTitleJoinsEndpoints() {
        let seg = TripSegment(origin: .sfo, destination: .jfk)
        #expect(seg.displayTitle == "San Francisco Intl (SFO) → John F. Kennedy Intl (JFK)")
    }
}
