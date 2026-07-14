//
//  Connection.swift
//  Runnit iOS
//
//  A connection is two consecutive flight legs that meet at the same airport.
//  This file models the one thing that matters there: how long you actually have
//  between landing and boarding, and whether that's enough.
//
//  Gates, terminals, and delay minutes only exist on FlightStatusRecord (live API
//  data) — a TripSegment only carries a departure boarding point. So a Connection
//  reads records where it has them and degrades to the scheduled leg times where
//  it doesn't. Plain values: no SwiftData, no views, so it stays unit-testable.
//

import Foundation
import CoreLocation

// MARK: - Pairing

extension Trip {
    /// Consecutive `.flight` legs that meet at the same airport.
    var connectionPairs: [(inbound: TripSegment, outbound: TripSegment)] {
        Connection.pairs(in: displaySegments)
    }

    /// True when the trip contains at least one connection.
    var isConnecting: Bool { !connectionPairs.isEmpty }
}

// MARK: - Connection

struct Connection: Identifiable {
    /// Minimum time we consider workable for a same-terminal connection.
    static let baseMinimumConnectionMinutes = 45
    /// Extra time demanded when the traveler has to change terminals.
    static let terminalChangeExtraMinutes = 20
    /// Above `requiredMinutes` but within this margin still reads as "tight".
    static let tightMarginMinutes = 30

    let inbound: TripSegment
    let outbound: TripSegment
    /// Live snapshots, already filtered to displayable ones by the caller.
    let inboundStatus: FlightStatusRecord?
    let outboundStatus: FlightStatusRecord?

    var id: UUID { outbound.id }

    init(
        inbound: TripSegment,
        outbound: TripSegment,
        inboundStatus: FlightStatusRecord? = nil,
        outboundStatus: FlightStatusRecord? = nil
    ) {
        self.inbound = inbound
        self.outbound = outbound
        self.inboundStatus = inboundStatus
        self.outboundStatus = outboundStatus
    }

    /// Build from an unfiltered pool of records (e.g. a `@Query` result), keeping
    /// only the snapshots that should actually drive the UI.
    init(
        inbound: TripSegment,
        outbound: TripSegment,
        records: [FlightStatusRecord],
        now: Date = Date()
    ) {
        func displayable(for segment: TripSegment) -> FlightStatusRecord? {
            records.first { $0.segmentID == segment.id && $0.isDisplayable(for: segment, now: now) }
        }
        self.init(
            inbound: inbound,
            outbound: outbound,
            inboundStatus: displayable(for: inbound),
            outboundStatus: displayable(for: outbound)
        )
    }

    /// Connecting pairs within any ordered list of legs. Takes plain segments, so
    /// the trip editors can run it on unsaved drafts exactly as the detail screen
    /// runs it on a stored trip.
    static func pairs(in segments: [TripSegment]) -> [(inbound: TripSegment, outbound: TripSegment)] {
        guard segments.count > 1 else { return [] }
        return zip(segments, segments.dropFirst())
            .filter { isConnection(inbound: $0.0, outbound: $0.1) }
            .map { (inbound: $0.0, outbound: $0.1) }
    }

    /// Two legs connect when both fly and the first one lands where the second departs.
    static func isConnection(inbound: TripSegment, outbound: TripSegment) -> Bool {
        guard inbound.type == .flight, outbound.type == .flight else { return false }
        return isSameAirport(inbound.destination, outbound.origin)
    }

    /// Same airport by IATA code when both places carry one, else by proximity.
    static func isSameAirport(_ lhs: Place, _ rhs: Place) -> Bool {
        if let a = FlightIdentityParser.iataCode(from: lhs),
           let b = FlightIdentityParser.iataCode(from: rhs) {
            return a == b
        }
        return lhs.clLocation.distance(from: rhs.clLocation) < 2_000
    }

    // MARK: Where

    /// The airport you connect at.
    var airport: Place { outbound.origin }

    /// The clock at the hub. Both halves of a layover happen here, so both times
    /// are shown on this one clock — and the layover arithmetic is unaffected by
    /// timezones either way, since it's a difference of two instants.
    var timeZone: TimeZone? {
        inboundStatus?.arrTimeZone ?? outboundStatus?.depTimeZone ?? airport.timeZone
    }

    var arrivalTerminal: String? { inboundStatus?.arrTerminal }
    var arrivalGate: String? { inboundStatus?.arrGate }
    var departureTerminal: String? { outboundStatus?.depTerminal }
    /// The live gate when known, else whatever the traveler typed on the leg.
    var departureGate: String? { outboundStatus?.depGate ?? outbound.boardingPoint }

