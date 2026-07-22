//
//  ShareManager.swift
//  Runnit iOS
//
//  Everything to do with inviting people to a trip.
//
//  Sharing works on the zone, not the record. Every trip already owns a zone
//  (`trip-<id>`, assigned by SyncEngine), so a share covers the trip, its legs,
//  and their live-status snapshots in one go — and adding a leg later needs no
//  extra sharing work at all.
//
//  The roster is mirrored back onto the Trip as `participantSummaries` so the
//  UI can draw avatars and permissions instantly and offline. CloudKit stays the
//  authority: what's stored locally is a snapshot of the last time we asked.
//

import CloudKit
import Foundation
import SwiftData

@MainActor
final class ShareManager {

    enum ShareError: LocalizedError {
        case noZone
        case notOwner
        case noShare

        var errorDescription: String? {
            switch self {
            case .noZone:   return "This trip hasn't finished syncing to iCloud yet."
            case .notOwner: return "Only the trip's owner can change who it's shared with."
            case .noShare:  return "This trip isn't shared."
            }
        }
    }

    /// Injected only by tests. Resolved lazily otherwise — see `CloudContainer`.
    private let injectedContainer: CKContainer?
    private var container: CKContainer { injectedContainer ?? CloudContainer.shared }

    init(container: CKContainer? = nil) {
        self.injectedContainer = container
    }

    // MARK: Creating and fetching

    /// The trip's share, creating one the first time.
    ///
    /// `defaultPermission` becomes the access new invitees get. It's chosen
    /// before the invite goes out rather than after, because that's the order
    /// the question actually occurs to the person sending it.
    func share(for trip: Trip, defaultPermission: SharePermission) async throws -> CKShare {
        guard let zoneID = ownedZoneID(for: trip) else {
            throw trip.isOwnedByMe ? ShareError.noZone : ShareError.notOwner
        }

        if let existing = try await existingShare(for: trip, in: zoneID) {
            existing.publicPermission = .none
            return existing
        }

        let share = CKShare(recordZoneID: zoneID)
        share[CKShare.SystemFieldKey.title] = trip.displayTitle
        share[CKShare.SystemFieldKey.shareType] = "trip"
        // Invite-only: a link on its own grants nothing until we add someone.
        share.publicPermission = .none

        let saved = try await container.privateCloudDatabase.save(share)
        guard let savedShare = saved as? CKShare else { throw ShareError.noShare }
        store(savedShare, on: trip)
        return savedShare
    }

    /// The stored share, refetched from the server so participant changes made
    /// on another device are reflected.
    private func existingShare(for trip: Trip, in zoneID: CKRecordZone.ID) async throws -> CKShare? {
        guard let recordID = storedShareID(for: trip) ?? zoneShareID(for: zoneID) else { return nil }
        do {
            return try await container.privateCloudDatabase.record(for: recordID) as? CKShare
        } catch let error as CKError where error.code == .unknownItem {
            // The share was deleted out from under us — the trip is private again.
            trip.shareRecordData = nil
            trip.participantSummaries = []
            return nil
        }
    }

    /// Fetch the share for a trip we've been invited to, from the shared database.
    func participantShare(for trip: Trip) async throws -> CKShare? {
        guard let recordID = storedShareID(for: trip) else { return nil }
        return try await container.sharedCloudDatabase.record(for: recordID) as? CKShare
    }

    // MARK: Participants

    /// Re-read the roster from a share and mirror it onto the trip.
    func refreshParticipants(on trip: Trip, from share: CKShare) async {
        let me = try? await container.userRecordID()
        trip.participantSummaries = share.participants.map { summary(for: $0, currentUser: me) }
        store(share, on: trip)
    }

    /// Change one person's access. CloudKit is the enforcement point — this is
    /// what actually stops a view-only guest from editing, not the hidden UI.
    func setPermission(_ permission: SharePermission,
                       for participant: ShareParticipantSummary,
                       on trip: Trip) async throws {
        let share = try await ownedShare(for: trip)
        guard let target = match(participant, in: share) else { throw ShareError.noShare }

        target.permission = permission == .readWrite ? .readWrite : .readOnly
        let saved = try await container.privateCloudDatabase.save(share)
        if let updated = saved as? CKShare {
            await refreshParticipants(on: trip, from: updated)
        }
    }

