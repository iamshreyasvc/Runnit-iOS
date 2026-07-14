//
//  TripStatusCardView.swift
//  Runnit iOS
//
//  The "right now" card. It only exists while a trip is actually happening, and
//  it says the one thing that matters at that moment: In Flight, on the road,
//  sitting in a layover, or landed — with when you get there, how late that is,
//  and where you have to be next.
//
//  Everything it draws comes from `TripStatus` (pure) and cached
//  `FlightStatusRecord`s (read-only). It never fetches: the flight card below it
//  already owns that, and a live card that spent API credits just by scrolling
//  into view would be a trap.
//

import SwiftUI
import SwiftData

struct TripStatusCardView: View {
    let trip: Trip

    @Query private var records: [FlightStatusRecord]

    var body: some View {
        // Re-derived on a slow tick so the bar creeps, the countdown counts, and
        // "In Flight" becomes "Landed" without the traveler touching anything.
        TimelineView(.periodic(from: .now, by: 30)) { context in
            if let status = TripStatus(trip: trip, records: records, now: context.date) {
                card(status)
            }
        }
    }

    private func card(_ status: TripStatus) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            header(status)
            route(status)
            if let next = transfer(status) { Divider(); next }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(tint: status.tint.opacity(0.28))
    }

    // MARK: Header — the verdict, and whether it's going to plan.

    private func header(_ status: TripStatus) -> some View {
        HStack(spacing: 10) {
            LivePulse(color: status.tint, isAnimating: status.isUnderway)
            VStack(alignment: .leading, spacing: 1) {
                Text(status.headline)
                    .font(.headline)
                if let subtitle = status.subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            statusPill(status)
        }
    }

    private func statusPill(_ status: TripStatus) -> some View {
        let (text, color) = status.punctuality
        return Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(color.opacity(0.15), in: .capsule)
    }

    // MARK: Route — endpoints, the bar, and the clock at each end.

    private func route(_ status: TripStatus) -> some View {
        let ends = status.endpoints
        return VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(ends.start.code)
                    .font(.title3.weight(.bold))
                    .lineLimit(1)
                Spacer(minLength: 8)
                if let caption = status.countdown {
                    Text(caption)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Text(ends.end.code)
                    .font(.title3.weight(.bold))
                    .lineLimit(1)
                    .multilineTextAlignment(.trailing)
            }

            TripProgressTrack(progress: status.progress, icon: status.puckIcon, tint: status.tint)

            HStack(alignment: .top) {
                timeStack(ends.start, alignment: .leading)
                Spacer(minLength: 12)
                timeStack(ends.end, alignment: .trailing)
            }
        }
    }

    private func timeStack(_ end: TripStatus.Endpoint, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(end.title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            if let time = end.time {
                HStack(spacing: 5) {
                    Text(Format.time(time, in: end.zone))
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(end.isLate ? .orange : .primary)
                    if let zone = Format.zone(end.zone, at: time) {
                        Text(zone).font(.caption2).foregroundStyle(.tertiary)
                    }
                }
                // The time it was supposed to be, when that's no longer the time.
                if let scheduled = end.scheduled, abs(scheduled.timeIntervalSince(time)) > 60 {
                    Text(Format.time(scheduled, in: end.zone))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .strikethrough()
                }
            } else {
                Text("—").font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Transfer — what you have to do next, at a glance.

    /// The connection strip. Shown while waiting *in* a layover, and while still
    /// airborne on the leg that feeds one — that's exactly when knowing the next
    /// gate and how much slack you have is worth something.
    private func transfer(_ status: TripStatus) -> AnyView? {
        let pair: (inbound: TripSegment, outbound: TripSegment)?
        switch status.phase {
        case .waiting(let arrived, let next):
            pair = (arrived, next)
        case .inTransit(let current):
            pair = status.followingSegment.map { (current, $0) }
        case .boarding, .arrived:
            pair = nil
        }

        guard let pair else { return nil }

        if Connection.isConnection(inbound: pair.inbound, outbound: pair.outbound) {
            let connection = Connection(inbound: pair.inbound, outbound: pair.outbound,
                                        records: records, now: status.now)
            return AnyView(connectionStrip(connection))
        }
        return AnyView(nextLegStrip(pair.outbound, status: status))
    }

    private func connectionStrip(_ connection: Connection) -> some View {
        let risk = connection.risk
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: risk.systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(risk.color)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(risk.label)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(risk.color)
                    if let layover = connection.effectiveLayover, layover > 0 {
                        Text("· \(Format.duration(layover)) at \(connection.airport.shortCode)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                HStack(spacing: 6) {
                    if let number = connection.outbound.vehicleNumber, !number.isEmpty {
                        InfoChip("Next", number, tint: TripType.flight.accent)
                    }
                    if let gate = connection.departureGate {
                        InfoChip("Gate", gate, tint: TripType.flight.accent)
                    }
                    if connection.isTerminalChange, let terminal = connection.departureTerminal {
                        InfoChip("Terminal", terminal, tint: .orange)
                    }
                }
                Text(connection.advisory)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    /// A gap that isn't a flight connection — a train to catch, a car to pick up.
    private func nextLegStrip(_ next: TripSegment, status: TripStatus) -> some View {
        HStack(spacing: 10) {
            Image(systemName: next.type.symbol)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(next.type.gradient, in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                Text("Next · \(next.type.label) to \(next.destination.displayName)")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text("Departs \(Format.time(status.departure(of: next), in: next.origin.timeZone)) from \(next.origin.displayName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Pieces

/// The soft breathing dot that says this is live, not a stored number.
private struct LivePulse: View {
    let color: Color
    let isAnimating: Bool

    @State private var expanded = false

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.25))
                .frame(width: 26, height: 26)
                .scaleEffect(expanded ? 1 : 0.55)
                .opacity(expanded ? 0 : 1)
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
        }
        .frame(width: 26, height: 26)
        .onAppear {
            guard isAnimating else { return }
            withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) {
                expanded = true
            }
        }
    }
}

/// The progress bar: a track, a fill, and a little vehicle riding it. Draws no
/// fill at all when there's no known end — an honest blank beats a made-up bar.
/// Shared with the Upcoming tab's active box.
struct TripProgressTrack: View {
    let progress: Double?
    let icon: String
    let tint: Color

    /// A shorter bar for tighter rows (the active box on the Upcoming tab).
    var compact: Bool = false

    private var height: CGFloat { compact ? 6 : 8 }
    private var puck: CGFloat { compact ? 18 : 24 }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let value = progress ?? 0
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.quaternary)
                    .frame(height: height)
                if progress != nil {
                    Capsule()
                        .fill(tint.gradient)
                        .frame(width: max(width * value, height), height: height)
                    Image(systemName: icon)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: puck, height: puck)
                        .background(tint.gradient, in: .circle)
                        .shadow(color: tint.opacity(0.4), radius: 4, y: 2)
                        .offset(x: min(max(width * value - puck / 2, 0), width - puck))
                }
            }
            .frame(width: width, height: puck)
            .animation(.easeInOut(duration: 0.5), value: value)
        }
        .frame(height: puck)
    }
}

