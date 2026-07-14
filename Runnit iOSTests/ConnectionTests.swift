//
//  ConnectionTests.swift
//  Runnit iOSTests
//
//  Covers the pure connection logic: which legs pair up, how long the layover
//  really is once delays land, and when that stops being enough time.
//

import Foundation
import Testing
@testable import Runnit_iOS

@MainActor
struct ConnectionTests {

    // MARK: Helpers

    /// A fixed "now" so nothing here depends on the wall clock.
    private static let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func hours(_ h: Double) -> Date {
        Self.now.addingTimeInterval(h * 3600)
    }

    private func flight(
        from origin: Place, to destination: Place,
        departs: Date, arrives: Date? = nil,
        number: String = "UA 100", gate: String? = nil
    ) -> TripSegment {
        TripSegment(type: .flight, origin: origin, destination: destination,
                    departureDate: departs, arrivalDate: arrives,
                    operatorName: "United", vehicleNumber: number, boardingPoint: gate)
    }

    /// An inbound snapshot landing `delay` minutes late into `terminal`.
    private func inboundRecord(
        for segment: TripSegment, delayMinutes: Int, terminal: String? = nil,
        phase: FlightPhase = .scheduled
    ) -> FlightStatusRecord {
        let record = FlightStatusRecord(segmentID: segment.id)
        record.statusRaw = phase.rawValue
        record.arrScheduled = segment.arrivalDate
        record.arrEstimated = segment.arrivalDate?.addingTimeInterval(Double(delayMinutes) * 60)
        record.arrDelayMinutes = delayMinutes
        record.arrTerminal = terminal
        record.arrGate = "B8"
        return record
    }

    private func outboundRecord(
        for segment: TripSegment, terminal: String? = nil, phase: FlightPhase = .scheduled
    ) -> FlightStatusRecord {
        let record = FlightStatusRecord(segmentID: segment.id)
        record.statusRaw = phase.rawValue
        record.depScheduled = segment.departureDate
        record.depTerminal = terminal
        record.depGate = "E5"
        return record
    }

    // MARK: Pairing

    @Test func twoFlightsMeetingAtTheSameAirportPair() {
        let trip = Trip.make(segments: [
            flight(from: .sfo, to: .ord, departs: hours(0), arrives: hours(4)),
            flight(from: .ord, to: .jfk, departs: hours(6), arrives: hours(8))
        ])
        #expect(trip.isConnecting)
        #expect(trip.connectionPairs.count == 1)
        #expect(trip.connectionPairs.first?.outbound.origin.name == Place.ord.name)
    }

    @Test func flightThenTrainDoesNotPair() {
        let trip = Trip.make(segments: [
            flight(from: .sfo, to: .lhr, departs: hours(0), arrives: hours(10)),
            TripSegment(type: .train, origin: .lhr, destination: .paris,
                        departureDate: hours(12), arrivalDate: hours(14))
        ])
        #expect(trip.connectionPairs.isEmpty)
        #expect(!trip.isConnecting)
    }

    @Test func flightsAtDifferentAirportsDoNotPair() {
        // You land at JFK but the next flight leaves from LHR — not a connection.
        let trip = Trip.make(segments: [
            flight(from: .sfo, to: .jfk, departs: hours(0), arrives: hours(6)),
            flight(from: .lhr, to: .paris, departs: hours(30), arrives: hours(32))
        ])
        #expect(trip.connectionPairs.isEmpty)
    }

    @Test func threeFlightsYieldTwoPairs() {
        let trip = Trip.make(segments: [
            flight(from: .sfo, to: .ord, departs: hours(0), arrives: hours(4)),
            flight(from: .ord, to: .jfk, departs: hours(6), arrives: hours(8)),
            flight(from: .jfk, to: .lhr, departs: hours(11), arrives: hours(18))
        ])
        #expect(trip.connectionPairs.count == 2)
        #expect(trip.connectionPairs[1].inbound.destination.name == Place.jfk.name)
    }

    // MARK: Draft itineraries (the trip editors)

    /// A draft leg as the editors build one.
    private func draft(
        from origin: Place, to destination: Place, type: TripType = .flight,
        departs: Date, arrives: Date? = nil
    ) -> LegDraft {
        var leg = LegDraft()
        leg.type = type
        leg.origin = origin
        leg.destination = destination
        leg.departureDate = departs
        if let arrives {
            leg.hasArrival = true
            leg.arrivalDate = arrives
        }
        return leg
    }

