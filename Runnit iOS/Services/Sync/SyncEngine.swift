//
//  SyncEngine.swift
//  Runnit iOS
//
//  Keeps the local SwiftData store and CloudKit in step.
//
//  SwiftData remains the source of truth: every screen reads and writes it
//  exactly as before, which is what keeps the app fully usable offline. This
//  class is only the transport — it pushes local edits up and folds remote ones
//  back in.
//
//  Two engines, because CKSyncEngine works on one database scope at a time:
//
//  * the private engine carries the trips this person owns
//  * the shared engine carries the trips other people invited them to
//
//  Both write into the same store; whether a trip is ours is just `ownerName`.
//
//  Every trip owns a CloudKit zone (`trip-<id>`). That looks extravagant until
//  you try to share one — CloudKit can't share records in the default zone, and
//  a zone is the cleanest unit to attach a CKShare to. Giving every trip its own
//  from the start means sharing never has to move records between zones.
//

import CloudKit
import Foundation
import Observation
import SwiftData

/// The app's CloudKit container, created on first use.
///
/// Deliberately not built during app launch. `CKContainer(identifier:)` *traps*
/// when the iCloud entitlement is missing or the container id doesn't match the
/// provisioning profile — so constructing one eagerly turns every signing
/// misconfiguration into a crash on launch instead of an app that runs with
/// sync switched off. A `static let` is lazy, so nothing touches CloudKit until
/// something actually syncs.
enum CloudContainer {
    static let identifier = "iCloud.Runnit.Runnit-iOS"
    static let shared = CKContainer(identifier: identifier)

    /// Whether this build actually ships the iCloud entitlement.
    ///
    /// `CKContainer(identifier:)` traps outright when the entitlement is
    /// missing, so there's no way to try it and recover — it has to be known
    /// before touching CloudKit at all. The flag lives in Info.plist because
    /// the answer is a property of how the app was signed, not of anything
    /// that can be discovered at runtime.
    ///
    /// It is currently **off**: iCloud is unavailable to free Apple developer
    /// accounts ("Personal development teams do not support the iCloud
    /// capability"). Everything in `Services/Sync` stays built and tested but
    /// dormant, and the UI reports trips as not saved to iCloud. Enrolling in
    /// the paid Developer Program, adding the iCloud → CloudKit capability in
    /// Xcode, and flipping this to `true` is all that's needed to switch it on.
    static var isEnabled: Bool {
        Bundle.main.object(forInfoDictionaryKey: "RunnitCloudKitEnabled") as? Bool ?? false
    }
}

@MainActor
@Observable
final class SyncEngine {

    /// What the Account screen shows about syncing.
    enum SyncState: Equatable {
        case idle
        case syncing
        case offline
        case noAccount
        case failed(String)
    }

    private(set) var state: SyncState = .idle
    private(set) var lastSyncedAt: Date?

    /// Injected only by tests; production resolves `CloudContainer.shared`
    /// lazily, on the first sync rather than at launch.
    private let injectedContainer: CKContainer?
    private var container: CKContainer { injectedContainer ?? CloudContainer.shared }

    private let modelContainer: ModelContainer
    let tracker: SyncTracker

    private var privateEngine: CKSyncEngine?
    private var sharedEngine: CKSyncEngine?

    private enum Key {
        static let privateState = "runnit.sync.state.private"
        static let sharedState = "runnit.sync.state.shared"
        static let lastSynced = "runnit.sync.lastSynced"
    }

    init(modelContainer: ModelContainer,
         container: CKContainer? = nil,
         tracker: SyncTracker = SyncTracker()) {
        self.modelContainer = modelContainer
        self.injectedContainer = container
        self.tracker = tracker
        let stored = UserDefaults.standard.double(forKey: Key.lastSynced)
        self.lastSyncedAt = stored > 0 ? Date(timeIntervalSince1970: stored) : nil
    }

    private var context: ModelContext { modelContainer.mainContext }