// MARK: - Presentation

extension Place {
    /// The airport code when this place has one, else a short name — the label
    /// that fits at either end of a progress bar.
    var shortCode: String {
        FlightIdentityParser.iataCode(from: self) ?? displayName
    }
}

extension TripStatus {
    /// One end of the progress bar.
    struct Endpoint {
        var code: String
        var title: String
        var time: Date?
        var scheduled: Date?
        var zone: TimeZone?
        var isLate: Bool = false
    }

    /// The mode driving the card's color: the leg you're on, or the one you're
    /// waiting for.
    private var mode: TripType { focusSegment.type }

    var tint: Color {
        if isCancelled { return .red }
        if (delayMinutes ?? 0) > 0 { return .orange }
        if case .arrived = phase { return .green }
        return mode.accent
    }

    /// True while actually moving — the only time the pulse should breathe.
    var isUnderway: Bool {
        if case .inTransit = phase { return true }
        return false
    }

    var headline: String {
        if isCancelled { return "Cancelled" }
        switch phase {
        case .boarding:
            let soon = (timeRemaining ?? 0) <= 3600
            switch mode {
            case .flight, .train:   return soon ? "Boarding Soon" : "Up Next"
            case .roadTrip:         return soon ? "Departing Soon" : "Up Next"
            case .other:            return soon ? "Departing Soon" : "Up Next"
            }
        case .inTransit:
            switch mode {
            case .flight:   return "In Flight"
            case .train:    return "On Board"
            case .roadTrip: return "On the Road"
            case .other:    return "In Transit"
            }
        case .waiting(let arrived, let next):
            return Connection.isConnection(inbound: arrived, outbound: next)
                ? "Layover" : "Between Legs"
        case .arrived:
            return mode == .flight ? "Landed" : "Arrived"
        }
    }

