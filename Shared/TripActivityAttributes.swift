//
//  TripActivityAttributes.swift
//  Runnit iOS · Shared with RunnitWidgets
//
//  The contract between the app and the Live Activity. The widget extension runs
//  in its own process with no SwiftData store, so nothing model-shaped crosses
//  this line: the app reads a `TripStatus` and hands over the *already-decided*
//  reading — the words, the icon, the color, the fraction. The widget only draws.
//
//  Everything here is Codable and small, because ActivityKit ships it between
//  processes on every update.
//
//  ActivityKit is iPhone-only, and the app builds for Mac and Vision too, so the
//  whole live-activity feature sits behind `os(iOS)` from here outward.
//

#if os(iOS)

import Foundation
import ActivityKit

/// The palette the live card draws from. `Color` isn't Codable, and the widget
/// shouldn't be second-guessing which mode is which color, so the app resolves
/// the tint to one of these and sends the name.
enum TripActivityAccent: String, Codable, Hashable, Sendable {
    case blue, orange, green, red, purple
}

struct TripActivityAttributes: ActivityAttributes {

    /// Everything that changes while the trip is under way. Mirrors one row of
    /// the app's "Happening Now" box, field for field.
    struct ContentState: Codable, Hashable, Sendable {
        /// "In Flight", "Layover", "Boarding Soon", "Landed"…
        var headline: String
        /// The trip's display title, under the headline.
        var tripTitle: String
        /// The right-hand pill: "On time", "+55m late", "Arrived".
        var punctuality: String
        /// Drives the puck, the bar fill, and the punctuality text.
        var accent: TripActivityAccent
        /// SF Symbol riding the progress bar.
        var icon: String
        /// How far through the current stretch, 0…1. Nil draws an empty track,
        /// exactly as in the app — a leg with no known end gets no fake bar.
        var progress: Double?

        /// The stretch the countdown is measuring, so the widget can tick down
        /// on its own between updates rather than freezing on a stale string.
        var countdownStart: Date?
        var countdownEnd: Date?
        /// Words wrapped around the ticking clock: "Departs in ⏱", "⏱ left".
        var countdownPrefix: String
        var countdownSuffix: String
        /// Shown instead of a clock when there's nothing left to count ("Complete").
        var countdownFallback: String?

        /// The bar's two ends and the arrival line between them.
        var startCode: String
        var endCode: String
        var endTitle: String
        /// Preformatted on the clock at the place it happens, like the app does.
        var endTime: String?
        var endIsLate: Bool

        /// The countdown's range, when both ends are known and still ahead.
        var countdownRange: ClosedRange<Date>? {
            guard let countdownStart, let countdownEnd, countdownEnd > countdownStart else {
                return nil
            }
            return countdownStart...countdownEnd
        }
    }

    /// Which trip this card is about — the key the app syncs on, and the value
    /// a tap on the card carries back so the right trip opens.
    var tripID: UUID
}

#endif
