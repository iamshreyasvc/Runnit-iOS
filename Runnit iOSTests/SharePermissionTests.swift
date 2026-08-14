//
//  SharePermissionTests.swift
//  Runnit iOSTests
//
//  `canEdit` decides which affordances a shared trip shows. CloudKit enforces
//  the real rule server-side, so a mistake here doesn't leak write access — but
//  it does offer someone an Edit button that will fail, or hide one from a
//  collaborator who is allowed to use it.
//

import Foundation
import Testing
@testable import Runnit_iOS

@MainActor
struct SharePermissionTests {

    private func sharedTrip(
        ownedByMe: Bool,
        myPermission: SharePermission = .readOnly
    ) -> Trip {
        let trip = Trip(origin: .sfo, destination: .jfk)
        trip.shareRecordData = Data("share".utf8)
        trip.ownerName = ownedByMe ? nil : "_otherPerson"
        trip.participantSummaries = [
            ShareParticipantSummary(name: "Priya", permission: .readWrite,
                                    acceptance: .accepted,
                                    isCurrentUser: ownedByMe, isOwner: true),
            ShareParticipantSummary(name: "Me", permission: myPermission,
                                    acceptance: .accepted,
                                    isCurrentUser: !ownedByMe)
        ]
        return trip
    }

    // MARK: Ownership

    @Test func anUnsharedTripIsMineAndEditable() {
        let trip = Trip(origin: .sfo, destination: .jfk)
        #expect(!trip.isShared)
        #expect(trip.isOwnedByMe)
        #expect(trip.canEdit)
    }

    @Test func aTripIsSharedOnceItHasAShareRecord() {
        let trip = Trip(origin: .sfo, destination: .jfk)
        trip.shareRecordData = Data("share".utf8)
        #expect(trip.isShared)
    }

    @Test func ownersCanAlwaysEditTheirOwnSharedTrip() {
        let trip = sharedTrip(ownedByMe: true)
        #expect(trip.isOwnedByMe)
        #expect(trip.canEdit)
    }

    // MARK: Participants

    @Test func aReadOnlyParticipantCannotEdit() {
        let trip = sharedTrip(ownedByMe: false, myPermission: .readOnly)
        #expect(!trip.isOwnedByMe)
        #expect(!trip.canEdit)
    }

    @Test func aReadWriteParticipantCanEdit() {
        let trip = sharedTrip(ownedByMe: false, myPermission: .readWrite)
        #expect(trip.canEdit)
    }

    /// Until the share's participants have synced we know only that the trip
    /// isn't ours. Withholding edit is the safe default — the alternative offers
    /// a button the server will reject.
    @Test func aParticipantWithNoSyncedRosterCannotEdit() {
        let trip = Trip(origin: .sfo, destination: .jfk)
        trip.ownerName = "_otherPerson"
        #expect(!trip.canEdit)
    }

    @Test func theOwnerIsIdentifiedForSharedWithYouPhrasing() {
        let trip = sharedTrip(ownedByMe: false)
        #expect(trip.ownerParticipant?.displayName == "Priya")
        #expect(trip.ownerParticipant?.shortName == "Priya")
    }

    // MARK: Roster ordering

    @Test func collaboratorsExcludeMeAndLeadWithTheOwner() {
        let trip = Trip(origin: .sfo, destination: .jfk)
        trip.participantSummaries = [
            ShareParticipantSummary(name: "Zoe", acceptance: .accepted),
            ShareParticipantSummary(name: "Me", isCurrentUser: true),
            ShareParticipantSummary(name: "Priya", acceptance: .accepted, isOwner: true),
            ShareParticipantSummary(name: "Alex", acceptance: .pending)
        ]

        let names = trip.collaborators.map(\.displayName)
        #expect(names == ["Priya", "Zoe", "Alex"])
    }

