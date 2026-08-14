//
//  ShareParticipantSummary.swift
//  Runnit iOS
//
//  A person on a shared trip, flattened into a Codable value stored on the Trip.
//
//  CloudKit's own CKShare.Participant is the source of truth, but it lives on a
//  CKShare that only exists after a network round-trip. Mirroring the parts the
//  UI needs onto the Trip means the participant stack and the roster render
//  instantly and offline — the same reason the trip carries a denormalized
//  summary of its segments.
//

import Foundation

/// What a participant is allowed to do with a shared trip.
enum SharePermission: String, Codable, CaseIterable, Identifiable {
    case readOnly
    case readWrite

    var id: String { rawValue }

    var label: String {
        switch self {
        case .readOnly:  return "Can view"
        case .readWrite: return "Can edit"
        }
    }

    /// The one-line explanation shown under the picker while inviting.
    var blurb: String {
        switch self {
        case .readOnly:  return "They'll see everything, but can't change it."
        case .readWrite: return "They can add legs, edit times, and add stops."
        }
    }

    var symbol: String {
        switch self {
        case .readOnly:  return "eye.fill"
        case .readWrite: return "pencil"
        }
    }
}

/// Where a participant is in the invite lifecycle.
enum ShareAcceptance: String, Codable {
    case pending
    case accepted
    case removed

    var label: String {
        switch self {
        case .pending:  return "Invited"
        case .accepted: return "Joined"
        case .removed:  return "Removed"
        }
    }
}

/// One person on a shared trip, as the UI needs them.
struct ShareParticipantSummary: Codable, Hashable, Identifiable {
    var id = UUID()
    /// Display name from the participant's contact record, when CloudKit gives
    /// us one. Invitees who haven't accepted often have only a handle.
    var name: String?
    /// The email or phone the invite was sent to.
    var handle: String?
    private var permissionRaw: String = SharePermission.readOnly.rawValue
    private var acceptanceRaw: String = ShareAcceptance.pending.rawValue
    /// True for the row representing the person using this device.
    var isCurrentUser: Bool = false
    /// True for the trip's owner, who always has full access.
    var isOwner: Bool = false

    init(
        id: UUID = UUID(),
        name: String? = nil,
        handle: String? = nil,
        permission: SharePermission = .readOnly,
        acceptance: ShareAcceptance = .pending,
        isCurrentUser: Bool = false,
        isOwner: Bool = false
    ) {
        self.id = id
        self.name = name
        self.handle = handle
        self.permissionRaw = permission.rawValue
        self.acceptanceRaw = acceptance.rawValue
        self.isCurrentUser = isCurrentUser
        self.isOwner = isOwner
    }

    var permission: SharePermission {
        get { SharePermission(rawValue: permissionRaw) ?? .readOnly }
        set { permissionRaw = newValue.rawValue }
    }

    var acceptance: ShareAcceptance {
        get { ShareAcceptance(rawValue: acceptanceRaw) ?? .pending }
        set { acceptanceRaw = newValue.rawValue }
    }

    /// The owner always counts as able to edit, whatever the stored permission.
    var canEdit: Bool { isOwner || permission == .readWrite }

    /// Best available label: their name, else the handle, else something neutral.
    var displayName: String {
        if let name, !name.isEmpty { return name }
        if let handle, !handle.isEmpty { return handle }
        return "Guest"
    }

    /// Just the first name, for possessive phrasing like "Priya's Flight".
    var shortName: String {
        displayName.split(separator: " ").first.map(String.init) ?? displayName
    }
}
