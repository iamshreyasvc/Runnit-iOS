//
//  SyncTrackerTests.swift
//  Runnit iOSTests
//
//  The tracker decides what leaves the device. Two failure modes matter and
//  they pull in opposite directions: uploading something that should have
//  stayed local (demo data, a trip we only have read access to), or quietly
//  never uploading a real edit. Both are silent in the app, so they're pinned
//  down here.
//
//  These drive the tracker's array-based entry points rather than its
//  ModelContext ones, so no store is stood up at all — the decision logic is
//  the part worth testing, and it's plain values.
//

import CloudKit
import Foundation
import SwiftData
import Testing
@testable import Runnit_iOS

@MainActor
struct SyncTrackerTests {

    private func makeTracker() -> SyncTracker {
        // Its own defaults suite, so tests can't see each other's tombstones.
        SyncTracker(defaults: UserDefaults(suiteName: "sync-tests-\(UUID().uuidString)")!)
    }

    /// A one-leg trip. Unmanaged — nothing here needs a store.
    private func makeTrip(title: String = "", vehicleNumber: String? = nil) -> Trip {
        Trip.make(title: title, segments: [
            TripSegment(type: .flight, origin: .sfo, destination: .jfk,
                        operatorName: "United", vehicleNumber: vehicleNumber)
        ])
    }

    /// A trip that has already been given its CloudKit zone.
    private func zonedTrip(title: String = "Trip") -> Trip {
        let trip = makeTrip(title: title)
        trip.zoneName = RecordCodec.zoneName(for: trip.id)
        return trip
    }

    /// Mark a trip and its legs as confirmed at their current version, the way
    /// a successful upload does.
    private func confirmAll(_ trip: Trip) {
        trip.syncedAt = trip.updatedAt
        for segment in trip.segments { segment.syncedAt = segment.updatedAt }
    }

    // MARK: Zone assignment

    @Test func aNewTripNeedsAZone() {
        let tracker = makeTracker()
        let trip = makeTrip()

        #expect(tracker.tripsNeedingZones(among: [trip]).map(\.id) == [trip.id])
    }

    @Test func sampleTripsNeverGetAZone() {
        let tracker = makeTracker()
        let sample = makeTrip(title: "Euro Loop")
        sample.isSample = true

        #expect(tracker.tripsNeedingZones(among: [sample]).isEmpty)
    }

    @Test func aTripSharedWithUsKeepsItsOwnersZone() {
        let tracker = makeTracker()
        let trip = makeTrip()
        trip.ownerName = "_priya"

        // We don't create zones in someone else's database.
        #expect(tracker.tripsNeedingZones(among: [trip]).isEmpty)
    }

    @Test func aTripWithAZoneIsNotAskedForAnother() {
        let tracker = makeTracker()
        let trip = zonedTrip()
        #expect(tracker.tripsNeedingZones(among: [trip]).isEmpty)
    }

    // MARK: The sweep

    @Test func aFreshlyEditedTripAndItsLegsAreOutstanding() {
        let tracker = makeTracker()
        let trip = zonedTrip()

        let outstanding = tracker.outstandingChanges(trips: [trip], statuses: [])
        let names = Set(outstanding.saves.map(\.recordName))

        #expect(names.contains(trip.id.uuidString))
        #expect(names.contains(trip.segments[0].id.uuidString))
    }

    @Test func recordsGoToTheirTripsOwnZone() {
        let tracker = makeTracker()
        let trip = zonedTrip()

        let zones = Set(tracker.outstandingChanges(trips: [trip], statuses: []).saves.map(\.zoneID.zoneName))
        #expect(zones == [RecordCodec.zoneName(for: trip.id)])
    }

    @Test func nothingIsOutstandingOnceEveryRecordIsConfirmed() {
        let tracker = makeTracker()
        let trip = zonedTrip()
        confirmAll(trip)

        #expect(tracker.outstandingChanges(trips: [trip], statuses: []).saves.isEmpty)
    }

    @Test func anEditAfterConfirmationBecomesOutstandingAgain() {
        let tracker = makeTracker()
        let trip = zonedTrip()
        confirmAll(trip)

        trip.title = "Renamed"
        trip.touch(Date().addingTimeInterval(120))

        let names = tracker.outstandingChanges(trips: [trip], statuses: []).saves.map(\.recordName)
        #expect(names.contains(trip.id.uuidString))
    }

    /// The bug this guards: a record that has just been *downloaded* has a
    /// fresh `updatedAt` too. Judged against one global "last upload" clock it
    /// looks like a local edit and gets sent straight back, so two devices
    /// bounce the same trip between them forever.
    @Test func aDownloadedRecordIsNotImmediatelyUploadedBack() {
        let tracker = makeTracker()
        let trip = zonedTrip()

        // Exactly what RecordCodec.apply does for an incoming record: a stamp
        // far newer than anything local, marked as already synced.
        let remoteStamp = Date().addingTimeInterval(3_600)
        trip.updatedAt = remoteStamp
        trip.syncedAt = remoteStamp
        for segment in trip.segments {
            segment.updatedAt = remoteStamp
            segment.syncedAt = remoteStamp
        }

        #expect(tracker.outstandingChanges(trips: [trip], statuses: []).saves.isEmpty)
    }

    /// Only the version that was actually accepted is confirmed — an edit made
    /// while the upload was in flight must survive as outstanding.
    @Test func anEditDuringUploadIsNotSweptAwayByTheConfirmation() {
        let tracker = makeTracker()
        let trip = zonedTrip()

        let sentVersion = trip.updatedAt
        trip.touch(sentVersion.addingTimeInterval(5))   // edited mid-flight
        trip.syncedAt = sentVersion                      // server confirms the old one
        for segment in trip.segments { segment.syncedAt = segment.updatedAt }

        let names = tracker.outstandingChanges(trips: [trip], statuses: []).saves.map(\.recordName)
        #expect(names == [trip.id.uuidString])
    }