    /// Whether iCloud is usable on this device at all. False means there's no
    /// signed-in account, so nothing can upload until that's fixed — a
    /// different situation from an upload that simply hasn't happened yet.
    var isCloudAvailable: Bool { state != .noAccount }

    /// Whether a manual "Sync Now" would do anything. Hidden mid-sync, and with
    /// no account there's nothing to sync to.
    var canSyncNow: Bool {
        switch state {
        case .syncing, .noAccount: return false
        default:                   return privateEngine != nil
        }
    }

    // MARK: - Lifecycle

    /// Bring both engines up. Safe to call more than once — a second call just
    /// kicks a sync, which is what we want on foreground.
    func start() async {
        // Touching CloudKit without the entitlement is a hard crash, not an
        // error — so this check comes before anything else.
        guard CloudContainer.isEnabled else {
            state = .noAccount
            return
        }
        guard await hasAccount() else {
            state = .noAccount
            return
        }
        if privateEngine == nil {
            privateEngine = makeEngine(for: container.privateCloudDatabase,
                                       stateKey: Key.privateState)
        }
        if sharedEngine == nil {
            sharedEngine = makeEngine(for: container.sharedCloudDatabase,
                                      stateKey: Key.sharedState)
        }
        await ensureZonesExist()
        await syncNow()
    }

    /// Push anything outstanding and pull anything new.
    func syncNow() async {
        guard let privateEngine else { return }
        state = .syncing
        do {
            try await privateEngine.fetchChanges()
            try await privateEngine.sendChanges()
            if let sharedEngine {
                try await sharedEngine.fetchChanges()
                try await sharedEngine.sendChanges()
            }
            finishSync(at: Date())
        } catch {
            report(error)
        }
    }

    private func makeEngine(for database: CKDatabase, stateKey: String) -> CKSyncEngine {
        var configuration = CKSyncEngine.Configuration(
            database: database,
            stateSerialization: loadState(forKey: stateKey),
            delegate: self
        )
        configuration.automaticallySync = true
        return CKSyncEngine(configuration)
    }

    private func hasAccount() async -> Bool {
        (try? await container.accountStatus()) == .available
    }

    private func finishSync(at date: Date) {
        lastSyncedAt = date
        UserDefaults.standard.set(date.timeIntervalSince1970, forKey: Key.lastSynced)
        state = .idle
    }

    /// Translate a failure into something the Account screen can say. Being
    /// offline isn't an error — edits are queued and go up later — so it reads
    /// as its own state rather than a red one.
    private func report(_ error: Error) {
        let ckError = error as? CKError
        switch ckError?.code {
        case .networkUnavailable, .networkFailure, .serviceUnavailable:
            state = .offline
        case .notAuthenticated:
            state = .noAccount
        default:
            state = .failed(error.localizedDescription)
        }
    }

    // MARK: - Zones

    /// Give every syncable trip a zone of its own, so it can be shared later
    /// without moving a single record.
    private func ensureZonesExist() async {
        let trips = tracker.tripsNeedingZones(in: context)
        guard !trips.isEmpty, let privateEngine else { return }

        var pending: [CKSyncEngine.PendingDatabaseChange] = []
        for trip in trips {
            let name = RecordCodec.zoneName(for: trip.id)
            trip.zoneName = name
            pending.append(.saveZone(CKRecordZone(zoneID: CKRecordZone.ID(
                zoneName: name, ownerName: CKCurrentUserDefaultName
            ))))
        }
        try? context.save()
        privateEngine.state.add(pendingDatabaseChanges: pending)
    }

    // MARK: - Local edits

    /// Queue everything that has changed locally since the last confirmed upload.
    /// Called before sending, and whenever the app comes back to the foreground.
    func enqueueLocalChanges() {
        let outstanding = tracker.outstandingChanges(in: context)
        guard !outstanding.isEmpty else { return }

        for scope in [privateEngine, sharedEngine] {
            guard let engine = scope else { continue }
            let mine = engine.database.databaseScope == .private
            let saves = outstanding.saves.filter { isPrivate($0) == mine }
            let deletes = outstanding.deletes.filter { isPrivate($0) == mine }
            guard !saves.isEmpty || !deletes.isEmpty else { continue }
            engine.state.add(pendingRecordZoneChanges:
                saves.map { .saveRecord($0) } + deletes.map { .deleteRecord($0) })
        }
    }

