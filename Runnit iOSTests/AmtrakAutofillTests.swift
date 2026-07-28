//
//  AmtrakAutofillTests.swift
//  Runnit iOSTests
//
//  Covers the network-free parts of Amtrak auto-fill: the cumulative GTFS time
//  stamping (overnight and multi-day rollover, per-station timezone), the
//  running-days mask, validity windows, number normalisation, variant selection,
//  and the route-trimming geometry.
//

import Foundation
import CoreLocation
import Testing
@testable import Runnit_iOS

struct AmtrakAutofillTests {

    // MARK: Number normalisation

    @Test func normalisesOneToFourDigitNumbers() {
        #expect(AmtrakSchedule.normalizedNumber(from: "1") == "1")
        #expect(AmtrakSchedule.normalizedNumber(from: "307") == "307")
        #expect(AmtrakSchedule.normalizedNumber(from: " 1003 ") == "1003")
        #expect(AmtrakSchedule.normalizedNumber(from: "Train 88") == "88")
        // Five digits belong to Indian Railways; empty / too long are rejected.
        #expect(AmtrakSchedule.normalizedNumber(from: "12608") == nil)
        #expect(AmtrakSchedule.normalizedNumber(from: "") == nil)
        #expect(AmtrakSchedule.normalizedNumber(from: "abc") == nil)
    }

    // MARK: Cumulative time stamping

    @Test func stampsSameDayTimeInStationZone() {
        let chicago = TimeZone(identifier: "America/Chicago")!
        let stamped = AmtrakSchedule.stamp(cumulative: "10:00:00", onto: day(2026, 7, 20), in: chicago)
        #expect(stamped == instant(2026, 7, 20, 10, 0, chicago))
    }

    @Test func stampsOvernightRolloverPastMidnight() {
        // "25:09" = 01:09 the next calendar day.
        let chicago = TimeZone(identifier: "America/Chicago")!
        let stamped = AmtrakSchedule.stamp(cumulative: "25:09:00", onto: day(2026, 7, 20), in: chicago)
        #expect(stamped == instant(2026, 7, 21, 1, 9, chicago))
    }

    @Test func stampsMultiDayArrivalInDestinationZone() {
        // The Sunset Limited: New Orleans dep, Los Angeles arr at "56:35" — two
        // days on, 08:35 Pacific.
        let la = TimeZone(identifier: "America/Los_Angeles")!
        let stamped = AmtrakSchedule.stamp(cumulative: "56:35:00", onto: day(2026, 7, 20), in: la)
        #expect(stamped == instant(2026, 7, 22, 8, 35, la))
    }

    // MARK: Running days (Sunday-first mask, index = Swift weekday − 1)

    @Test func runsOnlyOnMaskedDays() {
        // "0101001": Sun off, Mon on, Tue off, Wed on, Thu off, Fri off, Sat on.
        let v = variant(days: "0101001")
        let chicago = TimeZone(identifier: "America/Chicago")!
        #expect(v.runs(on: day(2026, 7, 20), in: chicago))        // Monday — on
        #expect(v.runs(on: day(2026, 7, 21), in: chicago) == false) // Tuesday — off
        #expect(v.runs(on: day(2026, 7, 19), in: chicago) == false) // Sunday — off
        #expect(v.runs(on: day(2026, 7, 25), in: chicago))        // Saturday — on
    }

    @Test func malformedMaskAssumesRuns() {
        let v = variant(days: "11")
        #expect(v.runs(on: day(2026, 7, 21), in: TimeZone(identifier: "America/Chicago")!))
    }

    // MARK: Validity window

    @Test func coversDatesWithinWindowOnly() {
        let v = variant(days: "1111111", start: "20260719", end: "20270719")
        #expect(v.covers(day(2026, 7, 20)))
        #expect(v.covers(day(2025, 1, 1)) == false)
        #expect(v.covers(day(2028, 1, 1)) == false)
    }

    // MARK: Variant selection

