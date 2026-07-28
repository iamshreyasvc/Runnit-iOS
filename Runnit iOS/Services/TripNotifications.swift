//
//  TripNotifications.swift
//  Runnit iOS
//
//  Local notifications for upcoming trips. There's no server and no push here —
//  everything is scheduled on-device from the trips already stored, and torn
//  down and rebuilt whenever they change. Three kinds, each independently
//  switchable on the Account page:
//
//    • check-in   — a day before a flight, when online check-in typically opens;
//    • departure  — a few hours before the first leg leaves, time to head out;
//    • delay      — surfaced when the app already knows a tracked leg slipped
//                   (we compare each live record against the last delay we told
//                   the traveler about, so the same delay is never nagged twice).
//
//  Scheduling is fully declarative: `reschedule(for:)` clears every Runnit
//  request and re-adds the ones that still lie in the future, so it's safe to
//  call on every launch, foreground, and trip edit.
//

import Foundation
import UserNotifications
import SwiftData

@MainActor
enum TripNotifications {

    // MARK: Timing

    /// How far before departure the check-in nudge fires — a day, when most
    /// airlines open online check-in.
    private static let checkInLead: TimeInterval = 24 * 3600

    /// How far before the first leg the "head out" reminder fires. Mirrors
    /// `TripStatus.leadTime` so the notification lands exactly as the live card
    /// starts reading "active".
    private static let departureLead: TimeInterval = TripStatus.leadTime

    /// Prefix on every request we own, so we only ever clear our own.
    private static let idPrefix = "runnit."

    // MARK: Preferences

    private static var masterEnabled: Bool {
        UserDefaults.standard.bool(forKey: PrefKey.notificationsEnabled)
    }
    /// A per-kind switch, defaulting on when the key was never written — so
    /// turning notifications on lights up all three unless one was pared back.
    private static func kindEnabled(_ key: String) -> Bool {
        UserDefaults.standard.object(forKey: key) == nil
            ? true
            : UserDefaults.standard.bool(forKey: key)
    }

    // MARK: Authorization

