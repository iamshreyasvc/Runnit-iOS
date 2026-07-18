//
//  TrainAutofillTests.swift
//  Runnit iOSTests
//
//  Covers the network-free parts of Indian Railways auto-fill: erail's delimited
//  payload parser, the running-days mask, and train-number normalisation.
//

import Foundation
import Testing
@testable import Runnit_iOS

struct TrainAutofillTests {

    // A real getTrains.aspx payload for 12608 (Lalbagh SF Express, daily),
    // truncated after the fields the parser reads.
    private let lalbagh = "~~~~~~2026-7-18-8-41-7~~~^12608~LALBAGH SF EXP~Ksr Bengaluru~SBC~Mgr Chennai Ctr~MAS~Ksr Bengaluru~SBC~Mgr Chennai Ctr~MAS~06.25~12.20~05.55~1111111~~~~~~~~000100101000000~0~0~1~1~06.25~12.20~13~1111111~First~Last~SUPERFAST"

    // 20608 (MAS Vande Bharat, runs every day except Tuesday), MYS → MAS.
    private let vandeBharat = "~~~~~~2026-7-18-8-43-8~~~^20608~MAS VANDEBHARAT~Mysore Jn~MYS~Mgr Chennai Ctr~MAS~Mysore Jn~MYS~Mgr Chennai Ctr~MAS~13.05~19.20~06.15~1101111~~~~~~~~000100000010000~0~0~0~1~13.05~19.20~4~1101111~First~Last~SUPERFAST"

    // MARK: Parsing

    @Test func parsesTrainSchedule() {
        let r = ErailClient.parse(lalbagh)
        #expect(r?.trainNumber == "12608")
        #expect(r?.trainName == "LALBAGH SF EXP")
        #expect(r?.sourceName == "Ksr Bengaluru")
        #expect(r?.sourceCode == "SBC")
        #expect(r?.destinationName == "Mgr Chennai Ctr")
        #expect(r?.destinationCode == "MAS")
        #expect(r?.departureTime == "06.25")
        #expect(r?.arrivalTime == "12.20")
        #expect(r?.duration == "05.55")
        #expect(r?.runningDays == "1111111")
    }

    @Test func trainNotFoundReturnsNil() {
        #expect(ErailClient.parse("~~~~~Train not found") == nil)
        #expect(ErailClient.parse("") == nil)
        #expect(ErailClient.parse("garbage with no caret") == nil)
    }

    // MARK: Running days (Sunday-first mask, index = Swift weekday − 1)

    @Test func dailyTrainRunsEveryDay() {
        let r = ErailClient.parse(lalbagh)!
        #expect(r.runs(on: date("2026-07-19"))) // Sunday
        #expect(r.runs(on: date("2026-07-21"))) // Tuesday
    }

    @Test func exceptTuesdayTrainSkipsTuesday() {
        let r = ErailClient.parse(vandeBharat)!
        #expect(r.runs(on: date("2026-07-20")))      // Monday — runs
        #expect(r.runs(on: date("2026-07-21")) == false) // Tuesday — off
        #expect(r.runs(on: date("2026-07-19")))      // Sunday — runs
    }

    @Test func malformedMaskAssumesRuns() {
        var r = ErailClient.parse(lalbagh)!
        r.runningDays = "11"
        #expect(r.runs(on: date("2026-07-21")))
    }

    // MARK: Duration

    @Test func durationParsesToInterval() {
        #expect(ErailClient.parse(lalbagh)!.durationInterval == 5 * 3600 + 55 * 60)
        #expect(ErailClient.parse(vandeBharat)!.durationInterval == 6 * 3600 + 15 * 60)
    }

    // MARK: Number normalisation

    @Test func normalisesFiveDigitNumbers() {
        #expect(TrainAutofill.normalizedNumber(from: "12608") == "12608")
        #expect(TrainAutofill.normalizedNumber(from: " 12608 ") == "12608")
        #expect(TrainAutofill.normalizedNumber(from: "AA100") == nil)
        #expect(TrainAutofill.normalizedNumber(from: "1234") == nil)
        #expect(TrainAutofill.normalizedNumber(from: "123456") == nil)
    }

    // MARK: Helpers

    /// A date at noon IST on the given yyyy-MM-dd, so the running-days weekday
    /// (computed in Asia/Kolkata) is unambiguous.
    private func date(_ ymd: String) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TrainAutofill.indiaTimeZone
        let p = ymd.split(separator: "-").map { Int($0)! }
        return cal.date(from: DateComponents(year: p[0], month: p[1], day: p[2], hour: 12))!
    }
}