    /// Remove someone from the trip. Their copy disappears on their next sync.
    func remove(_ participant: ShareParticipantSummary, from trip: Trip) async throws {
        let share = try await ownedShare(for: trip)
        guard let target = match(participant, in: share) else { throw ShareError.noShare }

        share.removeParticipant(target)
        let saved = try await container.privateCloudDatabase.save(share)
        if let updated = saved as? CKShare {
            await refreshParticipants(on: trip, from: updated)
        }
    }

    /// Stop participating in someone else's trip. Deleting the share record from
    /// our shared database is how CloudKit models "leave" for a guest — the
    /// owner's copy is untouched.
    func leave(_ trip: Trip, in context: ModelContext) async throws {
        guard !trip.isOwnedByMe else { throw ShareError.notOwner }
        guard let recordID = storedShareID(for: trip) else { throw ShareError.noShare }

        try await container.sharedCloudDatabase.deleteRecord(withID: recordID)
        context.delete(trip)
        try? context.save()
    }

    /// Stop sharing entirely, returning the trip to just its owner.
    func stopSharing(_ trip: Trip) async throws {
        let share = try await ownedShare(for: trip)
        try await container.privateCloudDatabase.deleteRecord(withID: share.recordID)
        trip.shareRecordData = nil
        trip.participantSummaries = []
    }

    // MARK: Plumbing

    private func ownedShare(for trip: Trip) async throws -> CKShare {
        guard trip.isOwnedByMe else { throw ShareError.notOwner }
        guard let zoneID = ownedZoneID(for: trip) else { throw ShareError.noZone }
        guard let share = try await existingShare(for: trip, in: zoneID) else {
            throw ShareError.noShare
        }
        return share
    }

    /// Participants have no stable id we control, so they're matched on the
    /// contact handle the invite was addressed to.
    private func match(_ summary: ShareParticipantSummary, in share: CKShare) -> CKShare.Participant? {
        share.participants.first { participant in
            handle(for: participant) == summary.handle
                && participant.role != .owner
        }
    }

    private func summary(for participant: CKShare.Participant,
                         currentUser: CKRecord.ID?) -> ShareParticipantSummary {
        let components = participant.userIdentity.nameComponents
        let name = components.map { PersonNameComponentsFormatter.localizedString(from: $0, style: .default) }

        return ShareParticipantSummary(
            name: name?.isEmpty == false ? name : nil,
            handle: handle(for: participant),
            permission: participant.permission == .readWrite ? .readWrite : .readOnly,
            acceptance: acceptance(for: participant),
            isCurrentUser: participant.userIdentity.userRecordID == currentUser,
            isOwner: participant.role == .owner
        )
    }

    private func handle(for participant: CKShare.Participant) -> String? {
        participant.userIdentity.lookupInfo?.emailAddress
            ?? participant.userIdentity.lookupInfo?.phoneNumber
    }

    private func acceptance(for participant: CKShare.Participant) -> ShareAcceptance {
        switch participant.acceptanceStatus {
        case .accepted: return .accepted
        case .removed:  return .removed
        default:        return .pending
        }
    }

    /// The zone a trip we own lives in. Nil for a trip shared with us — its zone
    /// belongs to the person who shared it.
    private func ownedZoneID(for trip: Trip) -> CKRecordZone.ID? {
        guard trip.isOwnedByMe, let zoneName = trip.zoneName else { return nil }
        return CKRecordZone.ID(zoneName: zoneName, ownerName: CKCurrentUserDefaultName)
    }

    /// CloudKit names a zone-wide share record `cloudkit.zoneshare` in the zone
    /// it shares, which is how an existing share is found without storing it.
    private func zoneShareID(for zoneID: CKRecordZone.ID) -> CKRecord.ID? {
        CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zoneID)
    }

    private func storedShareID(for trip: Trip) -> CKRecord.ID? {
        RecordCodec.existingRecord(from: trip.shareRecordData)?.recordID
    }

    private func store(_ share: CKShare, on trip: Trip) {
        trip.shareRecordData = RecordCodec.archiveSystemFields(share)
    }
}
