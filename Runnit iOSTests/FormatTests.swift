//
//  FormatTests.swift
//  Runnit iOSTests
//
//  Covers the human-readable formatting helpers. Distance honors the shared
//  distance-unit preference, so the suite is serialized and restores it.
//

import Foundation
import Testing
@testable import Runnit_iOS

@MainActor
@Suite(.serialized)
struct FormatTests {

    private func withDistanceUnit(_ raw: String, _ body: () -> Void) {
        let defaults = UserDefaults.standard
        let previous = defaults.string(forKey: PrefKey.distanceUnit)
        defer {
            if let previous {
                defaults.set(previous, forKey: PrefKey.distanceUnit)
            } else {
                defaults.removeObject(forKey: PrefKey.distanceUnit)
            }
        }
        defaults.set(raw, forKey: PrefKey.distanceUnit)
        body()
    }

    @Test func distanceInKilometers() {
        withDistanceUnit("kilometers") {
            let text = Format.distance(5_000)
            #expect(text.contains("km"))
            #expect(text.contains("5"))
        }
    }

    @Test func distanceInMiles() {
        withDistanceUnit("miles") {
            let text = Format.distance(1_609)   // ~1 mile
            #expect(text.contains("mi"))
        }
    }

    @Test func durationCombinesHoursAndMinutes() {
        // 5 hr 20 min.
        let text = Format.duration(5 * 3_600 + 20 * 60)
        #expect(text.contains("hr"))
        #expect(text.contains("min"))
    }

    @Test func durationClampsNegativeToZero() {
        // Should not crash or produce a negative reading.
        let text = Format.duration(-100)
        #expect(!text.contains("-"))
    }
}
