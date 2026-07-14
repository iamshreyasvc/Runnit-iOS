//
//  FR24Tests.swift
//  Runnit iOSTests
//
//  Covers the Flightradar24 integration's pure logic: decoding its payloads,
//  parsing its two timestamp shapes, when a leg is worth calling the API about,
//  and how a status record is derived from a snapshot — including the delay
//  figure, which FR24 doesn't supply and we compute against the leg's own times.
//

import Foundation
import Testing
@testable import Runnit_iOS

@MainActor
struct FR24Tests {

    // MARK: Helpers

    private func place(_ name: String, zone: String) -> Place {
        Place(name: name, latitude: 0, longitude: 0, timeZoneIdentifier: zone)
    }

    private var sfo: Place { place("San Francisco Intl (SFO)", zone: "America/Los_Angeles") }
    private var jfk: Place { place("John F. Kennedy Intl (JFK)", zone: "America/New_York") }

    private func flight(departs: Date, arrives: Date? = nil,
                        number: String = "UA 523") -> TripSegment {
        TripSegment(type: .flight, origin: sfo, destination: jfk,
                    departureDate: departs, arrivalDate: arrives,
                    vehicleNumber: number)
    }

    // MARK: Timestamps

    /// FR24 sends two shapes: `2023-11-08T10:10:00Z` on positions and a
    /// zone-less `2025-02-13T21:23:39` on summaries. The second is documented as
    /// UTC, and reading it as *local* time is the single easiest way to be hours
    /// wrong — which is exactly what went wrong with AviationStack.
    @Test func zonelessTimestampsAreUTCNotLocal() throws {
        let parsed = try #require(FR24Date.parse("2025-02-13T21:23:39"))

        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = try #require(TimeZone(identifier: "UTC"))
        let c = utc.dateComponents([.year, .month, .day, .hour, .minute, .second], from: parsed)

        #expect(c.year == 2025 && c.month == 2 && c.day == 13)
        #expect(c.hour == 21 && c.minute == 23 && c.second == 39)
    }

    @Test func zSuffixedTimestampsParse() throws {
        let parsed = try #require(FR24Date.parse("2023-11-08T10:10:00Z"))
        #expect(parsed == Date(timeIntervalSince1970: 1_699_438_200))
    }

    /// Both shapes must land on the same scale, or a flight's elapsed time comes
    /// out hours off. FR24's own example says this leg took 4577 seconds.
    @Test func bothShapesShareOneClock() throws {
        let takeoff = try #require(FR24Date.parse("2025-02-13T21:23:39"))
        let landed = try #require(FR24Date.parse("2025-02-13T22:39:56"))
        #expect(landed.timeIntervalSince(takeoff) == 4577)
    }

    @Test func queryFormatRoundTrips() throws {
        let date = try #require(FR24Date.parse("2025-02-13T21:23:39"))
        #expect(FR24Date.query(date) == "2025-02-13T21:23:39")
        #expect(FR24Date.parse(FR24Date.query(date)) == date)
    }

    @Test func emptyTimestampsAreNil() {
        #expect(FR24Date.parse(nil) == nil)
        #expect(FR24Date.parse("") == nil)
    }

    // MARK: Decoding

    /// Guards the CodingKeys: a typo silently nulls a field rather than throwing,
    /// so these assert against FR24's own documented example payload.
    @Test func decodesLivePosition() throws {
        let json = Data("""
        {"fr24_id":"321a0cc3","flight":"AF1463","callsign":"AFR1463","lat":-0.08806,
        "lon":-168.07118,"track":219,"alt":38000,"gspeed":500,"vspeed":340,
        "squawk":"6135","timestamp":"2023-11-08T10:10:00Z","source":"ADSB",
        "hex":"394C19","type":"A321","reg":"F-GTAZ","painted_as":"THY",
        "operating_as":"THY","orig_iata":"ARN","orig_icao":"ESSA","dest_iata":"LHR",
        "dest_icao":"EGLL","eta":"2023-11-08T16:12:24Z"}
        """.utf8)

        let p = try JSONDecoder().decode(FR24Position.self, from: json)
        #expect(p.flight == "AF1463")
        #expect(p.origIata == "ARN")
        #expect(p.destIata == "LHR")
        #expect(p.paintedAs == "THY")
        #expect(p.eta == "2023-11-08T16:12:24Z")
        // Feet and knots — not the metres and km/h AviationStack sent.
        #expect(p.alt == 38000)
        #expect(p.gspeed == 500)
    }

