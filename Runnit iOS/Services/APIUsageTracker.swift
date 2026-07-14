//
//  APIUsageTracker.swift
//  Runnit iOS
//
//  Tracks how many AviationStack calls we've made this calendar month against
//  the free tier's 100-call cap. Backed by UserDefaults (keyed per month, so it
//  resets automatically), surfaced in Account, and drives the home-screen
//  "limit reached" banner. FlightTracker consults `canSpend` before every call.
//

import Foundation
import Observation

@MainActor
@Observable
final class APIUsageTracker {
    /// Free-tier monthly cap.
    static let limit = 100

    private let defaults: UserDefaults
    /// Set when the API itself told us the limit is reached, even if our local
    /// count disagrees (e.g. the key is shared with another app).
    private(set) var apiReportedLimit: Bool

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.apiReportedLimit = defaults.bool(forKey: Self.reportedKey(for: Date()))
    }

    // MARK: Counts

    var used: Int {
        defaults.integer(forKey: Self.countKey(for: Date()))
    }

    var remaining: Int { max(0, Self.limit - used) }

    var isExhausted: Bool { apiReportedLimit || remaining <= 0 }

    /// Whether a call is allowed right now.
    var canSpend: Bool { !isExhausted }

    // MARK: Mutations

    /// Record one successful/attempted call against this month's budget.
    func record() {
        let key = Self.countKey(for: Date())
        defaults.set(defaults.integer(forKey: key) + 1, forKey: key)
    }

    /// The API reported the monthly limit is reached — latch it for this month.
    func markLimitReached() {
        apiReportedLimit = true
        defaults.set(true, forKey: Self.reportedKey(for: Date()))
        // Also pin the local count to the cap so the readout matches reality.
        defaults.set(Self.limit, forKey: Self.countKey(for: Date()))
    }

    // MARK: Keys (per calendar month; dots avoided per PrefKey convention note)

    private static func monthStamp(for date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month], from: date)
        return String(format: "%04d%02d", c.year ?? 0, c.month ?? 0)
    }
    private static func countKey(for date: Date) -> String { "runnitApiUsage\(monthStamp(for: date))" }
    private static func reportedKey(for date: Date) -> String { "runnitApiLimit\(monthStamp(for: date))" }
}