    @Test func sampleTripsAreNeverUploaded() {
        let tracker = makeTracker()
        let sample = zonedTrip(title: "Flight Path Test")
        sample.isSample = true

        let names = tracker.outstandingChanges(trips: [sample], statuses: []).saves.map(\.recordName)
        #expect(!names.contains(sample.id.uuidString))
    }

    /// A read-only participant's local edits would be rejected by CloudKit
    /// anyway; queuing them just produces a retry loop.
    @Test func readOnlySharedTripsAreNotUploaded() {
        let tracker = makeTracker()
        let trip = zonedTrip()
        trip.ownerName = "_priya"
        trip.shareRecordData = Data("share".utf8)
        trip.participantSummaries = [
            ShareParticipantSummary(name: "Me", permission: .readOnly,
                                    acceptance: .accepted, isCurrentUser: true)
        ]

        #expect(tracker.outstandingChanges(trips: [trip], statuses: []).saves.isEmpty)
    }

    @Test func editableSharedTripsAreUploadedToTheOwnersZone() {
        let tracker = makeTracker()
        let trip = zonedTrip()
        trip.ownerName = "_priya"
        trip.shareRecordData = Data("share".utf8)
        trip.participantSummaries = [
            ShareParticipantSummary(name: "Me", permission: .readWrite,
                                    acceptance: .accepted, isCurrentUser: true)
        ]
        trip.touch()

        let saves = tracker.outstandingChanges(trips: [trip], statuses: []).saves
        #expect(saves.contains { $0.recordName == trip.id.uuidString })
        #expect(saves.allSatisfy { $0.zoneID.ownerName == "_priya" })
    }

    @Test func aTripWithoutAZoneIsSkippedUntilItHasOne() {
        let tracker = makeTracker()
        let trip = makeTrip()

        #expect(tracker.outstandingChanges(trips: [trip], statuses: []).saves.isEmpty)
    }

    // MARK: Flight status snapshots

    @Test func statusSnapshotsRideInTheirTripsZone() {
        let tracker = makeTracker()
        let trip = zonedTrip()
        let segmentID = trip.segments[0].id

        let status = FlightStatusRecord(segmentID: segmentID)

        let saves = tracker.outstandingChanges(trips: [trip], statuses: [status]).saves
        let statusSave = saves.first { $0.recordName.hasPrefix("status-") }

        #expect(statusSave?.recordName == RecordCodec.statusRecordName(for: segmentID))
        #expect(statusSave?.zoneID.zoneName == RecordCodec.zoneName(for: trip.id))
    }

    /// A snapshot for a sample trip's leg — or an orphan whose leg is gone —
    /// has no zone to go to and must not be queued.
    @Test func orphanStatusSnapshotsAreSkipped() {
        let tracker = makeTracker()
        let trip = zonedTrip()
        let orphan = FlightStatusRecord(segmentID: UUID())

        let saves = tracker.outstandingChanges(trips: [trip], statuses: [orphan]).saves
        #expect(!saves.contains { $0.recordName.hasPrefix("status-") })
    }

    // MARK: Tombstones

    @Test func deletionsSurviveUntilConfirmed() {
        let tracker = makeTracker()
        let zoneID = CKRecordZone.ID(zoneName: "trip-x", ownerName: CKCurrentUserDefaultName)
        let id = CKRecord.ID(recordName: "gone", zoneID: zoneID)

        tracker.noteDeletions([id])
        #expect(tracker.tombstones.map(\.recordName) == ["gone"])

        tracker.clearTombstones([id])
        #expect(tracker.tombstones.isEmpty)
    }

    @Test func theSameDeletionIsNotRecordedTwice() {
        let tracker = makeTracker()
        let id = CKRecord.ID(recordName: "gone",
                             zoneID: CKRecordZone.ID(zoneName: "trip-x",
                                                     ownerName: CKCurrentUserDefaultName))
        tracker.noteDeletions([id])
        tracker.noteDeletions([id])
        #expect(tracker.tombstones.count == 1)
    }

    @Test func pendingDeletionsAppearInTheSweep() {
        let tracker = makeTracker()
        let id = CKRecord.ID(recordName: "gone",
                             zoneID: CKRecordZone.ID(zoneName: "trip-x",
                                                     ownerName: CKCurrentUserDefaultName))
        tracker.noteDeletions([id])
        #expect(tracker.outstandingChanges(trips: [], statuses: []).deletes.map(\.recordName) == ["gone"])
    }

    @Test func aTombstoneKeepsItsZoneAcrossReads() {
        let tracker = makeTracker()
        let zoneID = CKRecordZone.ID(zoneName: "trip-abc", ownerName: "_priya")
        tracker.noteDeletions([CKRecord.ID(recordName: "gone", zoneID: zoneID)])

        #expect(tracker.tombstones.first?.zoneID == zoneID)
    }

    // MARK: Account changes

    @Test func resettingSyncStateMakesEverythingOutstandingAgain() {
        let tracker = makeTracker()
        let trip = zonedTrip()
        confirmAll(trip)
        #expect(tracker.outstandingChanges(trips: [trip], statuses: []).saves.isEmpty)

        // What `resetSyncState` does to each record, without a store to do it in.
        trip.syncedAt = nil
        trip.zoneName = nil
        for segment in trip.segments { segment.syncedAt = nil }

        // The zone assignment goes too, so the trip is re-zoned before anything
        // can be sent to a different account.
        #expect(tracker.tripsNeedingZones(among: [trip]).map(\.id) == [trip.id])
    }
}