    @Test func decodesFlightSummary() throws {
        let json = Data("""
        {"fr24_id":"391e1d99","flight":"RR9407","operating_as":"RYS","painted_as":"RYS",
        "orig_icao":"LZIB","orig_iata":"BTS","datetime_takeoff":"2025-02-13T21:23:39",
        "dest_icao":"LGTS","dest_iata":"SKG","dest_iata_actual":"SKG",
        "datetime_landed":"2025-02-13T22:39:56","first_seen":"2025-02-13T20:54:19",
        "last_seen":"2025-02-13T22:43:49","flight_ended":true}
        """.utf8)

        let s = try JSONDecoder().decode(FR24Summary.self, from: json)
        #expect(s.flight == "RR9407")
        #expect(s.origIata == "BTS")
        #expect(s.destIata == "SKG")
        #expect(s.datetimeTakeoff == "2025-02-13T21:23:39")
        #expect(s.datetimeLanded == "2025-02-13T22:39:56")
        #expect(s.flightEnded == true)
    }

    /// The airport endpoint exists solely to learn what clock an airport runs on.
    @Test func decodesAirportTimezone() throws {
        let json = Data("""
        {"name":"Stockholm Arlanda Airport","iata":"ARN","icao":"ESSA","lon":17.94,
        "lat":59.65,"elevation":137,"country":{"code":"SE","name":"SWEDEN"},
        "city":"Stockholm","state":null,"timezone":{"name":"Europe/Stockholm","offset":7200}}
        """.utf8)

        let a = try JSONDecoder().decode(FR24Airport.self, from: json)
        #expect(a.name == "Stockholm Arlanda Airport")
        #expect(a.iata == "ARN")
        #expect(a.timezone?.name == "Europe/Stockholm")
        #expect(TimeZone(identifier: a.timezone?.name ?? "") != nil)
    }

    // MARK: Tracking reach

