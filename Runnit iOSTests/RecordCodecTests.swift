//
//  RecordCodecTests.swift
//  Runnit iOSTests
//
//  The mapping between the models and CKRecord is where a field goes missing
//  silently — it still compiles, still syncs, and the data just never arrives.
//  These tests push each model out to a record and back, asserting on the far
//  side. No network and no iCloud account: a CKRecord is an ordinary object.
//

import CloudKit
import Foundation
import Testing
@testable import Runnit_iOS

@MainActor
struct RecordCodecTests {

    private var zoneID: CKRecordZone.ID {
        CKRecordZone.ID(zoneName: "trip-test", ownerName: CKCurrentUserDefaultName)
    }

    // MARK: Zones

    @Test func zoneNameRoundTripsTripID() {
        let id = UUID()
        let name = RecordCodec.zoneName(for: id)
        #expect(name == "trip-\(id.uuidString)")
        #expect(RecordCodec.tripID(fromZoneName: name) == id)
    }

    @Test func foreignZoneNamesAreIgnored() {
        #expect(RecordCodec.tripID(fromZoneName: "_defaultZone") == nil)
        #expect(RecordCodec.tripID(fromZoneName: "trip-not-a-uuid") == nil)
    }

    // MARK: Trip

    @Test func tripRoundTripsEveryField() {
        let trip = Trip(origin: .sfo, destination: .jfk,
                        departureDate: Date(timeIntervalSince1970: 1_000_000),
                        arrivalDate: Date(timeIntervalSince1970: 1_020_000),
                        operatorName: "United", vehicleNumber: "UA 523",
                        boardingPoint: "Gate B12", seat: "14A",
                        confirmation: "ABC123", notes: "window seat")
        trip.title = "Work Trip"
        trip.type = .train

        let record = RecordCodec.record(for: trip, in: zoneID)
        let decoded = RecordCodec.makeTrip(from: record)

        #expect(decoded?.id == trip.id)
        #expect(decoded?.type == .train)
        #expect(decoded?.title == "Work Trip")
        #expect(decoded?.origin == trip.origin)
        #expect(decoded?.destination == trip.destination)
        #expect(decoded?.departureDate == trip.departureDate)
        #expect(decoded?.arrivalDate == trip.arrivalDate)
        #expect(decoded?.operatorName == "United")
        #expect(decoded?.vehicleNumber == "UA 523")
        #expect(decoded?.boardingPoint == "Gate B12")
        #expect(decoded?.seat == "14A")
        #expect(decoded?.confirmation == "ABC123")
        #expect(decoded?.notes == "window seat")
    }

    @Test func tripRecordUsesTheTripIDAsItsRecordName() {
        let trip = Trip(origin: .sfo, destination: .jfk)
        let record = RecordCodec.record(for: trip, in: zoneID)
        #expect(record.recordID.recordName == trip.id.uuidString)
        #expect(record.recordType == RecordType.trip)
    }

    /// A place carries country, locality and timezone resolved once at save
    /// time; losing them in transit would silently break the Passport and every
    /// airport-clock time on the receiving device.
    @Test func placeMetadataSurvivesTheRoundTrip() {
        let trip = Trip(origin: .sfo, destination: .jfk)
        let record = RecordCodec.record(for: trip, in: zoneID)
        let decoded = RecordCodec.makeTrip(from: record)

        #expect(decoded?.origin.isoCountryCode == Place.sfo.isoCountryCode)
        #expect(decoded?.origin.locality == Place.sfo.locality)
        #expect(decoded?.origin.timeZoneIdentifier == Place.sfo.timeZoneIdentifier)
        #expect(decoded?.origin.latitude == Place.sfo.latitude)
        #expect(decoded?.origin.longitude == Place.sfo.longitude)
    }

    /// Applying a record must not touch this device's own view of the trip —
    /// whether it's a sample, which zone it's in, or who owns it.
    @Test func applyingARecordLeavesLocalBookkeepingAlone() {
        let trip = Trip(origin: .sfo, destination: .jfk)
        let record = RecordCodec.record(for: trip, in: zoneID)

        trip.isSample = true
        trip.ownerName = "_someoneElse"
        trip.zoneName = "trip-keepme"
        RecordCodec.apply(record, to: trip)

        #expect(trip.isSample)
        #expect(trip.ownerName == "_someoneElse")
        #expect(trip.zoneName == "trip-keepme")
    }

