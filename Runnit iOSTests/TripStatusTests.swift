//
//  TripStatusTests.swift
//  Runnit iOSTests
//
//  Covers the live "right now" reading of a trip: which leg is current, how far
//  through it we are, and how a delayed arrival moves both.
//

import Foundation
import Testing
@testable import Runnit_iOS

@MainActor
struct TripStatusTests {

    /// A fixed "now" so nothing here depends on the wall clock.
    private static let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func hours(_ h: Double) -> Date {
        Self.now.addingTimeInterval(h * 3600)
    }

    private func flight(
        from origin: Place, to destination: Place,
        departs: Date, arrives: Date?, number: String = "UA 100"
    ) -> TripSegment {
        TripSegment(type: .flight, origin: origin, destination: destination,
                    departureDate: departs, arrivalDate: arrives,
                    operatorName: "United", vehicleNumber: number)
    }

    private func status(_ trip: Trip, records: [FlightStatusRecord] = []) -> TripStatus? {
        TripStatus(trip: trip, records: records, now: Self.now)
    }

    // MARK: Activation window

    @Test("A trip further out than the lead time has no live status")
    func tooEarly() {
        let trip = Trip.make(segments: [
            flight(from: .sfo, to: .jfk, departs: hours(30), arrives: hours(36))
        ])
        #expect(status(trip) == nil)
    }

    @Test("A trip long finished has no live status")
    func longOver() {
        let trip = Trip.make(segments: [
            flight(from: .sfo, to: .jfk, departs: hours(-20), arrives: hours(-14))
        ])
        #expect(status(trip) == nil)
    }

    @Test("The card wakes up inside the lead time, before departure")
    func boardingSoon() {
        let leg = flight(from: .sfo, to: .jfk, departs: hours(2), arrives: hours(8))
        let trip = Trip.make(segments: [leg])

        let status = status(trip)
        #expect(status?.phase == .boarding(leg))
        #expect(status?.focusSegment.id == leg.id)
        // Two hours into a four-hour countdown.
        #expect(abs((status?.progress ?? 0) - 0.5) < 0.01)
        #expect(status?.timeRemaining == TimeInterval(2 * 3600))
    }

    // MARK: In transit

    @Test("Halfway through a leg reads as in transit, halfway along the bar")
    func inTransitProgress() {
        let leg = flight(from: .sfo, to: .jfk, departs: hours(-3), arrives: hours(3))
        let trip = Trip.make(segments: [leg])

        let status = status(trip)
        #expect(status?.phase == .inTransit(leg))
        #expect(abs((status?.progress ?? 0) - 0.5) < 0.01)
        #expect(status?.timeRemaining == TimeInterval(3 * 3600))
    }

    @Test("A live delayed arrival pushes the finish line out and reports the delay")
    func delayedArrivalStretchesTheLeg() {
        let leg = flight(from: .sfo, to: .jfk, departs: hours(-3), arrives: hours(1))
        let trip = Trip.make(segments: [leg])

        let record = FlightStatusRecord(segmentID: leg.id)
        record.statusRaw = FlightPhase.active.rawValue
        // Captured on the same (fixed) day as `now`, or it wouldn't be displayable.
        record.fetchedAt = Self.now
        record.depActual = leg.departureDate
        record.arrScheduled = leg.arrivalDate
        record.arrEstimated = hours(2)          // an hour late
        record.arrDelayMinutes = 60

        let status = status(trip, records: [record])
        #expect(status?.phase == .inTransit(leg))
        #expect(status?.delayMinutes == 60)
        // Without the delay we'd be 3/4 through; the late ETA makes it 3/5.
        #expect(abs((status?.progress ?? 0) - 0.6) < 0.01)
        #expect(status?.timeRemaining == TimeInterval(2 * 3600))
    }

    // MARK: Layovers

    @Test("Between two flights, the status is the layover — and its clock is ticking")
    func layover() {
        let inbound = flight(from: .sfo, to: .ord, departs: hours(-6), arrives: hours(-1))
        let outbound = flight(from: .ord, to: .jfk, departs: hours(1), arrives: hours(4),
                              number: "UA 200")
        let trip = Trip.make(segments: [inbound, outbound])

        let status = status(trip)
        #expect(status?.phase == .waiting(arrived: inbound, next: outbound))
        // The card is about the flight you still have to catch.
        #expect(status?.focusSegment.id == outbound.id)
        #expect(status?.followingSegment == nil)
        // One hour into a two-hour layover.
        #expect(abs((status?.progress ?? 0) - 0.5) < 0.01)
        #expect(status?.timeRemaining == 3600)
    }

    @Test("While flying the inbound, the connecting leg is the one that follows")
    func followingSegmentDuringInbound() {
        let inbound = flight(from: .sfo, to: .ord, departs: hours(-2), arrives: hours(2))
        let outbound = flight(from: .ord, to: .jfk, departs: hours(4), arrives: hours(7),
                              number: "UA 200")
        let trip = Trip.make(segments: [inbound, outbound])

        let status = status(trip)
        #expect(status?.phase == .inTransit(inbound))
        #expect(status?.followingSegment?.id == outbound.id)
    }

