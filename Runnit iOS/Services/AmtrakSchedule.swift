//
//  AmtrakSchedule.swift
//  Runnit iOS
//
//  The bundled Amtrak timetable — the US-train counterpart to erail's by-number
//  schedule, except it's a local dataset rather than a network call. Generated
//  from Amtrak's free GTFS feed (Scripts/generate_amtrak_data.py) into
//  `AmtrakSchedule.json`: each train number maps to the halts it makes, with
//  scheduled times, the days it runs, and the validity window.
//
//  GTFS publishes a real forward timetable (valid ~a year out), so — like erail
//  and unlike a live-tracking API — a *future* travel date fills correctly.
//
//  Two GTFS quirks the times encode, both handled here:
//    • Stop times are cumulative hours from the origin's service day, so a value
//      can exceed 24:00 (e.g. "25:09" = 01:09 the next day, "56:35" = 08:35 two
//      days on). That makes overnight and multi-day trains fall out naturally.
//    • Each stop's time is in that stop's *own* timezone, since one train crosses
//      several — so departure is stamped in the origin's zone, arrival in the
//      destination's.
//

import Foundation

nonisolated struct AmtrakSchedule: Decodable {
    /// One halt: a station code and its cumulative "H:MM:SS" arrival/departure
    /// (H may exceed 24 — see the file header).
    struct Stop: Decodable, Equatable {
        let code: String
        let arr: String
        let dep: String
    }

    /// One service pattern for a train number — the canonical (fullest) trip, its
    /// running-days mask, and the dates it's valid between.
    struct Variant: Decodable, Equatable {
        /// The route's public name, e.g. "Sunset Limited" — shown as the train name.
        let name: String
        let headsign: String
        /// GTFS shape id, keying `AmtrakShapes` for the real route geometry.
        let shapeId: String
        /// 7-character mask, Sunday-first (index = Swift weekday − 1); '1' = runs.
        let days: String
        /// Validity window, "YYYYMMDD" inclusive.
        let start: String
        let end: String
        /// Halts in travel order, origin first.
        let stops: [Stop]

        var origin: Stop? { stops.first }
        var destination: Stop? { stops.last }
    }

    /// Train number → its service variants (usually one).
    let trains: [String: [Variant]]

    // MARK: Loading

    /// The bundled timetable, parsed once. Empty if the resource is missing so a
    /// lookup simply misses rather than crashing.
    static let bundled: AmtrakSchedule = {
        guard let url = Bundle.main.url(forResource: "AmtrakSchedule", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: [Variant]].self, from: data)
        else { return AmtrakSchedule(trains: [:]) }
        return AmtrakSchedule(trains: decoded)
    }()

    // MARK: Lookup

    /// Normalise a typed Amtrak number to its digits, or `nil` if it clearly isn't
    /// one. Amtrak numbers are 1–4 digits, which is what keeps them from colliding
    /// with Indian Railways' 5-digit numbers at the autofill dispatch.
    static func normalizedNumber(from raw: String) -> String? {
        let digits = raw.filter(\.isNumber)
        return (1...4).contains(digits.count) ? digits : nil
    }

    /// The variant for a number on a given date: the one whose validity window
    /// covers the date, else the first known (so a fill still happens, flagged as
    /// not running). `nil` only when the number is unknown.
    func variant(forNumber number: String, on date: Date) -> Variant? {
        guard let variants = trains[number], !variants.isEmpty else { return nil }
        return variants.first { $0.covers(date) } ?? variants.first
    }

    /// Any variant for a number, ignoring the date — used for route geometry,
    /// which doesn't change day to day.
    func anyVariant(forNumber number: String) -> Variant? {
        trains[number]?.first
    }

    // MARK: - Time stamping (pure, unit-tested)

    /// Combine a stop's cumulative "H:MM(:SS)" time with the calendar day of
    /// `day`, in timezone `tz`, producing a correct instant. Hours ≥ 24 roll the
    /// date forward by whole days, so overnight and multi-day trains land right.
    static func stamp(cumulative hhmmss: String, onto day: Date, in tz: TimeZone) -> Date? {
        let parts = hhmmss.split(separator: ":")
        guard let rawHour = Int(parts.first ?? "") else { return nil }
        let minute = parts.count > 1 ? (Int(parts[1]) ?? 0) : 0
        let dayOffset = rawHour / 24
        let hour = rawHour % 24

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        let dayComps = Calendar.current.dateComponents([.year, .month, .day], from: day)
        var merged = DateComponents()
        merged.year = dayComps.year
        merged.month = dayComps.month
        merged.day = dayComps.day
        merged.hour = hour
        merged.minute = minute
        guard let base = cal.date(from: merged) else { return nil }
        return dayOffset == 0 ? base : cal.date(byAdding: .day, value: dayOffset, to: base)
    }
}

extension AmtrakSchedule.Variant {
    /// Whether the date falls within this variant's validity window. Returns true
    /// when the window is malformed, so a parsing quirk never hides a real train.
    func covers(_ date: Date) -> Bool {
        guard start.count == 8, end.count == 8 else { return true }
        let ymd = Self.compactYMD(date)
        return ymd >= start && ymd <= end
    }

    /// Whether this train runs on `date`, judged on the origin's local calendar day
    /// (`tz`). Returns true when the mask is malformed, so a quirk never hides a
    /// real train.
    func runs(on date: Date, in tz: TimeZone) -> Bool {
        guard days.count == 7 else { return true }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        let weekday = cal.component(.weekday, from: date) // 1 = Sunday … 7 = Saturday
        let index = days.index(days.startIndex, offsetBy: weekday - 1)
        return days[index] == "1"
    }

    /// "YYYYMMDD" for the device-local calendar day of `date`, matching how the
    /// generator wrote the validity window.
    static func compactYMD(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d%02d%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
