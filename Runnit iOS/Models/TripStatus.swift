//
//  TripStatus.swift
//  Runnit iOS
//
//  What is happening on this trip *right now*. A trip is a list of legs with
//  planned times; this collapses that, plus whatever live snapshots exist, into
//  the single thing a traveler in motion wants to know: which leg am I on, how
//  far through it am I, when do I get there, and what comes next.
//
//  Live records sharpen the answer where they exist (a delayed arrival moves the
//  finish line) and are simply absent otherwise, so a road trip with nothing but
//  two timestamps still gets a phase and a progress bar. Plain values: no
//  SwiftData writes, no views, no fetching — build one, read it, throw it away.
//

import Foundation

struct TripStatus {

    // MARK: Tuning

    /// How long before the first departure a trip starts reading as "active".
    /// Roughly when you'd be heading to the airport, and when a gate is worth
    /// putting on screen.
    static let leadTime: TimeInterval = 4 * 3600

    /// How long after the final arrival the status still shows, so "Landed" is
    /// there while you're walking to baggage claim.
    static let settleTime: TimeInterval = 2 * 3600

    /// Assumed length of an open-ended final leg — a drive, usually, entered with
    /// a departure and no arrival. Nothing else can bound the trip, and a leg that
    /// never ends would pin the card to the screen forever.
    static let openEndedDuration: TimeInterval = 3 * 3600

    /// Where the traveler is in the journey.
    enum Phase {
        /// The next leg hasn't left yet, and it's close enough to care.
        case boarding(TripSegment)
        /// Under way on this leg.
        case inTransit(TripSegment)
        /// On the ground between two legs — a layover, or any gap between modes.
        case waiting(arrived: TripSegment, next: TripSegment)
        /// The last leg is done.
        case arrived(TripSegment)

        /// The legs this phase names, in order — the whole of its identity.
        var legs: [TripSegment] {
            switch self {
            case .boarding(let s), .inTransit(let s), .arrived(let s): return [s]
            case .waiting(let arrived, let next):                      return [arrived, next]
            }
        }

        /// A stable name for the case, so equality doesn't hinge on the payload.
        fileprivate var kind: String {
            switch self {
            case .boarding:  return "boarding"
            case .inTransit: return "inTransit"
            case .waiting:   return "waiting"
            case .arrived:   return "arrived"
            }
        }
    }

    let phase: Phase
    let now: Date

    private let segments: [TripSegment]
    private let records: [FlightStatusRecord]

    /// The trip's status now, or nil when the trip isn't happening yet (further
    /// out than `leadTime`) or is well and truly over (past `settleTime`). A nil
    /// status is the signal to show no live card at all.
    init?(trip: Trip, records: [FlightStatusRecord] = [], now: Date = Date()) {
        let segments = trip.displaySegments
        guard let first = segments.first, let last = segments.last else { return nil }

        let start = Self.departure(of: first, records: records, now: now)
        guard now >= start.addingTimeInterval(-Self.leadTime) else { return nil }

        let finish = Self.end(ofLegAt: segments.count - 1, in: segments, records: records, now: now)
        guard now <= finish.addingTimeInterval(Self.settleTime) else { return nil }

        self.segments = segments
        self.records = records
        self.now = now

        // The leg you're on (or have most recently been on) is the last one that
        // has already pushed back. Before that, you're still waiting on the first.
        guard let index = segments.lastIndex(where: {
            Self.departure(of: $0, records: records, now: now) <= now
        }) else {
            phase = .boarding(first)
            return
        }

        let current = segments[index]
        if now < Self.end(ofLegAt: index, in: segments, records: records, now: now) {
            phase = .inTransit(current)
        } else if index + 1 < segments.count {
            phase = .waiting(arrived: current, next: segments[index + 1])
        } else {
            phase = .arrived(last)
        }
    }

    // MARK: Times

    /// When the trip is effectively over, sharpened by whatever live snapshots
    /// exist: the last leg's actual or estimated arrival when a record has one,
    /// its planned arrival otherwise, with the open-ended assumption as the
    /// final fallback. This is the clock Upcoming/Past classification runs on —
    /// planned times alone can be hours wrong in either direction (a flight
    /// that landed early is over; a delayed one is not).
    static func effectiveEnd(of trip: Trip, records: [FlightStatusRecord], now: Date = Date()) -> Date {
        let segments = trip.displaySegments
        guard !segments.isEmpty else { return trip.endDate }
        return end(ofLegAt: segments.count - 1, in: segments, records: records, now: now)
    }

    /// The live snapshot for a leg, only when it should drive the UI.
    private static func record(
        for segment: TripSegment, records: [FlightStatusRecord], now: Date
    ) -> FlightStatusRecord? {
        records.first { $0.segmentID == segment.id && $0.isDisplayable(for: segment, now: now) }
    }

    private func record(for segment: TripSegment) -> FlightStatusRecord? {
        Self.record(for: segment, records: records, now: now)
    }

    /// When this leg actually leaves: the best fact available, newest first.
    private static func departure(
        of segment: TripSegment, records: [FlightStatusRecord], now: Date
    ) -> Date {
        let live = record(for: segment, records: records, now: now)
        return live?.depActual ?? live?.depEstimated ?? segment.departureDate
    }

    func departure(of segment: TripSegment) -> Date {
        Self.departure(of: segment, records: records, now: now)
    }

