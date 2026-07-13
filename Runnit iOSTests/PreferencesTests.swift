//
//  PreferencesTests.swift
//  Runnit iOSTests
//
//  Covers appearance + distance-unit preference mapping. Distance-unit tests
//  mutate the shared UserDefaults, so the suite is serialized and each test
//  restores the key it touched.
//

import SwiftUI
import Testing
@testable import Runnit_iOS

@MainActor
struct AppAppearanceTests {

    @Test func colorSchemeMapping() {
        #expect(AppAppearance.system.colorScheme == nil)
        #expect(AppAppearance.light.colorScheme == .light)
        #expect(AppAppearance.dark.colorScheme == .dark)
    }

    @Test func labelsCoverEveryCase() {
        #expect(AppAppearance.allCases.map(\.label) == ["System", "Light", "Dark"])
    }
}

@MainActor
@Suite(.serialized)
struct DistanceUnitTests {

    /// Run `body` with the distance-unit preference set to `raw`, restoring the
    /// previous value afterwards.
    private func withDistanceUnit(_ raw: String?, _ body: () -> Void) {
        let defaults = UserDefaults.standard
        let previous = defaults.string(forKey: PrefKey.distanceUnit)
        defer {
            if let previous {
                defaults.set(previous, forKey: PrefKey.distanceUnit)
            } else {
                defaults.removeObject(forKey: PrefKey.distanceUnit)
            }
        }
        if let raw {
            defaults.set(raw, forKey: PrefKey.distanceUnit)
        } else {
            defaults.removeObject(forKey: PrefKey.distanceUnit)
        }
        body()
    }

    @Test func currentReflectsStoredValue() {
        withDistanceUnit("kilometers") { #expect(DistanceUnit.current == .kilometers) }
        withDistanceUnit("miles") { #expect(DistanceUnit.current == .miles) }
    }

    @Test func currentDefaultsToAutomatic() {
        withDistanceUnit(nil) { #expect(DistanceUnit.current == .automatic) }
        withDistanceUnit("nonsense") { #expect(DistanceUnit.current == .automatic) }
    }
}
