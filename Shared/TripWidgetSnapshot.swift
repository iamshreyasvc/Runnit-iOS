//
//  TripWidgetSnapshot.swift
//  Runnit iOS  +  RunnitWidgets  (shared — add to BOTH targets)
//
//  The Home Screen / Lock Screen widget can't reach into SwiftData directly
//  without recreating the whole store, so the app instead writes a tiny snapshot
//  of the trips worth showing into a shared App Group container, and the widget
//  reads just that. This is the shape of that snapshot.
//
//  IMPORTANT (Xcode setup): add this file to both targets, and enable the App
//  Group `group.Runnit.Runnit-iOS` on each. See SETUP.md.
//

import Foundation

/// Where the app and widget meet: the App Group and the key the snapshot lives
/// under.
enum WidgetSharing {
    static let appGroup = "group.Runnit.Runnit-iOS"
    static let snapshotKey = "runnit.widget.snapshot"

    /// Shared defaults, falling back to standard if the group isn't configured yet
    /// (so a missing entitlement degrades to "no data" rather than crashing).
    static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroup) ?? .standard
    }
}

/// A handful of trips distilled for the widget — soonest first, an underway trip
/// ahead of merely upcoming ones.
struct TripWidgetSnapshot: Codable, Hashable {
    var generatedAt: Date
    var trips: [Entry]

    struct Entry: Codable, Hashable, Identifiable {
        var tripID: String
        var id: String { tripID }

        var title: String
        var originCode: String
        var destinationCode: String
        var originName: String
        var destinationName: String
        var mode: TripActivityAttributes.Mode

        var departureDate: Date
        var arrivalDate: Date?

        /// True when the trip is happening right now.
        var isUnderway: Bool
        /// A live one-liner while underway (e.g. "In Flight"), else nil.
        var headline: String?
    }

    static let empty = TripWidgetSnapshot(generatedAt: .distantPast, trips: [])

    // MARK: Codec

    func encoded() -> Data? { try? JSONEncoder().encode(self) }

    static func decode(_ data: Data) -> TripWidgetSnapshot? {
        try? JSONDecoder().decode(TripWidgetSnapshot.self, from: data)
    }

    /// Load the current snapshot from the shared container, or `.empty`.
    static func load() -> TripWidgetSnapshot {
        guard let data = WidgetSharing.defaults.data(forKey: WidgetSharing.snapshotKey),
              let snapshot = decode(data) else { return .empty }
        return snapshot
    }
}