    /// A record in a zone we own belongs to the private database; anything in
    /// someone else's zone came to us through a share.
    private func isPrivate(_ id: CKRecord.ID) -> Bool {
        id.zoneID.ownerName == CKCurrentUserDefaultName
    }

    /// Note a deletion before the objects disappear. Call this *before*
    /// `context.delete(trip)` — afterwards the record ids are unrecoverable.
    func willDelete(_ trip: Trip) {
        guard !trip.isSample, let zoneName = trip.zoneName else { return }
        let zoneID = CKRecordZone.ID(zoneName: zoneName,
                                     ownerName: trip.ownerName ?? CKCurrentUserDefaultName)

        // Deleting the zone takes the trip, its legs, and their snapshots with
        // it in one operation — and reclaims the share along with them.
        if trip.isOwnedByMe {
            privateEngine?.state.add(pendingDatabaseChanges: [.deleteZone(zoneID)])
            return
        }
        tracker.noteDeletions([CKRecord.ID(recordName: trip.id.uuidString, zoneID: zoneID)])
    }

    // MARK: - Applying remote changes

    private func apply(_ record: CKRecord) {
        switch record.recordType {
        case RecordType.trip:        applyTrip(record)
        case RecordType.segment:     applySegment(record)
        case RecordType.flightStatus: applyStatus(record)
        default:                     break
        }
    }

    private func applyTrip(_ record: CKRecord) {
        guard let id = UUID(uuidString: record.recordID.recordName) else { return }
        guard let existing = fetchTrip(id: id) else {
            guard let trip = RecordCodec.makeTrip(from: record) else { return }
            trip.ownerName = remoteOwner(of: record)
            context.insert(trip)
            return
        }
        guard isNewer(record, than: existing.updatedAt) else { return }
        RecordCodec.apply(record, to: existing)
        existing.zoneName = record.recordID.zoneID.zoneName
        existing.ownerName = remoteOwner(of: record)
    }

    private func applySegment(_ record: CKRecord) {
        guard let id = UUID(uuidString: record.recordID.recordName) else { return }

        if let existing = fetchSegment(id: id) {
            guard isNewer(record, than: existing.updatedAt) else { return }
            RecordCodec.apply(record, to: existing)
            existing.trip?.refreshSummary()
            return
        }
        guard let segment = RecordCodec.makeSegment(from: record) else { return }
        context.insert(segment)
        if let tripID = RecordCodec.tripID(ofSegmentRecord: record),
           let trip = fetchTrip(id: tripID) {
            segment.trip = trip
            trip.refreshSummary()
        }
    }

    private func applyStatus(_ record: CKRecord) {
        guard let raw = record["segmentID"] as? String,
              let segmentID = UUID(uuidString: raw)
        else { return }

        if let existing = fetchStatus(segmentID: segmentID) {
            guard isNewer(record, than: existing.updatedAt) else { return }
            RecordCodec.apply(record, to: existing)
            return
        }
        guard let status = RecordCodec.makeStatus(from: record) else { return }
        context.insert(status)
    }

    /// Last writer wins. A record with no stamp is treated as older, so a
    /// half-written server copy can't overwrite a real local edit.
    private func isNewer(_ record: CKRecord, than local: Date) -> Bool {
        guard let remote = record["updatedAt"] as? Date else { return false }
        return remote > local
    }

    /// Nil when the record is in one of our own zones — the trip is ours.
    private func remoteOwner(of record: CKRecord) -> String? {
        let owner = record.recordID.zoneID.ownerName
        return owner == CKCurrentUserDefaultName ? nil : owner
    }

