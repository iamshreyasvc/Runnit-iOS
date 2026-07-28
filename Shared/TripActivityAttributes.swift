//
//  TripActivityAttributes.swift
//  Runnit iOS  +  RunnitWidgets  (shared — add to BOTH targets)
//
//  The contract between the app (which starts, updates, and ends a Live Activity)
//  and the widget extension (which draws it). Deliberately free of SwiftUI and of
//  any app model type: colors and modes travel as small enums the widget maps to
//  real `Color`s and SF Symbols, so nothing here drags UIKit/SwiftUI into the
//  attributes payload that ActivityKit serializes.
//
//  IMPORTANT (Xcode setup): this one file must belong to the app target AND the
//  widget-extension target. See SETUP.md.
//

import Foundation
import ActivityKit

struct TripActivityAttributes: ActivityAttributes {

    // MARK: Static for the life of the activity

    /// Identifies which trip this activity is for, so the app can find and update
    /// the right one.
    let tripID: String
    /// Overall route endpoints — short codes for the compact chrome, full names
    /// for the expanded view.
    let originCode: String
    let destinationCode: String
    let originName: String
    let destinationName: String
    /// The trip's primary mode, used for the static icon if a leg mode is absent.
    let overallMode: Mode

    // MARK: Live, replaced on every update

    struct ContentState: Codable, Hashable {
        /// The one-line status, e.g. "In Flight" / "Boarding Soon" / "Landed".
        var headline: String
        /// The line beneath it — the vehicle, or where you are.
        var subtitle: String?
        /// Where the traveler is in the journey.
        var phase: Phase
        /// The leg currently in focus, for the mode icon and coloring.
        var legMode: Mode
        /// The accent color, chosen by the app from delay/phase/mode.
        var tint: Accent

        /// The two ends of the progress bar (codes + times).
        var departureCode: String
        var arrivalCode: String
        var departureTime: Date?
        var arrivalTime: Date?

        /// Absolute window the progress bar spans, so the widget can animate a
        /// self-updating `ProgressView(timerInterval:)` between updates.
        var rangeStart: Date?
        var rangeEnd: Date?

        /// Minutes late, when running behind.
        var delayMinutes: Int?
        /// The punctuality pill, e.g. "On time" / "+35m late" / "Arrived".
        var punctuality: String
        /// True only while actually moving — drives the breathing dot.
        var isUnderway: Bool
    }

    // MARK: Small, SwiftUI-free enums

    enum Mode: String, Codable, Hashable {
        case flight, train, roadTrip, other

        /// SF Symbol for the mode — resolved here so both targets agree.
        var symbol: String {
            switch self {
            case .flight:   return "airplane"
            case .train:    return "tram.fill"
            case .roadTrip: return "car.fill"
            case .other:    return "location.fill"
            }
        }
    }

    enum Phase: String, Codable, Hashable {
        case boarding, inTransit, waiting, arrived
    }

    /// A named accent the widget maps to a real `Color`. Kept to the palette the
    /// live status card already uses.
    enum Accent: String, Codable, Hashable {
        case blue, orange, green, purple, red, cyan
    }
}