    /// FR24 is blind to the future: a flight isn't in its data until it flies.
    /// Calling before then is guaranteed to return nothing, so we don't.
    @Test func futureFlightIsOutOfReach() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let tomorrow = flight(departs: now.addingTimeInterval(24 * 3600))
        #expect(FlightTracker.isWithinTrackingReach(tomorrow, now: now) == false)
    }

    /// Departure time here is whatever the user typed, and aircraft push back
    /// early, so the window opens an hour ahead of it.
    @Test func reachOpensAnHourBeforeDeparture() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let soon = flight(departs: now.addingTimeInterval(30 * 60))
        #expect(FlightTracker.isWithinTrackingReach(soon, now: now))
    }

    /// The mirror image of the AviationStack rule: past flights are FR24's
    /// strength, and stay reachable indefinitely.
    @Test func pastFlightStaysInReach() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let lastMonth = flight(departs: now.addingTimeInterval(-30 * 24 * 3600))
        #expect(FlightTracker.isWithinTrackingReach(lastMonth, now: now))
    }

    /// FR24's flight history begins 2022-06-01; anything older can't be answered.
    @Test func flightBeforeHistoryFloorIsOutOfReach() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let ancient = flight(departs: Date(timeIntervalSince1970: 1_600_000_000)) // 2020
        #expect(FlightTracker.isWithinTrackingReach(ancient, now: now) == false)
    }

    // MARK: Applying a snapshot

    /// FR24 publishes no schedule, so the leg's own times stand in for one — and
    /// the delay is the gap between what the traveler planned and what flew.
    @Test func delayIsDerivedFromTheLegsOwnTimes() {
        let departs = Date(timeIntervalSince1970: 1_800_000_000)
        let seg = flight(departs: departs, arrives: departs.addingTimeInterval(5 * 3600))

        let record = FlightStatusRecord(segmentID: seg.id)
        record.apply(FR24Snapshot(
            phase: .landed,
            flightIata: "UA523",
            airlineName: "United Airlines",
            takeoff: departs.addingTimeInterval(25 * 60),   // 25 minutes late
            landed: departs.addingTimeInterval(5 * 3600 + 10 * 60), // 10 late
            eta: nil,
            position: nil
        ), for: seg)

        #expect(record.phase == .landed)
        #expect(record.isFinal)
        #expect(record.depScheduled == departs)
        #expect(record.depDelayMinutes == 25)
        #expect(record.arrDelayMinutes == 10)
        #expect(record.airlineName == "United Airlines")
    }

    /// Leaving early is not a delay and must never render as one.
    @Test func earlyDepartureIsNotADelay() {
        let departs = Date(timeIntervalSince1970: 1_800_000_000)
        let seg = flight(departs: departs)

        let record = FlightStatusRecord(segmentID: seg.id)
        record.apply(FR24Snapshot(
            phase: .landed, flightIata: "UA523", airlineName: nil,
            takeoff: departs.addingTimeInterval(-8 * 60),   // 8 minutes early
            landed: departs.addingTimeInterval(4 * 3600),
            eta: nil, position: nil
        ), for: seg)

        #expect(record.depDelayMinutes == nil)
    }

    /// FR24 has no gate/terminal/baggage data at any tier. Assert that plainly, so
    /// nobody later mistakes an empty chip for a bug in the parsing.
    @Test func gateTerminalAndBaggageAreNeverPopulated() {
        let seg = flight(departs: Date(timeIntervalSince1970: 1_800_000_000))
        let record = FlightStatusRecord(segmentID: seg.id)

        record.apply(FR24Snapshot(
            phase: .active, flightIata: "UA523", airlineName: nil,
            takeoff: nil, landed: nil, eta: nil, position: nil
        ), for: seg)

        #expect(record.depTerminal == nil)
        #expect(record.depGate == nil)
        #expect(record.arrTerminal == nil)
        #expect(record.arrGate == nil)
        #expect(record.arrBaggage == nil)
    }

    /// Telemetry is carried through in FR24's units (feet, knots) and only exists
    /// while a position row does.
    @Test func airborneSnapshotCarriesTelemetry() {
        let departs = Date(timeIntervalSince1970: 1_800_000_000)
        let seg = flight(departs: departs)
        let eta = departs.addingTimeInterval(4 * 3600)

        let position = FR24Position(
            fr24ID: "abc", flight: "UA523", callsign: "UAL523",
            lat: 37.5, lon: -100.2, track: 88, alt: 36000, gspeed: 470, vspeed: 0,
            timestamp: "2027-01-15T12:00:00Z", origIata: "SFO", destIata: "JFK",
            paintedAs: "UAL", operatingAs: "UAL", eta: nil
        )

        let record = FlightStatusRecord(segmentID: seg.id)
        record.apply(FR24Snapshot(
            phase: .active, flightIata: "UA523", airlineName: "United Airlines",
            takeoff: departs, landed: nil, eta: eta, position: position
        ), for: seg)

        #expect(record.phase == .active)
        #expect(record.isFinal == false)
        #expect(record.hasLivePosition)
        #expect(record.liveAltitude == 36000)  // feet
        #expect(record.liveSpeed == 470)       // knots
        #expect(record.liveDirection == 88)
        // Still in the air, so the ETA is the arrival estimate.
        #expect(record.arrEstimated == eta)
        #expect(record.arrActual == nil)
    }

    /// Once it's down, the landing time is the answer and the ETA is stale noise.
    @Test func landingSupersedesTheETA() {
        let departs = Date(timeIntervalSince1970: 1_800_000_000)
        let seg = flight(departs: departs, arrives: departs.addingTimeInterval(5 * 3600))
        let landed = departs.addingTimeInterval(5 * 3600)

        let record = FlightStatusRecord(segmentID: seg.id)
        record.apply(FR24Snapshot(
            phase: .landed, flightIata: "UA523", airlineName: nil,
            takeoff: departs, landed: landed,
            eta: departs.addingTimeInterval(9 * 3600), // stale
            position: nil
        ), for: seg)

        #expect(record.arrActual == landed)
        #expect(record.arrEstimated == nil)
    }

    /// A landed record is frozen and displayable forever; that's what makes past
    /// flights free to show.
    @Test func finalRecordStaysDisplayable() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let seg = flight(departs: now.addingTimeInterval(-60 * 24 * 3600))

        let record = FlightStatusRecord(segmentID: seg.id)
        record.apply(FR24Snapshot(
            phase: .landed, flightIata: "UA523", airlineName: nil,
            takeoff: seg.departureDate, landed: seg.departureDate.addingTimeInterval(5 * 3600),
            eta: nil, position: nil
        ), for: seg)

        #expect(record.isFinal)
        #expect(record.isDisplayable(for: seg, now: now))
    }

    /// A negative cache must never drive the UI.
    @Test func emptyRecordIsNotDisplayable() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let seg = flight(departs: now.addingTimeInterval(-3600))

        let record = FlightStatusRecord(segmentID: seg.id)
        record.markEmpty()

        #expect(record.didFindData == false)
        #expect(record.isDisplayable(for: seg, now: now) == false)
    }
}