    /// When this leg actually arrives, or nil when nobody knows — a drive entered
    /// without an arrival time has no answer, and guessing one would be a lie.
    private static func arrival(
        of segment: TripSegment, records: [FlightStatusRecord], now: Date
    ) -> Date? {
        let live = record(for: segment, records: records, now: now)
        return live?.arrActual ?? live?.arrEstimated ?? segment.arrivalDate
    }

    func arrival(of segment: TripSegment) -> Date? {
        Self.arrival(of: segment, records: records, now: now)
    }

    /// The times originally booked, kept so a change can be shown against them.
    func scheduledDeparture(of segment: TripSegment) -> Date { segment.departureDate }
    func scheduledArrival(of segment: TripSegment) -> Date? { segment.arrivalDate }

    /// When a leg stops being the current one. An arrival if it has one; failing
    /// that the next leg's departure (you can't still be driving once you're on a
    /// train); failing that, an assumption.
    private static func end(
        ofLegAt index: Int, in segments: [TripSegment],
        records: [FlightStatusRecord], now: Date
    ) -> Date {
        let segment = segments[index]
        if let arrival = arrival(of: segment, records: records, now: now) { return arrival }
        if index + 1 < segments.count {
            return departure(of: segments[index + 1], records: records, now: now)
        }
        return departure(of: segment, records: records, now: now)
            .addingTimeInterval(openEndedDuration)
    }

    // MARK: The leg in focus

    /// The leg this status is about: the one you're on, or the one you're waiting
    /// for. Everything else on the card hangs off it.
    var focusSegment: TripSegment {
        switch phase {
        case .boarding(let segment):   return segment
        case .inTransit(let segment):  return segment
        case .waiting(_, let next):    return next
        case .arrived(let segment):    return segment
        }
    }

    /// The leg after the one in focus, when there is one.
    var followingSegment: TripSegment? {
        guard case .inTransit(let current) = phase,
              let index = segments.firstIndex(where: { $0.id == current.id }),
              index + 1 < segments.count
        else { return nil }
        return segments[index + 1]
    }

    /// The live delay worth reporting: on the arrival while under way (that's the
    /// number that changes your plans), on the departure while still waiting.
    var delayMinutes: Int? {
        let live = record(for: focusSegment)
        switch phase {
        case .inTransit, .arrived:  return live?.arrDelayMinutes ?? live?.depDelayMinutes
        case .boarding, .waiting:   return live?.depDelayMinutes
        }
    }

    /// True when a leg of this trip is cancelled — outranks every other reading.
    var isCancelled: Bool { record(for: focusSegment)?.phase == .cancelled }

    // MARK: Progress

    /// How far through the current stretch we are, 0 to 1 — the leg while flying,
    /// the layover while on the ground, the countdown while waiting to leave. Nil
    /// when the stretch has no known end, which is the signal to draw no bar
    /// rather than a fake one.
    var progress: Double? {
        switch phase {
        case .boarding(let segment):
            let departs = departure(of: segment)
            return fraction(from: departs.addingTimeInterval(-Self.leadTime), to: departs)
        case .inTransit(let segment):
            guard let arrives = arrival(of: segment) else { return nil }
            return fraction(from: departure(of: segment), to: arrives)
        case .waiting(let arrived, let next):
            guard let landed = arrival(of: arrived) else { return nil }
            return fraction(from: landed, to: departure(of: next))
        case .arrived:
            return 1
        }
    }

    private func fraction(from start: Date, to end: Date) -> Double? {
        let span = end.timeIntervalSince(start)
        guard span > 0 else { return nil }
        return min(max(now.timeIntervalSince(start) / span, 0), 1)
    }

    /// The absolute time window the current progress spans, when it has one.
    /// Mirrors `progress` exactly, but returns the endpoints rather than the
    /// fraction — so a Live Activity can drive a self-updating bar from a single
    /// update, no per-minute pushes needed.
    var progressInterval: (start: Date, end: Date)? {
        switch phase {
        case .boarding(let segment):
            let departs = departure(of: segment)
            return (departs.addingTimeInterval(-Self.leadTime), departs)
        case .inTransit(let segment):
            guard let arrives = arrival(of: segment) else { return nil }
            return (departure(of: segment), arrives)
        case .waiting(let arrived, let next):
            guard let landed = arrival(of: arrived) else { return nil }
            return (landed, departure(of: next))
        case .arrived:
            return nil
        }
    }

    /// Time left in the current stretch, for the countdown line.
    var timeRemaining: TimeInterval? {
        let target: Date?
        switch phase {
        case .boarding(let segment):        target = departure(of: segment)
        case .inTransit(let segment):       target = arrival(of: segment)
        case .waiting(_, let next):         target = departure(of: next)
        case .arrived:                      target = nil
        }
        guard let target else { return nil }
        let remaining = target.timeIntervalSince(now)
        return remaining > 0 ? remaining : nil
    }
}

// MARK: - Equality

/// Two phases match when they name the same case over the same legs. Compared by
/// leg id rather than by object, so a phase built from a re-fetched trip still
/// equals one built from the original.
extension TripStatus.Phase: Equatable {
    static func == (lhs: TripStatus.Phase, rhs: TripStatus.Phase) -> Bool {
        lhs.kind == rhs.kind && lhs.legs.map(\.id) == rhs.legs.map(\.id)
    }
}
