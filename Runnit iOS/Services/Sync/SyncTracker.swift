//
//  SyncTracker.swift
//  Runnit iOS
//
//  Works out what has changed locally and still needs to go up.
//
//  SwiftData has no change feed we can drive a sync engine from directly, and
//  hooking every write site in the app would mean a new way to forget one. So
//  the tracker derives the answer instead: every model already stamps
//  `updatedAt`, so anything stamped after the last successful upload is
//  outstanding. A save notification just makes it prompt — correctness comes
//  from the sweep, not from catching every edit as it happens.
//
//  Deletions are the exception. Once a trip is gone there is nothing left to
//  scan, so the record ids are written down as tombstones before the delete and
//  drained once CloudKit confirms them.
//

import CloudKit
import Foundation
import SwiftData

@MainActor
final class SyncTracker {

    /// What the tracker decided still needs sending.
    struct Outstanding {
        var saves: [CKRecord.ID] = []
        var deletes: [CKRecord.ID] = []

        var isEmpty: Bool { saves.isEmpty && deletes.isEmpty }
    }

    private enum Key {
        static let tombstones = "runnit.sync.tombstones"
    }

    private let defaults: UserDefaults

    /// Nonisolated so it can be a default argument on `SyncEngine.init` — those
    /// are evaluated at the call site, outside the main actor. Nothing here
    /// touches isolated state.
    nonisolated init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: Sync state

    /// Forget what's been synced, so everything uploads again. Used when the
    /// iCloud account changes: the new account has seen none of this data, and
    /// the old account's confirmations describe nothing that's still true.
    func resetSyncState(in context: ModelContext) {
        for trip in (try? context.fetch(FetchDescriptor<Trip>())) ?? [] {
            trip.syncedAt = nil
            trip.ckSystemFields = nil
            trip.zoneName = nil
        }
        for segment in (try? context.fetch(FetchDescriptor<TripSegment>())) ?? [] {
            segment.syncedAt = nil
            segment.ckSystemFields = nil
        }
        for status in (try? context.fetch(FetchDescriptor<FlightStatusRecord>())) ?? [] {
            status.syncedAt = nil
            status.ckSystemFields = nil
        }
        try? context.save()
    }

    // MARK: Tombstones

    /// Record ids deleted locally but not yet deleted on the server.
    var tombstones: [CKRecord.ID] {
        guard let data = defaults.data(forKey: Key.tombstones),
              let stored = try? JSONDecoder().decode([StoredRecordID].self, from: data)
        else { return [] }
        return stored.map(\.recordID)
    }

    /// Write down what a delete removed, before the objects are gone and the
    /// record ids become unrecoverable.
    func noteDeletions(_ ids: [CKRecord.ID]) {
        guard !ids.isEmpty else { return }
        var all = tombstones
        let known = Set(all.map(StoredRecordID.init))
        for id in ids where !known.contains(StoredRecordID(id)) { all.append(id) }
        persist(all)
    }

    /// Drop tombstones CloudKit has confirmed.
    func clearTombstones(_ ids: [CKRecord.ID]) {
        let done = Set(ids.map(StoredRecordID.init))
        persist(tombstones.filter { !done.contains(StoredRecordID($0)) })
    }

    private func persist(_ ids: [CKRecord.ID]) {
        let stored = ids.map(StoredRecordID.init)
        defaults.set(try? JSONEncoder().encode(stored), forKey: Key.tombstones)
    }

    // MARK: The sweep

    /// Everything that has changed locally since CloudKit last confirmed it.
    ///
    /// The comparison is per record — `updatedAt` against that record's own
    /// `syncedAt` — rather than against one global timestamp. That matters:
    /// with a shared clock, a record we had just *downloaded* would look newer
    /// than the last upload and get sent straight back, ping-ponging between
    /// devices forever.
    ///
    /// Sample trips are skipped outright — demo data never leaves the device —
    /// and so is anything we don't have write access to, which CloudKit would
    /// reject anyway.
    func outstandingChanges(in context: ModelContext) -> Outstanding {
        outstandingChanges(
            trips: (try? context.fetch(FetchDescriptor<Trip>())) ?? [],
            statuses: (try? context.fetch(FetchDescriptor<FlightStatusRecord>())) ?? []
        )
    }

