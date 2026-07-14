//
//  FlightTimeTests.swift
//  Runnit iOSTests
//
//  AviationStack emits each airport's local wall clock and staples a "+00:00"
//  onto it. Read as UTC, a 1:15 PM departure from LAX becomes 6:15 AM — seven
//  hours wrong. These tests pin the real DL 395 payload that exposed it.
//

import Foundation
import Testing
@testable import Runnit_iOS

@MainActor
struct FlightTimeTests {

    // The exact payload the API returned for DL 395, LAX → ATL, 14 Jul 2026.
    private let departureRaw = "2026-07-14T13:15:00+00:00"
    private let departureZone = "America/Los_Angeles"
    private let arrivalRaw = "2026-07-14T20:56:00+00:00"
    private let arrivalZone = "America/New_York"

    /// The wall clock at `zone` for an instant, e.g. "Jul 14 1:15 PM".
    private func clock(_ date: Date, at zone: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d h:mm a"
        formatter.timeZone = TimeZone(identifier: zone)
        return formatter.string(from: date)
    }

    @Test func flightTimesAreReadOnTheAirportsClock() throws {
        let departure = try #require(ASDate.parse(departureRaw, timeZone: departureZone))
        let arrival = try #require(ASDate.parse(arrivalRaw, timeZone: arrivalZone))

        #expect(clock(departure, at: departureZone) == "Jul 14 1:15 PM")
        #expect(clock(arrival, at: arrivalZone) == "Jul 14 8:56 PM")
    }

    @Test func theBlockTimeIsPhysicallyPossible() throws {
        let departure = try #require(ASDate.parse(departureRaw, timeZone: departureZone))
        let arrival = try #require(ASDate.parse(arrivalRaw, timeZone: arrivalZone))

        // LAX → ATL is about 4h40. Trusting the "+00:00" gave 7h41.
        let hours = arrival.timeIntervalSince(departure) / 3600
        #expect(hours > 4.5 && hours < 5.0)
    }

    @Test func trustingTheOffsetIsSevenHoursWrong() throws {
        // Documents the bug: this is exactly the "6:15 AM" that was on screen.
        let naive = try #require(ASDate.parse(departureRaw))
        let correct = try #require(ASDate.parse(departureRaw, timeZone: departureZone))

        #expect(clock(naive, at: departureZone) == "Jul 14 6:15 AM")
        #expect(correct.timeIntervalSince(naive) == 7 * 3600)
    }

    @Test func parsingFallsBackWhenTheZoneIsMissingOrBogus() {
        let naive = ASDate.parse(departureRaw)
        #expect(ASDate.parse(departureRaw, timeZone: nil) == naive)
        #expect(ASDate.parse(departureRaw, timeZone: "Not/AZone") == naive)
        #expect(ASDate.parse(nil, timeZone: departureZone) == nil)
    }

    @Test func halfHourOffsetZonesRoundTrip() throws {
        let date = try #require(ASDate.parse("2026-07-14T09:30:00+00:00", timeZone: "Asia/Kolkata"))
        #expect(clock(date, at: "Asia/Kolkata") == "Jul 14 9:30 AM")
    }

    // MARK: Presentation

    @Test func aRecordCarriesEachEndpointsZone() throws {
        let record = FlightStatusRecord(segmentID: UUID())
        record.depTimeZoneID = departureZone
        record.arrTimeZoneID = arrivalZone

        #expect(record.depTimeZone == TimeZone(identifier: departureZone))
        #expect(record.arrTimeZone == TimeZone(identifier: arrivalZone))
    }

    @Test func zoneShiftNamesTheChangeAcrossALeg() throws {
        let departure = try #require(ASDate.parse(departureRaw, timeZone: departureZone))
        let arrival = try #require(ASDate.parse(arrivalRaw, timeZone: arrivalZone))

        let shift = Format.zoneShift(
            from: TimeZone(identifier: departureZone), to: TimeZone(identifier: arrivalZone),
            departing: departure, arriving: arrival
        )
        #expect(shift == "PDT → EDT · 3 hr ahead")
    }

    @Test func noShiftIsReportedWithinOneZone() throws {
        let departure = try #require(ASDate.parse(departureRaw, timeZone: departureZone))
        let zone = TimeZone(identifier: departureZone)

        // Same clock at both ends — there is nothing to warn about.
        #expect(Format.zoneShift(from: zone, to: zone,
                                 departing: departure, arriving: departure) == nil)
        // And an unknown zone can't be compared.
        #expect(Format.zoneShift(from: zone, to: nil,
                                 departing: departure, arriving: departure) == nil)
    }

    // MARK: Picking the right instance of a flight number

    /// The DL 537 payload: departs ATL 21:59 ET on Jul 14 — which is 01:59 UTC on
    /// Jul 15. Matching calendar days in UTC rejected it, and the tracker cached
    /// that as "no live data found".
    private func dl537() throws -> ASFlight {
        let json = """
        {"data":[
          {"flight_date":"2026-07-14","flight_status":"scheduled",
           "departure":{"airport":"Hartsfield-jackson Atlanta International",
                        "timezone":"America/New_York","iata":"ATL",
                        "terminal":"S","gate":"C2",
                        "scheduled":"2026-07-14T21:59:00+00:00"},
           "arrival":{"airport":"Ronald Reagan Washington National",
                      "timezone":"America/New_York","iata":"DCA",
                      "terminal":"2","gate":"B18",
                      "scheduled":"2026-07-14T23:52:00+00:00"},
           "airline":{"name":"Delta"},"flight":{"iata":"DL537"}}
        ]}
        """
        let decoded = try JSONDecoder().decode(ASResponse.self, from: Data(json.utf8))
        return try #require(decoded.data?.first)
    }

    @Test func anEveningDepartureIsMatchedOnTheAirportsDay() throws {
        let flight = try dl537()
        let target = try #require(ASDate.parse("2026-07-14T21:59:00+00:00",
                                               timeZone: "America/New_York"))

        // Sanity: this instant really does fall on the *next* day in UTC — which is
        // precisely why the old UTC-day comparison threw the flight away.
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = try #require(TimeZone(identifier: "UTC"))
        #expect(utc.component(.day, from: target) == 15)

        #expect(AviationStackClient.isSameFlightDay(flight, as: target))
    }

    @Test func aDifferentDaysInstanceIsStillRejected() throws {
        let flight = try dl537()
        // The same flight number, but the traveler's leg is a day later.
        let target = try #require(ASDate.parse("2026-07-15T21:59:00+00:00",
                                               timeZone: "America/New_York"))
        #expect(!AviationStackClient.isSameFlightDay(flight, as: target))
    }

    @Test func theLiveGateIsWhatTheAPIReports() throws {
        let flight = try dl537()
        // Whatever the traveler typed when booking, this is the gate that counts.
        #expect(flight.departure?.gate == "C2")
        #expect(flight.departure?.terminal == "S")
    }

    @Test func timesRenderOnTheZoneTheyAreGiven() throws {
        let departure = try #require(ASDate.parse(departureRaw, timeZone: departureZone))

        // The same instant, on two clocks — this is the whole point.
        let atLAX = Format.time(departure, in: TimeZone(identifier: departureZone))
        let atATL = Format.time(departure, in: TimeZone(identifier: arrivalZone))
        #expect(atLAX != atATL)
        #expect(Format.zone(TimeZone(identifier: departureZone), at: departure) == "PDT")
    }
}
