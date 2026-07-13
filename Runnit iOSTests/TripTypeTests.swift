//
//  TripTypeTests.swift
//  Runnit iOSTests
//
//  Covers the mode enum's display + capability metadata.
//

import Testing
@testable import Runnit_iOS

@MainActor
struct TripTypeTests {

    @Test func allCasesAreIdentifiedByRawValue() {
        #expect(TripType.allCases.map(\.id) == ["flight", "train", "roadTrip", "other"])
    }

    @Test func onlyFlightAndTrainAreScheduledTransit() {
        #expect(TripType.flight.isScheduledTransit)
        #expect(TripType.train.isScheduledTransit)
        #expect(!TripType.roadTrip.isScheduledTransit)
        #expect(!TripType.other.isScheduledTransit)
    }

    @Test func labelsAreHumanReadable() {
        #expect(TripType.flight.label == "Flight")
        #expect(TripType.roadTrip.label == "Road Trip")
    }

    @Test func numberLabelVariesByMode() {
        #expect(TripType.flight.numberLabel == "Flight Number")
        #expect(TripType.train.numberLabel == "Train Number")
        #expect(TripType.roadTrip.numberLabel == "Number")
    }

    @Test func boardingLabelVariesByMode() {
        #expect(TripType.flight.boardingLabel == "Gate / Terminal")
        #expect(TripType.train.boardingLabel == "Platform")
        #expect(TripType.other.boardingLabel == "Boarding")
    }

    @Test func everyModeHasASymbol() {
        for type in TripType.allCases {
            #expect(!type.symbol.isEmpty)
        }
    }
}