    // MARK: Arrival

    @Test("Just-landed still shows, complete, until the settle time runs out")
    func arrived() {
        let leg = flight(from: .sfo, to: .jfk, departs: hours(-7), arrives: hours(-1))
        let trip = Trip.make(segments: [leg])

        let status = status(trip)
        #expect(status?.phase == .arrived(leg))
        #expect(status?.progress == 1)
        #expect(status?.timeRemaining == nil)
    }

    // MARK: Open-ended legs

    @Test("A drive with no arrival time is under way, with no bar to draw")
    func openEndedDrive() {
        let drive = TripSegment(type: .roadTrip, origin: .sfo, destination: .bigSur,
                                departureDate: hours(-1), arrivalDate: nil)
        let trip = Trip.make(segments: [drive])

        let status = status(trip)
        #expect(status?.phase == .inTransit(drive))
        #expect(status?.progress == nil)
        #expect(status?.timeRemaining == nil)
    }

    @Test("An open-ended leg ends when the next leg leaves")
    func openEndedLegEndsAtNextDeparture() {
        let drive = TripSegment(type: .roadTrip, origin: .sfo, destination: .lhr,
                                departureDate: hours(-4), arrivalDate: nil)
        let train = TripSegment(type: .train, origin: .lhr, destination: .paris,
                                departureDate: hours(-1), arrivalDate: hours(2), order: 1)
        let trip = Trip.make(segments: [drive, train])

        #expect(status(trip)?.phase == .inTransit(train))
    }

    // MARK: Past / Upcoming classification

    /// A flight added without an arrival time used to flip to "Past" the moment
    /// it departed — filing a trip that's in the air under the Past tab.
    @Test("A trip with no arrival time is not past the moment it departs")
    func openEndedTripIsNotPastAtDeparture() {
        let trip = Trip.make(segments: [
            flight(from: .sfo, to: .jfk, departs: hours(-1), arrives: nil)
        ])
        #expect(trip.isPast(now: Self.now) == false)
    }

    @Test("An open-ended trip settles once the assumed duration has run out")
    func openEndedTripSettlesEventually() {
        let trip = Trip.make(segments: [
            flight(from: .sfo, to: .jfk, departs: hours(-5), arrives: nil)
        ])
        #expect(trip.isPast(now: Self.now))
    }

    @Test("A trip with a known arrival is past once that arrival passes")
    func arrivedTripIsPast() {
        let trip = Trip.make(segments: [
            flight(from: .sfo, to: .jfk, departs: hours(-8), arrives: hours(-1))
        ])
        #expect(trip.isPast(now: Self.now))
    }

    /// The tab filter's second gate: even when the planned times say "past", a
    /// live record showing the flight still in the air keeps the trip active —
    /// TripStatus stays non-nil, and the Past tab must not claim it.
    @Test("A delayed flight past its booked arrival still reads as under way")
    func delayedFlightPastBookedArrivalIsStillLive() {
        let leg = flight(from: .sfo, to: .jfk, departs: hours(-7), arrives: hours(-1))
        let trip = Trip.make(segments: [leg])

        let record = FlightStatusRecord(segmentID: leg.id)
        record.statusRaw = FlightPhase.active.rawValue
        record.fetchedAt = Self.now
        record.arrEstimated = hours(1)   // running two hours late, still airborne

        #expect(trip.isPast(now: Self.now))                    // planned times say over…
        #expect(status(trip, records: [record]) != nil)        // …but the flight is live
    }

    /// The mirror image: a leg that already landed is over, even though the
    /// booked arrival is still hours away — it must never sit under Upcoming.
    @Test("A landed leg ends the trip before its booked arrival")
    func landedRecordEndsTheTripEarly() {
        let leg = flight(from: .sfo, to: .jfk, departs: hours(-7), arrives: hours(4))
        let trip = Trip.make(segments: [leg])

        let record = FlightStatusRecord(segmentID: leg.id)
        record.statusRaw = FlightPhase.landed.rawValue
        record.isFinal = true
        record.depActual = hours(-7)
        record.arrActual = hours(-3)
        record.fetchedAt = hours(-3)

        // The effective end is the actual landing, not the booked arrival…
        #expect(TripStatus.effectiveEnd(of: trip, records: [record], now: Self.now) == hours(-3))
        // …and the trip is past its settle window, so nothing reads as live.
        #expect(status(trip, records: [record]) == nil)
    }

    @Test("Without records the effective end is the planned end")
    func effectiveEndFallsBackToPlan() {
        let leg = flight(from: .sfo, to: .jfk, departs: hours(2), arrives: hours(8))
        let trip = Trip.make(segments: [leg])
        #expect(TripStatus.effectiveEnd(of: trip, records: [], now: Self.now) == hours(8))
    }
}
