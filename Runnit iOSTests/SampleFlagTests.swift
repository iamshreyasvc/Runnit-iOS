//
//  SampleFlagTests.swift
//  Runnit iOSTests
//
//  Installs that seeded demo trips before `isSample` existed have no flag to
//  read, so the seeded ones are recovered by matching the seeder's own titles
//  and flight numbers. Getting this wrong in one direction fills someone's
//  iCloud account with fake trips; in the other it silently refuses to sync a
//  real one. The second is worse, so the matcher is deliberately narrow.
//

import Foundation
import Testing
@testable import Runnit_iOS

@MainActor
struct SampleFlagTests {

    private func trip(titled title: String) -> Trip {
        Trip.make(title: title, segments: [
            TripSegment(origin: .sfo, destination: .jfk)
        ])
    }

    private func untitledFlight(number: String?) -> Trip {
        Trip.make(segments: [
            TripSegment(type: .flight, origin: .sfo, destination: .jfk,
                        operatorName: "United", vehicleNumber: number)
        ])
    }

    @Test(arguments: [
        "Coast Weekend", "Euro Loop", "Cherry Blossoms",
        "Alps Getaway", "Chicago Connection", "Flight Path Test"
    ])
    func seededTitlesAreRecognized(title: String) {
        #expect(SampleSeeder.isLikelySeededSample(trip(titled: title)))
    }

    @Test(arguments: ["UA 523", "BA 178", "AF 83"])
    func untitledSeededFlightsAreRecognizedByNumber(number: String) {
        #expect(SampleSeeder.isLikelySeededSample(untitledFlight(number: number)))
    }

    @Test func realTripsAreNotMistakenForSamples() {
        #expect(!SampleSeeder.isLikelySeededSample(trip(titled: "Mum's 60th")))
        #expect(!SampleSeeder.isLikelySeededSample(untitledFlight(number: "UA 999")))
        #expect(!SampleSeeder.isLikelySeededSample(untitledFlight(number: nil)))
    }

    /// A titled trip is judged on its title alone — someone's own flight that
    /// happens to be UA 523 must still sync.
    @Test func aTitledTripIsNeverMatchedOnItsFlightNumber() {
        let mine = Trip.make(title: "Interview in New York", segments: [
            TripSegment(type: .flight, origin: .sfo, destination: .jfk,
                        operatorName: "United", vehicleNumber: "UA 523")
        ])
        #expect(!SampleSeeder.isLikelySeededSample(mine))
    }

    @Test func whitespaceOnlyTitlesFallThroughToTheFlightNumber() {
        let padded = Trip.make(title: "   ", segments: [
            TripSegment(type: .flight, origin: .sfo, destination: .jfk,
                        vehicleNumber: "BA 178")
        ])
        #expect(SampleSeeder.isLikelySeededSample(padded))
    }

    @Test func newlySeededTripsCarryTheFlagDirectly() {
        let seeded = Trip.make(title: "Coast Weekend", segments: [
            TripSegment(type: .roadTrip, origin: .sfo, destination: .bigSur)
        ])
        seeded.isSample = true
        #expect(seeded.isSample)
    }
}
