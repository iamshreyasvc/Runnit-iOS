//
//  PlaceTests.swift
//  Runnit iOSTests
//
//  Covers the pure value-type behaviour on Place: flag derivation, display
//  labels, and coordinate bridging.
//

import CoreLocation
import Testing
@testable import Runnit_iOS

@MainActor
struct PlaceTests {

    @Test func derivesFlagFromIsoCode() {
        #expect(Place.sfo.flag == "🇺🇸")
        #expect(Place.lhr.flag == "🇬🇧")
    }

    @Test func flagIsNilWithoutIsoCode() {
        let p = Place(name: "Nowhere", latitude: 0, longitude: 0)
        #expect(p.flag == nil)
    }

    @Test func flagIsNilForMalformedIsoCode() {
        let p = Place(name: "Nowhere", latitude: 0, longitude: 0, isoCountryCode: "USA")
        #expect(p.flag == nil)
    }

    @Test func displayNamePrefersName() {
        #expect(Place.sfo.displayName == "San Francisco Intl (SFO)")
    }

    @Test func displayNameFallsBackToLocality() {
        let p = Place(name: "", latitude: 0, longitude: 0, locality: "Reykjavík")
        #expect(p.displayName == "Reykjavík")
    }

    @Test func displayNameFallsBackToUnknown() {
        let p = Place(name: "", latitude: 0, longitude: 0)
        #expect(p.displayName == "Unknown")
    }

    @Test func coordinateMirrorsStoredLatLong() {
        let coord = Place.sfo.coordinate
        #expect(coord.latitude == Place.sfo.latitude)
        #expect(coord.longitude == Place.sfo.longitude)
    }
}