    @Test func draftLegsSurfaceTheirConnection() {
        let legs = [
            draft(from: .sfo, to: .ord, departs: hours(0), arrives: hours(4)),
            draft(from: .ord, to: .jfk, departs: hours(6), arrives: hours(8))
        ]
        let connections = legs.draftConnections
        #expect(connections.count == 1)
        #expect(connections.first?.effectiveLayover == TimeInterval(2 * 3600))
        #expect(connections.first?.risk == .comfortable)
        #expect(legs.connection(after: legs[0])?.airport.name == Place.ord.name)
        #expect(legs.connection(after: legs[1]) == nil)
    }

    @Test func anIncompleteDraftDoesNotMakeItsNeighborsAdjacent() {
        var middle = LegDraft()          // no origin/destination yet
        middle.type = .flight
        middle.departureDate = hours(5)
        let legs = [
            draft(from: .sfo, to: .ord, departs: hours(0), arrives: hours(4)),
            middle,
            draft(from: .ord, to: .jfk, departs: hours(9), arrives: hours(11))
        ]
        // Legs 0 and 2 would pair if the unfinished leg between them were ignored.
        #expect(legs.draftConnections.isEmpty)
    }

    @Test func draftsDepartingOnArrivalAreAMissedConnection() {
        // The gap the editors must never default to: departing the instant you land.
        let legs = [
            draft(from: .sfo, to: .ord, departs: hours(0), arrives: hours(4)),
            draft(from: .ord, to: .jfk, departs: hours(4), arrives: hours(6))
        ]
        #expect(legs.draftConnections.first?.risk == .missed)
    }

    @Test func draftWithoutAnArrivalCannotJudgeItsLayover() {
        let legs = [
            draft(from: .sfo, to: .ord, departs: hours(0)),   // no arrival entered
            draft(from: .ord, to: .jfk, departs: hours(6), arrives: hours(8))
        ]
        #expect(legs.draftConnections.first?.risk == .unknown)
    }

    // MARK: Layover

    @Test func layoverFallsBackToScheduledLegDatesWithoutRecords() {
        let inbound = flight(from: .sfo, to: .ord, departs: hours(0), arrives: hours(4))
        let outbound = flight(from: .ord, to: .jfk, departs: hours(6), arrives: hours(8))
        let connection = Connection(inbound: inbound, outbound: outbound)

        #expect(connection.scheduledLayover == TimeInterval(2 * 3600))
        #expect(connection.effectiveLayover == TimeInterval(2 * 3600))
        #expect(connection.layoverDelta == 0)
        #expect(connection.inboundDelayMinutes == nil)
    }

    @Test func layoverShrinksByTheInboundArrivalDelay() {
        let inbound = flight(from: .sfo, to: .ord, departs: hours(0), arrives: hours(4))
        let outbound = flight(from: .ord, to: .jfk, departs: hours(6), arrives: hours(8))
        let connection = Connection(
            inbound: inbound, outbound: outbound,
            inboundStatus: inboundRecord(for: inbound, delayMinutes: 55),
            outboundStatus: outboundRecord(for: outbound)
        )

        #expect(connection.scheduledLayover == TimeInterval(2 * 3600))
        #expect(connection.effectiveLayover == TimeInterval(2 * 3600 - 55 * 60))
        #expect(connection.layoverDelta == TimeInterval(-55 * 60))
        #expect(connection.inboundDelayMinutes == 55)
    }

    @Test func departureGateFallsBackToTheLegBoardingPoint() {
        let inbound = flight(from: .sfo, to: .ord, departs: hours(0), arrives: hours(4))
        let outbound = flight(from: .ord, to: .jfk, departs: hours(6), gate: "C12")
        let connection = Connection(inbound: inbound, outbound: outbound)

        #expect(connection.departureGate == "C12")
        #expect(connection.arrivalGate == nil)
        #expect(!connection.isTerminalChange)
    }

    // MARK: Risk

    /// A connection with a `layoverHours` gap, optionally delayed and/or across terminals.
    private func connection(
        layoverHours: Double,
        delayMinutes: Int = 0,
        terminals: (arrival: String, departure: String)? = nil,
        inboundPhase: FlightPhase = .scheduled,
        outboundPhase: FlightPhase = .scheduled
    ) -> Connection {
        let inbound = flight(from: .sfo, to: .ord, departs: hours(0), arrives: hours(4))
        let outbound = flight(from: .ord, to: .jfk, departs: hours(4 + layoverHours), arrives: hours(12))
        return Connection(
            inbound: inbound, outbound: outbound,
            inboundStatus: inboundRecord(for: inbound, delayMinutes: delayMinutes,
                                         terminal: terminals?.arrival, phase: inboundPhase),
            outboundStatus: outboundRecord(for: outbound, terminal: terminals?.departure,
                                           phase: outboundPhase)
        )
    }