    @Test func joinedPeopleSortAheadOfPendingInvites() {
        let trip = Trip(origin: .sfo, destination: .jfk)
        trip.participantSummaries = [
            ShareParticipantSummary(name: "Alex", acceptance: .pending),
            ShareParticipantSummary(name: "Zoe", acceptance: .accepted)
        ]
        #expect(trip.collaborators.map(\.displayName) == ["Zoe", "Alex"])
    }

    // MARK: Participant display

    @Test func participantsFallBackFromNameToHandle() {
        let invited = ShareParticipantSummary(handle: "alex@example.com")
        #expect(invited.displayName == "alex@example.com")

        let anonymous = ShareParticipantSummary()
        #expect(anonymous.displayName == "Guest")
    }

    @Test func shortNameTakesTheFirstWord() {
        let person = ShareParticipantSummary(name: "Priya Ramachandran")
        #expect(person.shortName == "Priya")
    }

    // MARK: iCloud sync state

    /// Drives the small cloud badge on the trip card and detail header.

    @Test func aBrandNewTripIsPending() {
        let trip = Trip(origin: .sfo, destination: .jfk)
        #expect(trip.syncState == .pending)
    }

    @Test func aConfirmedTripReadsAsSaved() {
        let trip = Trip(origin: .sfo, destination: .jfk)
        trip.syncedAt = trip.updatedAt
        #expect(trip.syncState == .saved)
    }

    @Test func editingAfterUploadReturnsToPending() {
        let trip = Trip(origin: .sfo, destination: .jfk)
        trip.syncedAt = trip.updatedAt
        trip.touch(trip.updatedAt.addingTimeInterval(30))
        #expect(trip.syncState == .pending)
    }

    /// A leg edited but not uploaded means the trip isn't fully saved, even
    /// though the trip record itself is — that's the case a trip-only check
    /// would report as saved while an edit was still sitting on the device.
    @Test func anUnsyncedLegKeepsTheWholeTripPending() {
        let trip = Trip.make(segments: [TripSegment(origin: .sfo, destination: .jfk)])
        trip.syncedAt = trip.updatedAt
        #expect(trip.syncState == .pending)

        for segment in trip.segments { segment.syncedAt = segment.updatedAt }
        #expect(trip.syncState == .saved)
    }

    /// Demo trips never sync by design, so the badge stays away entirely rather
    /// than reporting them as unsaved.
    @Test func sampleTripsReadAsLocalOnly() {
        let trip = Trip(origin: .sfo, destination: .jfk)
        trip.isSample = true
        #expect(trip.syncState == .localOnly)

        trip.syncedAt = trip.updatedAt
        #expect(trip.syncState == .localOnly)
    }

    // MARK: iCloud availability

    /// Without an account nothing can upload, ever — which is a different thing
    /// from an upload that just hasn't happened yet, and the only one of the two
    /// worth acting on.
    @Test func pendingBecomesUnavailableWithoutAnAccount() {
        let trip = Trip(origin: .sfo, destination: .jfk)
        #expect(trip.syncState == .pending)
        #expect(trip.syncState.resolved(cloudAvailable: false) == .unavailable)
        #expect(trip.syncState.resolved(cloudAvailable: true) == .pending)
    }

    /// A trip already on the server stays saved whether or not this device is
    /// signed in right now — the data didn't go anywhere.
    @Test func savedStaysSavedWithoutAnAccount() {
        let trip = Trip(origin: .sfo, destination: .jfk)
        trip.syncedAt = trip.updatedAt
        #expect(trip.syncState.resolved(cloudAvailable: false) == .saved)
    }

    @Test func demoTripsAreUnaffectedByAccountStatus() {
        let trip = Trip(origin: .sfo, destination: .jfk)
        trip.isSample = true
        #expect(trip.syncState.resolved(cloudAvailable: false) == .localOnly)
        #expect(trip.syncState.resolved(cloudAvailable: true) == .localOnly)
    }

    @Test func theOwnerCountsAsAbleToEditWhateverThePermissionSays() {
        let owner = ShareParticipantSummary(name: "Priya", permission: .readOnly, isOwner: true)
        #expect(owner.canEdit)
    }
}