    /// An applied record is by definition the server's version, so it must come
    /// back marked as synced — otherwise the next sweep uploads it straight back
    /// and two devices ping-pong the same trip forever.
    @Test func anAppliedRecordIsMarkedAsAlreadySynced() {
        let trip = Trip(origin: .sfo, destination: .jfk)
        let record = RecordCodec.record(for: trip, in: zoneID)

        let decoded = RecordCodec.makeTrip(from: record)
        #expect(decoded?.syncedAt == decoded?.updatedAt)
        #expect(decoded?.syncedAt != nil)

        let segment = TripSegment(origin: .sfo, destination: .jfk)
        let segmentRecord = RecordCodec.record(for: segment, tripID: UUID(), in: zoneID)
        #expect(RecordCodec.makeSegment(from: segmentRecord)?.syncedAt != nil)

        let status = FlightStatusRecord(segmentID: UUID())
        let statusRecord = RecordCodec.record(for: status, in: zoneID)
        #expect(RecordCodec.makeStatus(from: statusRecord)?.syncedAt != nil)
    }

    @Test func nilFieldsStayNilRatherThanBecomingEmptyStrings() {
        let trip = Trip(origin: .sfo, destination: .jfk)
        let decoded = RecordCodec.makeTrip(from: RecordCodec.record(for: trip, in: zoneID))

        #expect(decoded?.arrivalDate == nil)
        #expect(decoded?.operatorName == nil)
        #expect(decoded?.seat == nil)
        #expect(decoded?.notes == nil)
    }

    // MARK: Segment

    @Test func segmentRoundTripsEveryField() {
        let segment = TripSegment(type: .roadTrip, origin: .sfo, destination: .jfk,
                                  departureDate: Date(timeIntervalSince1970: 500),
                                  arrivalDate: Date(timeIntervalSince1970: 9_000),
                                  operatorName: "Eurostar", vehicleNumber: "ES 9024",
                                  boardingPoint: "Platform 3", seat: "22C",
                                  confirmation: "XYZ", order: 2)
        segment.routeSignature = "sig"
        segment.routeCheckedAt = Date(timeIntervalSince1970: 42)

        let tripID = UUID()
        let record = RecordCodec.record(for: segment, tripID: tripID, in: zoneID)
        let decoded = RecordCodec.makeSegment(from: record)

        #expect(decoded?.id == segment.id)
        #expect(decoded?.type == .roadTrip)
        #expect(decoded?.origin == segment.origin)
        #expect(decoded?.destination == segment.destination)
        #expect(decoded?.departureDate == segment.departureDate)
        #expect(decoded?.arrivalDate == segment.arrivalDate)
        #expect(decoded?.operatorName == "Eurostar")
        #expect(decoded?.vehicleNumber == "ES 9024")
        #expect(decoded?.boardingPoint == "Platform 3")
        #expect(decoded?.seat == "22C")
        #expect(decoded?.confirmation == "XYZ")
        #expect(decoded?.routeSignature == "sig")
        #expect(decoded?.routeCheckedAt == segment.routeCheckedAt)
        #expect(decoded?.order == 2)
        #expect(RecordCodec.tripID(ofSegmentRecord: record) == tripID)
    }

    @Test func segmentRecordParentsItsTripSoTheHierarchyShares() {
        let segment = TripSegment(origin: .sfo, destination: .jfk)
        let tripID = UUID()
        let record = RecordCodec.record(for: segment, tripID: tripID, in: zoneID)

        #expect(record.parent?.recordID.recordName == tripID.uuidString)
        #expect(record.parent?.recordID.zoneID == zoneID)
    }