    private func delete(_ recordID: CKRecord.ID, type: String) {
        switch type {
        case RecordType.trip:
            if let id = UUID(uuidString: recordID.recordName), let trip = fetchTrip(id: id) {
                context.delete(trip)
            }
        case RecordType.segment:
            if let id = UUID(uuidString: recordID.recordName), let segment = fetchSegment(id: id) {
                let trip = segment.trip
                context.delete(segment)
                trip?.refreshSummary()
            }
        case RecordType.flightStatus:
            let name = recordID.recordName
            guard name.hasPrefix("status-"),
                  let id = UUID(uuidString: String(name.dropFirst("status-".count))),
                  let status = fetchStatus(segmentID: id)
            else { return }
            context.delete(status)
        default:
            break
        }
    }

    /// A whole zone went away — the trip was deleted by its owner, or a share we
    /// were part of was revoked.
    private func deleteZone(named zoneName: String) {
        guard let tripID = RecordCodec.tripID(fromZoneName: zoneName),
              let trip = fetchTrip(id: tripID)
        else { return }
        context.delete(trip)
    }

    // MARK: - Fetch helpers

    private func fetchTrip(id: UUID) -> Trip? {
        var descriptor = FetchDescriptor<Trip>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func fetchSegment(id: UUID) -> TripSegment? {
        var descriptor = FetchDescriptor<TripSegment>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func fetchStatus(segmentID: UUID) -> FlightStatusRecord? {
        var descriptor = FetchDescriptor<FlightStatusRecord>(
            predicate: #Predicate { $0.segmentID == segmentID }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    // MARK: - Building records to send

    /// Materialize the CKRecord for a pending change, or nil if the object has
    /// since been deleted — CloudKit then drops the change quietly.
    private func record(for recordID: CKRecord.ID) -> CKRecord? {
        let name = recordID.recordName

        if name.hasPrefix("status-") {
            guard let id = UUID(uuidString: String(name.dropFirst("status-".count))),
                  let status = fetchStatus(segmentID: id)
            else { return nil }
            return RecordCodec.record(for: status, in: recordID.zoneID)
        }
        guard let id = UUID(uuidString: name) else { return nil }
        if let trip = fetchTrip(id: id) {
            return RecordCodec.record(for: trip, in: recordID.zoneID)
        }
        if let segment = fetchSegment(id: id), let tripID = segment.trip?.id {
            return RecordCodec.record(for: segment, tripID: tripID, in: recordID.zoneID)
        }
        return nil
    }

    // MARK: - State serialization

    private func loadState(forKey key: String) -> CKSyncEngine.State.Serialization? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: data)
    }

    private func save(_ serialization: CKSyncEngine.State.Serialization, forKey key: String) {
        UserDefaults.standard.set(try? JSONEncoder().encode(serialization), forKey: key)
    }

    private func stateKey(for engine: CKSyncEngine) -> String {
        engine.database.databaseScope == .private ? Key.privateState : Key.sharedState
    }
}

// MARK: - CKSyncEngineDelegate

extension SyncEngine: CKSyncEngineDelegate {

    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        switch event {
        case .stateUpdate(let update):
            save(update.stateSerialization, forKey: stateKey(for: syncEngine))

        case .accountChange(let change):
            handleAccountChange(change)

        case .fetchedDatabaseChanges(let changes):
            for deletion in changes.deletions {
                deleteZone(named: deletion.zoneID.zoneName)
            }
            try? context.save()

        case .fetchedRecordZoneChanges(let changes):
            for modification in changes.modifications {
                apply(modification.record)
            }
            for deletion in changes.deletions {
                delete(deletion.recordID, type: deletion.recordType)
            }
            try? context.save()

        case .sentRecordZoneChanges(let sent):
            handleSentChanges(sent, on: syncEngine)

        case .willFetchChanges, .willSendChanges:
            state = .syncing

        case .didFetchChanges, .didSendChanges:
            finishSync(at: Date())

        default:
            break
        }
    }

    func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        // Sweep for local edits here rather than trusting every write site in
        // the app to have remembered to announce itself.
        enqueueLocalChanges()

        let scope = context.options.scope
        let pending = syncEngine.state.pendingRecordZoneChanges.filter { scope.contains($0) }
        guard !pending.isEmpty else { return nil }

        // Build every record up front. The batch's provider is called back
        // outside this actor, and reading SwiftData from there isn't allowed —
        // so by the time it runs, the answers are already a dictionary lookup.
        var records: [CKRecord.ID: CKRecord] = [:]
        var vanished: [CKSyncEngine.PendingRecordZoneChange] = []
        for change in pending {
            guard case .saveRecord(let id) = change else { continue }
            if let record = record(for: id) {
                records[id] = record
            } else {
                // Deleted locally between queueing and sending; drop it quietly.
                vanished.append(.saveRecord(id))
            }
        }
        if !vanished.isEmpty {
            syncEngine.state.remove(pendingRecordZoneChanges: vanished)
        }

        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: pending) { id in
            records[id]
        }
    }

    // MARK: Event handling

    private func handleAccountChange(_ change: CKSyncEngine.Event.AccountChange) {
        switch change.changeType {
        case .signIn, .switchAccounts:
            // A different (or newly signed-in) account has seen none of this
            // data, and the old account's zones and change tags mean nothing
            // here — so everything local becomes outstanding again.
            tracker.resetSyncState(in: context)
            state = .idle
        case .signOut:
            state = .noAccount
        @unknown default:
            break
        }
    }

    private func handleSentChanges(_ sent: CKSyncEngine.Event.SentRecordZoneChanges,
                                   on syncEngine: CKSyncEngine) {
        for record in sent.savedRecords {
            confirmSaved(record)
        }
        tracker.clearTombstones(sent.deletedRecordIDs)

        for failure in sent.failedRecordSaves {
            handleFailedSave(failure, on: syncEngine)
        }
        try? context.save()
    }

    /// Mark a record as safely on the server: keep its change tag so the next
    /// upload is an update rather than a blind overwrite, and record *which*
    /// version was accepted so the sweep stops offering it.
    ///
    /// The accepted version is the one we sent, not "now" — an edit made while
    /// the upload was in flight must stay outstanding.
    private func confirmSaved(_ record: CKRecord) {
        let fields = RecordCodec.archiveSystemFields(record)
        let sentVersion = record["updatedAt"] as? Date
        let name = record.recordID.recordName

        if name.hasPrefix("status-") {
            if let raw = record["segmentID"] as? String, let id = UUID(uuidString: raw),
               let status = fetchStatus(segmentID: id) {
                status.ckSystemFields = fields
                status.syncedAt = sentVersion
            }
            return
        }
        guard let id = UUID(uuidString: name) else { return }
        if let trip = fetchTrip(id: id) {
            trip.ckSystemFields = fields
            trip.syncedAt = sentVersion
        }
        if let segment = fetchSegment(id: id) {
            segment.ckSystemFields = fields
            segment.syncedAt = sentVersion
        }
    }

    /// The conflict case: someone else changed the record between our read and
    /// our write. Whichever version was edited later wins; if theirs did we take
    /// it, and if ours did we adopt their change tag and try again.
    private func handleFailedSave(_ failure: CKSyncEngine.Event.SentRecordZoneChanges.FailedRecordSave,
                                  on syncEngine: CKSyncEngine) {
        let error = failure.error
        switch error.code {
        case .serverRecordChanged:
            guard let serverRecord = error.serverRecord else { return }
            apply(serverRecord)
            syncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(serverRecord.recordID)])

        case .zoneNotFound, .userDeletedZone:
            // The zone went away under us — usually the owner deleted the trip.
            deleteZone(named: failure.record.recordID.zoneID.zoneName)

        case .networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited:
            // Transient. CKSyncEngine retries on its own; leave the change queued.
            state = .offline

        default:
            state = .failed(error.localizedDescription)
        }
    }
}