    /// True only when both terminals are known and they differ.
    var isTerminalChange: Bool {
        guard let arr = normalized(arrivalTerminal), let dep = normalized(departureTerminal) else {
            return false
        }
        return arr != dep
    }

    private func normalized(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespaces), !trimmed.isEmpty else {
            return nil
        }
        return trimmed.uppercased()
    }

    // MARK: When

    var scheduledArrival: Date? { inboundStatus?.arrScheduled ?? inbound.arrivalDate }
    var scheduledDeparture: Date { outboundStatus?.depScheduled ?? outbound.departureDate }

    /// When you actually land: the best fact available, newest first.
    var effectiveArrival: Date? {
        inboundStatus?.arrActual ?? inboundStatus?.arrEstimated
            ?? inboundStatus?.arrScheduled ?? inbound.arrivalDate
    }

    /// When your outbound actually leaves.
    var effectiveDeparture: Date {
        outboundStatus?.depActual ?? outboundStatus?.depEstimated
            ?? outboundStatus?.depScheduled ?? outbound.departureDate
    }

    /// The layover you booked.
    var scheduledLayover: TimeInterval? {
        scheduledArrival.map { scheduledDeparture.timeIntervalSince($0) }
    }

    /// The layover you're actually going to get.
    var effectiveLayover: TimeInterval? {
        effectiveArrival.map { effectiveDeparture.timeIntervalSince($0) }
    }

    /// How much the layover moved — negative when it shrank.
    var layoverDelta: TimeInterval? {
        guard let scheduled = scheduledLayover, let effective = effectiveLayover else { return nil }
        return effective - scheduled
    }

    /// True when the layover changed enough to be worth showing the original.
    var didLayoverChange: Bool { abs(layoverDelta ?? 0) > 60 }

    /// Arrival delay on the inbound leg, the usual reason a connection tightens.
    var inboundDelayMinutes: Int? { inboundStatus?.arrDelayMinutes }

    // MARK: Risk

    /// Minutes we need on the ground here: a floor, plus a terminal-change penalty.
    var requiredMinutes: Int {
        Self.baseMinimumConnectionMinutes + (isTerminalChange ? Self.terminalChangeExtraMinutes : 0)
    }

    var risk: ConnectionRisk {
        if inboundStatus?.phase == .cancelled || outboundStatus?.phase == .cancelled {
            return .cancelled
        }
        guard let layover = effectiveLayover else { return .unknown }
        if layover <= 0 { return .missed }
        let minutes = layover / 60
        if minutes < Double(requiredMinutes) { return .atRisk }
        if minutes < Double(requiredMinutes + Self.tightMarginMinutes) { return .tight }
        return .comfortable
    }

    /// One sentence naming why this connection looks the way it does.
    var advisory: String {
        switch risk {
        case .comfortable, .unknown, .missed, .cancelled:
            return risk.message
        case .tight, .atRisk:
            var reasons: [String] = []
            if let delay = inboundDelayMinutes, delay > 0 {
                reasons.append("Inbound is \(delay) min late")
            }
            if isTerminalChange {
                reasons.append(reasons.isEmpty ? "You change terminals" : "you change terminals")
            }
            guard !reasons.isEmpty else { return risk.message }
            return reasons.joined(separator: " and ") + "."
        }
    }
}

// MARK: - Risk

enum ConnectionRisk {
    case comfortable
    case tight
    case atRisk
    case missed
    case cancelled
    case unknown

    var label: String {
        switch self {
        case .comfortable: return "Comfortable"
        case .tight:       return "Tight connection"
        case .atRisk:      return "At risk"
        case .missed:      return "Missed"
        case .cancelled:   return "Cancelled"
        case .unknown:     return "Layover"
        }
    }

    var systemImage: String {
        switch self {
        case .comfortable: return "checkmark.circle.fill"
        case .tight:       return "timer"
        case .atRisk:      return "exclamationmark.triangle.fill"
        case .missed:      return "xmark.octagon.fill"
        case .cancelled:   return "xmark.octagon.fill"
        case .unknown:     return "questionmark.circle"
        }
    }

    /// Generic advice, used when there's nothing more specific to say.
    var message: String {
        switch self {
        case .comfortable: return "You have room to spare at this stop."
        case .tight:       return "Head straight for your next gate after landing."
        case .atRisk:      return "This connection is shorter than the airport usually needs."
        case .missed:      return "Your outbound has already departed — contact the airline to rebook."
        case .cancelled:   return "A leg of this connection is cancelled — contact the airline to rebook."
        case .unknown:     return "We don't have enough timing detail to judge this layover yet."
        }
    }

    /// Worth pulling to the top of the trip screen.
    var isUrgent: Bool {
        self == .atRisk || self == .missed || self == .cancelled
    }
}