    @Test func roadStopsSurviveWithCategoryAndNote() {
        let segment = TripSegment(type: .roadTrip, origin: .sfo, destination: .jfk)
        segment.stops = [
            RoadStop(place: .jfk, category: .coffee, note: "second breakfast"),
            RoadStop(place: .sfo, category: .gas)
        ]

        let record = RecordCodec.record(for: segment, tripID: UUID(), in: zoneID)
        let decoded = RecordCodec.makeSegment(from: record)

        #expect(decoded?.stops.count == 2)
        #expect(decoded?.stops.first?.category == .coffee)
        #expect(decoded?.stops.first?.note == "second breakfast")
        #expect(decoded?.stops.first?.place == Place.jfk)
        #expect(decoded?.stops.last?.category == .gas)
    }

    @Test func routePolylineSurvivesInOrder() {
        let segment = TripSegment(origin: .sfo, destination: .jfk)
        segment.routePolyline = (0..<50).map {
            RoutePoint(latitude: Double($0), longitude: Double($0) * -1)
        }

        let record = RecordCodec.record(for: segment, tripID: UUID(), in: zoneID)
        let decoded = RecordCodec.makeSegment(from: record)

        #expect(decoded?.routePolyline.count == 50)
        #expect(decoded?.routePolyline.first?.latitude == 0)
        #expect(decoded?.routePolyline.last?.latitude == 49)
        #expect(decoded?.routePolyline.last?.longitude == -49)
    }

    /// An enormous flown track must not take the whole trip's upload down with
    /// it. The field is dropped; the receiver recomputes the route locally.
    @Test func oversizedRoutePolylineIsDroppedNotFatal() {
        let segment = TripSegment(origin: .sfo, destination: .jfk)
        segment.routePolyline = (0..<60_000).map {
            RoutePoint(latitude: Double($0) / 1_000, longitude: Double($0) / -1_000)
        }

        let record = RecordCodec.record(for: segment, tripID: UUID(), in: zoneID)
        let decoded = RecordCodec.makeSegment(from: record)

        #expect(record["routePolyline"] as? Data == nil)
        #expect(decoded?.routePolyline.isEmpty == true)
        // The rest of the leg still made it.
        #expect(decoded?.origin == Place.sfo)
    }

    // MARK: Flight status

    @Test func flightStatusRoundTripsEveryField() {
        let segmentID = UUID()
        let status = FlightStatusRecord(segmentID: segmentID)
        status.statusRaw = FlightPhase.active.rawValue
        status.flightIata = "UA523"
        status.airlineName = "United"
        status.depScheduled = Date(timeIntervalSince1970: 100)
        status.depActual = Date(timeIntervalSince1970: 400)
        status.depTerminal = "1"
        status.depGate = "B12"
        status.depDelayMinutes = 55
        status.depTimeZoneID = "America/Los_Angeles"
        status.arrEstimated = Date(timeIntervalSince1970: 9_000)
        status.arrBaggage = "7"
        status.arrTimeZoneID = "America/New_York"
        status.liveLatitude = 41.5
        status.liveLongitude = -93.2
        status.liveAltitude = 35_000
        status.liveDirection = 91
        status.liveSpeed = 470
        status.liveUpdated = Date(timeIntervalSince1970: 800)

        let record = RecordCodec.record(for: status, in: zoneID)
        let decoded = RecordCodec.makeStatus(from: record)

        #expect(decoded?.segmentID == segmentID)
        #expect(decoded?.phase == .active)
        #expect(decoded?.flightIata == "UA523")
        #expect(decoded?.airlineName == "United")
        #expect(decoded?.depScheduled == status.depScheduled)
        #expect(decoded?.depActual == status.depActual)
        #expect(decoded?.depTerminal == "1")
        #expect(decoded?.depGate == "B12")
        #expect(decoded?.depDelayMinutes == 55)
        #expect(decoded?.depTimeZoneID == "America/Los_Angeles")
        #expect(decoded?.arrEstimated == status.arrEstimated)
        #expect(decoded?.arrBaggage == "7")
        #expect(decoded?.arrTimeZoneID == "America/New_York")
        #expect(decoded?.liveLatitude == 41.5)
        #expect(decoded?.liveLongitude == -93.2)
        #expect(decoded?.liveAltitude == 35_000)
        #expect(decoded?.liveDirection == 91)
        #expect(decoded?.liveSpeed == 470)
        #expect(decoded?.liveUpdated == status.liveUpdated)
    }