    @Test func comfortableWhenWellClearOfTheMinimum() {
        #expect(connection(layoverHours: 3).risk == .comfortable)
    }

    @Test func tightJustAboveTheMinimum() {
        // 60 min: over the 45-min floor, inside the 30-min "tight" margin.
        #expect(connection(layoverHours: 1).risk == .tight)
    }

    @Test func atRiskBelowTheMinimum() {
        // 30 min against a 45-min floor.
        #expect(connection(layoverHours: 0.5).risk == .atRisk)
    }

    @Test func terminalChangeRaisesTheBarByTwentyMinutes() {
        let terminals = (arrival: "1", departure: "2")
        // 55 min clears the 45-min floor, but not the 65 min a terminal change needs.
        let changing = connection(layoverHours: 55.0 / 60, terminals: terminals)
        #expect(changing.isTerminalChange)
        #expect(changing.requiredMinutes == 65)
        #expect(changing.risk == .atRisk)

        // The same 55 minutes within one terminal is merely tight.
        let sameTerminal = connection(layoverHours: 55.0 / 60,
                                      terminals: (arrival: "2", departure: "2"))
        #expect(!sameTerminal.isTerminalChange)
        #expect(sameTerminal.requiredMinutes == 45)
        #expect(sameTerminal.risk == .tight)
    }

    @Test func missedWhenTheOutboundLeavesBeforeYouLand() {
        // A 1-hour layover eaten by a 90-minute inbound delay.
        #expect(connection(layoverHours: 1, delayMinutes: 90).risk == .missed)
    }

    @Test func cancelledLegOutranksTiming() {
        // A comfortable 3 hours, but the outbound is cancelled.
        let cancelled = connection(layoverHours: 3, outboundPhase: .cancelled)
        #expect(cancelled.risk == .cancelled)
    }

    @Test func unknownWithoutAnyArrivalTime() {
        // No inbound arrival on the leg and no snapshot: nothing to measure.
        let inbound = flight(from: .sfo, to: .ord, departs: hours(0))
        let outbound = flight(from: .ord, to: .jfk, departs: hours(6))
        let connection = Connection(inbound: inbound, outbound: outbound)

        #expect(connection.effectiveLayover == nil)
        #expect(connection.risk == .unknown)
    }

    @Test func advisoryNamesTheDelayAndTheTerminalChange() {
        // A booked 1 h 50 m layover, eaten down to 55 min by a late inbound, across
        // terminals — exactly the shipped sample.
        let atRisk = connection(layoverHours: 110.0 / 60, delayMinutes: 55,
                                terminals: (arrival: "1", departure: "2"))
        #expect(atRisk.risk == .atRisk)
        #expect(atRisk.advisory == "Inbound is 55 min late and you change terminals.")
    }

    // MARK: Displayability

    @Test func finalSnapshotIsAlwaysDisplayable() {
        // Departed 45 days ago — out of realtime reach, but the record is frozen.
        let past = flight(from: .sfo, to: .ord,
                          departs: hours(-24 * 45), arrives: hours(-24 * 45 + 4))
        let record = FlightStatusRecord(segmentID: past.id)
        record.statusRaw = FlightPhase.landed.rawValue
        record.isFinal = true
        record.fetchedAt = hours(-24 * 45)

        #expect(record.isDisplayable(for: past, now: Self.now))
    }

    @Test func nonFinalSnapshotFromYesterdayIsNotDisplayable() {
        let today = flight(from: .sfo, to: .ord, departs: Self.now, arrives: hours(4))
        let record = FlightStatusRecord(segmentID: today.id)
        record.statusRaw = FlightPhase.scheduled.rawValue
        record.fetchedAt = hours(-24)   // captured yesterday: a different instance

        #expect(!record.isDisplayable(for: today, now: Self.now))
    }

    @Test func snapshotOutsideRealtimeReachIsNotDisplayable() {
        let future = flight(from: .sfo, to: .ord, departs: hours(24 * 5), arrives: hours(24 * 5 + 4))
        let record = FlightStatusRecord(segmentID: future.id)
        record.statusRaw = FlightPhase.scheduled.rawValue
        record.fetchedAt = Self.now

        #expect(!record.isDisplayable(for: future, now: Self.now))
    }

    @Test func negativeCacheIsNeverDisplayable() {
        let today = flight(from: .sfo, to: .ord, departs: Self.now, arrives: hours(4))
        let record = FlightStatusRecord(segmentID: today.id)
        record.fetchedAt = Self.now
        record.didFindData = false

        #expect(!record.isDisplayable(for: today, now: Self.now))
    }
}