    /// Ask for permission. Returns whether it's granted (or already was). Safe to
    /// call repeatedly — the system only prompts the first time.
    @discardableResult
    static func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        default:
            return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        }
    }

    // MARK: Scheduling

    /// Wipe every Runnit request and re-add the ones still ahead of us for the
    /// given trips. Idempotent: the state after the call depends only on the
    /// trips passed in, never on what was scheduled before.
    static func reschedule(for trips: [Trip]) async {
        let center = UNUserNotificationCenter.current()
        await clearAll(center)

        guard masterEnabled, await requestAuthorization() else { return }

        let now = Date()
        var requests: [UNNotificationRequest] = []

        for trip in trips where trip.isUpcoming {
            let legs = trip.displaySegments
            guard let first = legs.first else { continue }

            // One "head out" reminder per trip, keyed off its very first leg.
            if kindEnabled(PrefKey.notifyDeparture),
               let request = departureRequest(trip: trip, firstLeg: first, now: now) {
                requests.append(request)
            }

            // A check-in nudge for each scheduled-transit leg that supports it.
            if kindEnabled(PrefKey.notifyCheckIn) {
                for leg in legs where leg.type == .flight {
                    if let request = checkInRequest(trip: trip, leg: leg, now: now) {
                        requests.append(request)
                    }
                }
            }
        }

        for request in requests {
            try? await center.add(request)
        }
    }

    /// Remove every pending Runnit request. Leaves anything the app didn't create
    /// untouched (there is nothing else today, but the prefix keeps it honest).
    private static func clearAll(_ center: UNUserNotificationCenter) async {
        let pending = await center.pendingNotificationRequests()
        let ids = pending.map(\.identifier).filter { $0.hasPrefix(idPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    // MARK: Request builders

    private static func departureRequest(trip: Trip, firstLeg: TripSegment, now: Date) -> UNNotificationRequest? {
        let fireDate = firstLeg.departureDate.addingTimeInterval(-departureLead)
        guard fireDate > now else { return nil }

        let zone = firstLeg.origin.timeZone
        let content = UNMutableNotificationContent()
        content.title = "Time to head out"
        content.body = "\(verb(firstLeg.type)) to \(firstLeg.destination.displayName) departs at \(Format.time(firstLeg.departureDate, in: zone))."
        content.sound = .default
        content.threadIdentifier = threadID(trip)

        return request(id: "\(idPrefix)trip.\(trip.id.uuidString).depart",
                       content: content, fireDate: fireDate)
    }

    private static func checkInRequest(trip: Trip, leg: TripSegment, now: Date) -> UNNotificationRequest? {
        let fireDate = leg.departureDate.addingTimeInterval(-checkInLead)
        guard fireDate > now else { return nil }

        let flight = [leg.operatorName, leg.vehicleNumber]
            .compactMap { $0?.isEmpty == false ? $0 : nil }
            .joined(separator: " ")
        let who = flight.isEmpty ? "your flight to \(leg.destination.displayName)" : flight

        let content = UNMutableNotificationContent()
        content.title = "Check-in opens soon"
        content.body = "Check in for \(who) — it departs tomorrow at \(Format.time(leg.departureDate, in: leg.origin.timeZone))."
        content.sound = .default
        content.threadIdentifier = threadID(trip)

        return request(id: "\(idPrefix)flight.\(leg.id.uuidString).checkin",
                       content: content, fireDate: fireDate)
    }

    /// A calendar trigger to the minute — robust across relaunches and clock
    /// changes in a way a fixed time-interval trigger isn't.
    private static func request(id: String, content: UNMutableNotificationContent, fireDate: Date) -> UNNotificationRequest {
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        return UNNotificationRequest(identifier: id, content: content, trigger: trigger)
    }

    private static func threadID(_ trip: Trip) -> String { "\(idPrefix)trip.\(trip.id.uuidString)" }

    private static func verb(_ type: TripType) -> String {
        switch type {
        case .flight:   return "Your flight"
        case .train:    return "Your train"
        case .roadTrip: return "Your drive"
        case .other:    return "Your trip"
        }
    }

    // MARK: Delay alerts (surfaced from data the app already has)

    /// Fire a delay alert for any tracked leg whose known delay has grown since we
    /// last told the traveler. This reads only the live records already fetched —
    /// no network — so it's a way to *surface* a delay the moment the app learns
    /// of one, not a background poller. Call after a refresh and on foreground.
    static func surfaceDelays(for trips: [Trip], records: [FlightStatusRecord]) async {
        guard masterEnabled, kindEnabled(PrefKey.notifyDelays), await requestAuthorization() else { return }

        let defaults = UserDefaults.standard
        let now = Date()
        let bySegment = Dictionary(grouping: records, by: \.segmentID)

        for trip in trips {
            for leg in trip.displaySegments where leg.type == .flight {
                guard let record = bySegment[leg.id]?.first,
                      record.isDisplayable(for: leg, now: now),
                      let delay = record.arrDelayMinutes ?? record.depDelayMinutes,
                      delay > 0
                else { continue }

                let key = "\(idPrefix)delay.\(leg.id.uuidString)"
                let lastNotified = defaults.integer(forKey: key)
                // Only speak up when the delay is materially worse than last time
                // (or brand new) — a minute-by-minute creep shouldn't buzz.
                guard delay >= lastNotified + 10 else { continue }
                defaults.set(delay, forKey: key)

                let flight = [leg.operatorName, leg.vehicleNumber]
                    .compactMap { $0?.isEmpty == false ? $0 : nil }
                    .joined(separator: " ")
                let who = flight.isEmpty ? "Your flight to \(leg.destination.displayName)" : flight

                let content = UNMutableNotificationContent()
                content.title = "\(who) is delayed"
                content.body = "Now running about \(delay) min late\(record.arrDelayMinutes != nil ? " into \(leg.destination.displayName)" : "")."
                content.sound = .default
                content.threadIdentifier = threadID(trip)
                content.interruptionLevel = .timeSensitive

                let request = UNNotificationRequest(
                    identifier: "\(key).\(delay)",
                    content: content,
                    trigger: nil // deliver now
                )
                try? await UNUserNotificationCenter.current().add(request)
            }
        }
    }
}