    /// CloudKit has no boolean field type, so these travel as ints — the exact
    /// place a "false" could quietly arrive as "true".
    @Test func booleanFlagsSurviveBothWays() {
        let status = FlightStatusRecord(segmentID: UUID())
        status.isFinal = true
        status.didFindData = false
        status.liveIsGround = false

        let decoded = RecordCodec.makeStatus(from: RecordCodec.record(for: status, in: zoneID))

        #expect(decoded?.isFinal == true)
        #expect(decoded?.didFindData == false)
        #expect(decoded?.liveIsGround == false)
    }

    @Test func unsetGroundFlagStaysNil() {
        let status = FlightStatusRecord(segmentID: UUID())
        let decoded = RecordCodec.makeStatus(from: RecordCodec.record(for: status, in: zoneID))
        #expect(decoded?.liveIsGround == nil)
    }

    @Test func statusRecordNameIsDistinctFromItsSegments() {
        let segmentID = UUID()
        let status = FlightStatusRecord(segmentID: segmentID)
        let record = RecordCodec.record(for: status, in: zoneID)

        #expect(record.recordID.recordName == "status-\(segmentID.uuidString)")
        #expect(record.recordID.recordName != segmentID.uuidString)
    }

    @Test func statusLearnsItsZoneOnDecode() {
        let status = FlightStatusRecord(segmentID: UUID())
        let decoded = RecordCodec.makeStatus(from: RecordCodec.record(for: status, in: zoneID))
        #expect(decoded?.zoneName == "trip-test")
    }

    // MARK: System fields

    /// Without the change tag, every upload would overwrite the server copy
    /// blind and conflicts would never be detected.
    @Test func systemFieldsArchiveAndRestoreTheRecordIdentity() {
        let trip = Trip(origin: .sfo, destination: .jfk)
        let record = RecordCodec.record(for: trip, in: zoneID)

        guard let data = RecordCodec.archiveSystemFields(record) else {
            Issue.record("system fields did not archive")
            return
        }
        let restored = RecordCodec.existingRecord(from: data)

        #expect(restored?.recordID == record.recordID)
        #expect(restored?.recordType == record.recordType)
        // System fields only — the values are not carried.
        #expect(restored?["title"] as? String == nil)
    }

    @Test func decodingASecondTimeReusesTheSameRecordIdentity() {
        let trip = Trip(origin: .sfo, destination: .jfk)
        let first = RecordCodec.record(for: trip, in: zoneID)
        RecordCodec.apply(first, to: trip)

        // With system fields stored, re-encoding must target the same record
        // rather than minting a fresh one.
        let second = RecordCodec.record(for: trip, in: zoneID)
        #expect(second.recordID == first.recordID)
    }

    @Test func garbageSystemFieldsDoNotCrashTheEncoder() {
        let trip = Trip(origin: .sfo, destination: .jfk)
        trip.ckSystemFields = Data("not an archive".utf8)

        let record = RecordCodec.record(for: trip, in: zoneID)
        #expect(record.recordID.recordName == trip.id.uuidString)
    }

    // MARK: Wrong-type guards

    @Test func decodingRejectsRecordsOfTheWrongType() {
        let foreign = CKRecord(recordType: "SomethingElse",
                               recordID: CKRecord.ID(recordName: UUID().uuidString, zoneID: zoneID))
        #expect(RecordCodec.makeTrip(from: foreign) == nil)
        #expect(RecordCodec.makeSegment(from: foreign) == nil)
        #expect(RecordCodec.makeStatus(from: foreign) == nil)
    }

    @Test func decodingRejectsATripRecordWithoutAUUIDName() {
        let bad = CKRecord(recordType: RecordType.trip,
                           recordID: CKRecord.ID(recordName: "hello", zoneID: zoneID))
        #expect(RecordCodec.makeTrip(from: bad) == nil)
    }
}