    /// The line under the headline: which vehicle this is about, or where you are.
    var subtitle: String? {
        switch phase {
        case .waiting(let arrived, _):
            return "At \(arrived.destination.displayName)"
        case .boarding, .inTransit, .arrived:
            let parts = [focusSegment.operatorName, focusSegment.vehicleNumber]
                .compactMap { $0?.isEmpty == false ? $0 : nil }
            if !parts.isEmpty { return parts.joined(separator: " · ") }
            return focusSegment.type == .roadTrip ? nil : focusSegment.displayTitle
        }
    }

    /// The pill on the right: is this going to plan or not.
    var punctuality: (String, Color) {
        if isCancelled { return ("Cancelled", .red) }
        if let delay = delayMinutes, delay > 0 { return ("+\(delay)m late", .orange) }
        if case .arrived = phase { return ("Arrived", .green) }
        return ("On time", mode.accent)
    }

    /// The countdown that sits above the bar.
    var countdown: String? {
        guard let remaining = timeRemaining else {
            if case .arrived = phase { return "Complete" }
            return nil
        }
        switch phase {
        case .boarding:     return "Departs in \(Format.duration(remaining))"
        case .inTransit:    return "\(Format.duration(remaining)) left"
        case .waiting:      return "\(Format.duration(remaining)) to boarding"
        case .arrived:      return "Complete"
        }
    }

    /// What rides the bar.
    var puckIcon: String {
        switch phase {
        case .waiting:              return "figure.walk"
        case .arrived:              return "checkmark"
        case .boarding, .inTransit: return mode.symbol
        }
    }

    /// The two ends of the bar. In a layover both ends are the same airport, so
    /// they become the two events that bracket it: when you landed, when you go.
    var endpoints: (start: Endpoint, end: Endpoint) {
        let late = (delayMinutes ?? 0) > 0

        switch phase {
        case .waiting(let arrived, let next):
            return (
                Endpoint(code: arrived.destination.shortCode, title: "Landed",
                         time: arrival(of: arrived), scheduled: scheduledArrival(of: arrived),
                         zone: arrived.destination.timeZone),
                Endpoint(code: next.destination.shortCode, title: "Departs",
                         time: departure(of: next), scheduled: scheduledDeparture(of: next),
                         zone: next.origin.timeZone, isLate: late)
            )
        case .boarding(let segment), .inTransit(let segment), .arrived(let segment):
            let hasArrived: Bool = { if case .arrived = phase { return true } else { return false } }()
            return (
                Endpoint(code: segment.origin.shortCode,
                         title: hasArrived || isUnderway ? "Departed" : "Departs",
                         time: departure(of: segment), scheduled: scheduledDeparture(of: segment),
                         zone: segment.origin.timeZone),
                Endpoint(code: segment.destination.shortCode,
                         title: hasArrived ? "Arrived" : "Arrives",
                         time: arrival(of: segment), scheduled: scheduledArrival(of: segment),
                         zone: segment.destination.timeZone, isLate: late)
            )
        }
    }
}

#if DEBUG
#Preview("Connection") {
    ScrollView {
        TripStatusCardView(trip: .sampleConnection)
            .padding()
    }
    .modelContainer(PreviewData.container)
}
#endif
