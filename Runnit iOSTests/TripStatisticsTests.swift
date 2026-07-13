//
//  TripStatisticsTests.swift
//  Runnit iOSTests
//
//  Covers the Passport aggregations: only past trips count, and countries /
//  cities / modes / distances roll up across every leg.
//

import Foundation
import Testing
@testable import Runnit_iOS

@MainActor
struct TripStatisticsTests {

    /// A completed (past) single-leg trip between two places.
    private func pastTrip(_ type: TripType, from: Place, to: Place) -> Trip {
        let depart = Date(timeIntervalSince1970: 1_000_000)   // 1970 — safely in the past
        let arrive = depart.addingTimeInterval(3_600)
        let seg = TripSegment(type: type, origin: from, destination: to,
                              departureDate: depart, arrivalDate: arrive)
        return Trip.make(segments: [seg])
    }

    /// An upcoming single-leg trip that must be excluded from the Passport.
    private func upcomingTrip() -> Trip {
        let depart = Date(timeIntervalSinceNow: 86_400)       // tomorrow
        let seg = TripSegment(type: .flight, origin: .sfo, destination: .lhr,
                              departureDate: depart, arrivalDate: depart.addingTimeInterval(3_600))
        return Trip.make(segments: [seg])
    }

    @Test func onlyPastTripsCount() {
        let stats = TripStatistics(trips: [
            pastTrip(.flight, from: .sfo, to: .jfk),
            upcomingTrip(),
        ])
        #expect(stats.totalTrips == 1)
    }

    @Test func uniqueCountriesRollUpAcrossLegs() {
        let stats = TripStatistics(trips: [
            pastTrip(.flight, from: .sfo, to: .jfk),   // US, US
            pastTrip(.flight, from: .sfo, to: .lhr),   // US, GB
        ])
        let countries = stats.uniqueCountries
        let us = countries.first { $0.isoCode == "US" }
        let gb = countries.first { $0.isoCode == "GB" }
        #expect(us?.tripCount == 3)   // SFO, JFK, SFO
        #expect(gb?.tripCount == 1)   // LHR
        // Sorted by descending trip count, so the US leads.
        #expect(countries.first?.isoCode == "US")
    }

    @Test func uniqueCitiesAreDeduplicated() {
        let stats = TripStatistics(trips: [
            pastTrip(.flight, from: .sfo, to: .jfk),   // San Francisco, New York
            pastTrip(.flight, from: .sfo, to: .lhr),   // San Francisco (dupe), London
        ])
        #expect(stats.uniqueCities == 3)
    }

    @Test func modeBreakdownCountsEveryLeg() {
        let stats = TripStatistics(trips: [
            pastTrip(.flight, from: .sfo, to: .jfk),
            pastTrip(.train, from: .lhr, to: .paris),
        ])
        let modes = Dictionary(uniqueKeysWithValues: stats.modeBreakdown.map { ($0.type, $0.count) })
        #expect(modes[.flight] == 1)
        #expect(modes[.train] == 1)
        #expect(modes[.roadTrip] == nil)   // absent modes are omitted
    }

    @Test func totalDistanceAccumulates() {
        let stats = TripStatistics(trips: [pastTrip(.flight, from: .sfo, to: .jfk)])
        #expect(stats.totalDistanceMeters > 3_000_000)
    }

    @Test func emptyStatisticsAreZero() {
        let stats = TripStatistics(trips: [])
        #expect(stats.totalTrips == 0)
        #expect(stats.totalDistanceMeters == 0)
        #expect(stats.uniqueCountries.isEmpty)
        #expect(stats.uniqueCities == 0)
    }

    @Test func longestAndRecentTripsAreIdentified() {
        let short = pastTrip(.flight, from: .lhr, to: .paris)   // ~340 km
        let long = pastTrip(.flight, from: .sfo, to: .jfk)      // ~4,000 km
        let stats = TripStatistics(trips: [short, long])
        #expect(stats.longestTrip === long)
    }
}