    /// The decision itself, over plain arrays. Split from the fetching so it can
    /// be tested without standing up a store — the same reason `Connection` is
    /// kept free of SwiftData.
    func outstandingChanges(trips: [Trip], statuses: [FlightStatusRecord]) -> Outstanding {
        var result = Outstanding(deletes: tombstones)
        var syncableSegmentIDs: Set<UUID> = []

        for trip in trips where !trip.isSample {
            guard let zoneID = zoneID(for: trip) else { continue }
            guard trip.canEdit else { continue }

            if isDirty(updated: trip.updatedAt, synced: trip.syncedAt) {
                result.saves.append(CKRecord.ID(recordName: trip.id.uuidString, zoneID: zoneID))
            }
            for segment in trip.segments {
                syncableSegmentIDs.insert(segment.id)
                if isDirty(updated: segment.updatedAt, synced: segment.syncedAt) {
                    result.saves.append(
                        CKRecord.ID(recordName: segment.id.uuidString, zoneID: zoneID)
                    )
                }
            }
        }

        // Status snapshots have no relationship to walk — they're keyed by
        // segment id — so they're matched back to their trip's zone here.
        let zoneBySegment = segmentZones(in: trips)
        for status in statuses where isDirty(updated: status.updatedAt, synced: status.syncedAt) {
            guard syncableSegmentIDs.contains(status.segmentID),
                  let zoneID = zoneBySegment[status.segmentID]
            else { continue }
            result.saves.append(
                CKRecord.ID(recordName: RecordCodec.statusRecordName(for: status.segmentID),
                            zoneID: zoneID)
            )
        }

        return result
    }

    /// A record is outstanding when it has been edited since CloudKit last
    /// confirmed that exact version. Never confirmed at all means outstanding.
    private func isDirty(updated: Date, synced: Date?) -> Bool {
        guard let synced else { return true }
        return updated > synced
    }

    /// Trips that own no CloudKit zone yet, so the engine can create one before
    /// their records can go anywhere.
    func tripsNeedingZones(in context: ModelContext) -> [Trip] {
        tripsNeedingZones(among: (try? context.fetch(FetchDescriptor<Trip>())) ?? [])
    }

    /// Store-free counterpart, for the same reason as above.
    func tripsNeedingZones(among trips: [Trip]) -> [Trip] {
        trips.filter { !$0.isSample && $0.zoneName == nil && $0.isOwnedByMe }
    }

    // MARK: Zone lookup

    /// The zone a trip's records live in, or nil if it hasn't been assigned one.
    /// A trip shared with us lives in its owner's zone, not ours.
    private func zoneID(for trip: Trip) -> CKRecordZone.ID? {
        guard let zoneName = trip.zoneName else { return nil }
        return CKRecordZone.ID(zoneName: zoneName,
                               ownerName: trip.ownerName ?? CKCurrentUserDefaultName)
    }

    private func segmentZones(in trips: [Trip]) -> [UUID: CKRecordZone.ID] {
        var map: [UUID: CKRecordZone.ID] = [:]
        for trip in trips where !trip.isSample {
            guard let zoneID = zoneID(for: trip) else { continue }
            for segment in trip.segments { map[segment.id] = zoneID }
        }
        return map
    }
}

/// A `CKRecord.ID` flattened for storage. CKRecord.ID isn't Codable, and
/// tombstones have to outlive the launch that created them.
private struct StoredRecordID: Codable, Hashable {
    var recordName: String
    var zoneName: String
    var ownerName: String

    init(_ id: CKRecord.ID) {
        recordName = id.recordName
        zoneName = id.zoneID.zoneName
        ownerName = id.zoneID.ownerName
    }

    var recordID: CKRecord.ID {
        CKRecord.ID(recordName: recordName,
                    zoneID: CKRecordZone.ID(zoneName: zoneName, ownerName: ownerName))
    }
}