    @Test func picksKnownNumberAndFallsBackOutsideWindow() {
        let schedule = AmtrakSchedule(trains: [
            "1": [variant(days: "1111111", start: "20260719", end: "20270719")]
        ])
        #expect(schedule.variant(forNumber: "1", on: day(2026, 8, 1)) != nil)
        // Outside the window it still returns the variant (so a fill happens,
        // flagged as not running), but an unknown number yields nil.
        #expect(schedule.variant(forNumber: "1", on: day(2030, 1, 1)) != nil)
        #expect(schedule.variant(forNumber: "999", on: day(2026, 8, 1)) == nil)
    }

    // MARK: Auto-fill outcome

    @Test func fillsFromInMemorySchedule() async {
        let schedule = AmtrakSchedule(trains: [
            "1": [variant(days: "0101001", name: "Sunset Limited")]
        ])
        let outcome = await TrainAutofill.run(trainNumber: "1", date: day(2026, 7, 20), amtrak: schedule)
        guard case .filled(let f) = outcome else {
            Issue.record("expected a filled outcome, got \(outcome)")
            return
        }
        #expect(f.trainName == "Sunset Limited")
        #expect(f.trainNumber == "1")
        #expect(f.runsOnDate) // Monday is in the mask
    }

    @Test func unknownNumberIsNotFound() async {
        let outcome = await TrainAutofill.run(trainNumber: "999", date: day(2026, 7, 20),
                                              amtrak: AmtrakSchedule(trains: [:]))
        #expect(outcome == .notFound)
    }

    // MARK: Route trimming

    @MainActor
    @Test func trimsRouteToTheRiddenStretch() {
        let line = (0..<10).map { CLLocationCoordinate2D(latitude: 40.0 + Double($0) * 0.1, longitude: -100.0) }
        let origin = place(40.1, -100.0)   // index 1
        let destination = place(40.6, -100.0) // index 6
        let trimmed = AmtrakRouteProvider.trim(line, from: origin, to: destination)
        #expect(trimmed?.count == 6) // indices 1…6 inclusive
        #expect(trimmed?.first?.latitude == 40.1)
        #expect(trimmed?.last?.latitude == 40.6)
    }

    @MainActor
    @Test func trimIsOrderIndependent() {
        let line = (0..<10).map { CLLocationCoordinate2D(latitude: 40.0 + Double($0) * 0.1, longitude: -100.0) }
        // Boarding later than alighting on the line still yields a valid slice.
        let trimmed = AmtrakRouteProvider.trim(line, from: place(40.6, -100.0), to: place(40.1, -100.0))
        #expect(trimmed?.count == 6)
    }

    @MainActor
    @Test func trimRejectsStationsOffTheRoute() {
        let line = (0..<10).map { CLLocationCoordinate2D(latitude: 40.0 + Double($0) * 0.1, longitude: -100.0) }
        // Far from every point (well past the 30 km tolerance).
        let trimmed = AmtrakRouteProvider.trim(line, from: place(50.0, -100.0), to: place(40.5, -100.0))
        #expect(trimmed == nil)
    }

    // MARK: Helpers

    private func variant(
        days: String,
        start: String = "20260101",
        end: String = "20301231",
        name: String = "Test Route"
    ) -> AmtrakSchedule.Variant {
        AmtrakSchedule.Variant(
            name: name, headsign: "", shapeId: "1", days: days, start: start, end: end,
            stops: [
                .init(code: "AAA", arr: "10:00:00", dep: "10:00:00"),
                .init(code: "BBB", arr: "18:00:00", dep: "18:00:00"),
            ]
        )
    }

    private func place(_ lat: Double, _ lon: Double) -> Place {
        Place(name: "P", latitude: lat, longitude: lon)
    }

    /// Noon on the given day, so a weekday computed in any US zone is unambiguous.
    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Chicago")!
        return cal.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }

    private func instant(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int, _ tz: TimeZone) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        return cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }
}
