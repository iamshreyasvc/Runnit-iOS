//
//  TripCardView.swift
//  Runnit iOS
//
//  A boarding-pass style card summarizing one trip in the list: big origin /
//  destination codes with times, a dashed route connector, and a "stub" line
//  with the date, carrier, and distance. Kept scannable so a stack of them
//  reads cleanly.
//

import SwiftUI
import SwiftData

struct TripCardView: View {
    let trip: Trip

    /// Cached snapshots for this trip's flight legs only — enough to flag a
    /// connection in trouble. Cache-only: the list never fetches.
    @Query private var statusRecords: [FlightStatusRecord]
    @Environment(SyncEngine.self) private var sync

    init(trip: Trip) {
        self.trip = trip
        let ids = trip.displaySegments.filter { $0.type == .flight }.map(\.id)
        _statusRecords = Query(filter: #Predicate<FlightStatusRecord> {
            ids.contains($0.segmentID)
        })
    }

    var body: some View {
        VStack(spacing: 0) {
            topRow
            routeRow.padding(.top, 16)
            if let risk = urgentRisk { riskBanner(risk).padding(.top, 14) }
            perforation.padding(.vertical, 14)
            stubRow
        }
        .glassCard(tint: trip.type.accent.opacity(0.28))
    }

    // MARK: Top — mode + countdown

    private var topRow: some View {
        HStack(spacing: 8) {
            modeChain
            Text(modeLabel)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(trip.type.accent)
                .lineLimit(1)
            Spacer(minLength: 6)
            TripSyncBadge(state: trip.syncState.resolved(cloudAvailable: sync.isCloudAvailable))
            if trip.isShared {
                ParticipantStack(participants: trip.collaborators, size: 20)
            }
            countdownChip
        }
    }

    /// A single mode circle, or a chain of small mode icons for multi-modal trips.
    @ViewBuilder
    private var modeChain: some View {
        if trip.isMultiModal {
            HStack(spacing: -6) {
                ForEach(Array(trip.modeSequence.enumerated()), id: \.offset) { _, mode in
                    Image(systemName: mode.symbol)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(mode.gradient, in: .circle)
                        .overlay(Circle().strokeBorder(.background, lineWidth: 1.5))
                }
            }
        } else {
            Image(systemName: trip.type.symbol)
                .font(.footnote.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(trip.type.gradient, in: .circle)
        }
    }

    /// The mode, or leg count for a multi-modal trip. A trip someone shared with
    /// us is named for them — "Priya's Flight" — so a mixed list reads as whose
    /// trip is whose without needing a second badge to say so.
    private var modeLabel: String {
        let base = trip.isMultiModal ? "\(trip.legCount) legs" : trip.type.label
        guard !trip.isOwnedByMe, let owner = trip.ownerParticipant else { return base }
        return "\(owner.shortName)'s \(base)"
    }

    private var countdownChip: some View {
        Text(Format.relative(trip.startDate))
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .foregroundStyle(trip.isPast ? .secondary : trip.type.accent)
            .background(
                (trip.isPast ? Color.secondary : trip.type.accent).opacity(0.15),
                in: .capsule
            )
    }

    // MARK: Route — codes, times, connector

    private var routeRow: some View {
        HStack(alignment: .top, spacing: 10) {
            endpoint(code: code(for: trip.startPlace), time: departureTime, alignment: .leading)
            connector
            endpoint(code: code(for: trip.endPlace), time: arrivalTime, alignment: .trailing)
        }
    }

    private func endpoint(code: String, time: String?, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(code)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            if let time {
                Text(time)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .trailing)
    }

    private var connector: some View {
        VStack(spacing: 4) {
            HStack(spacing: 5) {
                DashedLine().stroke(.tertiary, style: dashStyle).frame(height: 1)
                Image(systemName: trip.type.symbol)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(trip.type.accent)
                DashedLine().stroke(.tertiary, style: dashStyle).frame(height: 1)
            }
            .frame(height: 16)
            if let stops = stopsLine {
                Text(stops)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    private var dashStyle: StrokeStyle { StrokeStyle(lineWidth: 1.5, dash: [2, 3]) }

    // MARK: Stub — date · carrier · distance

    private var perforation: some View {
        DashedLine()
            .stroke(.secondary.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            .frame(height: 1)
    }

    private var stubRow: some View {
        HStack(spacing: 6) {
            ForEach(Array(stubParts.enumerated()), id: \.offset) { index, part in
                if index > 0 {
                    Text("·").foregroundStyle(.tertiary)
                }
                Text(part)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var stubParts: [String] {
        var parts = [Format.date(trip.startDate, in: trip.startPlace.timeZone)]
        if let carrier = carrierLabel { parts.append(carrier) }
        parts.append(Format.distance(trip.distanceMeters))
        return parts
    }

    // MARK: Derived values

    /// IATA code for a flight endpoint, else a short place label.
    private func code(for place: Place) -> String { place.codeLabel }

    private var departureTime: String? {
        Format.time(trip.startDate, in: trip.startPlace.timeZone)
    }

    private var arrivalTime: String? {
        guard let arrival = trip.displaySegments.last?.arrivalDate else { return nil }
        return Format.time(arrival, in: trip.endPlace.timeZone)
    }

    private var carrierLabel: String? {
        if trip.isMultiModal { return "\(trip.legCount) legs" }
        if let number = trip.vehicleNumber, !number.isEmpty { return number }
        if let name = trip.operatorName, !name.isEmpty { return name }
        return nil
    }

    /// "1 stop · ORD" for a connecting flight, or "2 stops" for road-trip stops.
    private var stopsLine: String? {
        let pairs = trip.connectionPairs
        if !pairs.isEmpty {
            let count = "\(pairs.count) stop\(pairs.count == 1 ? "" : "s")"
            let airports = pairs.map { $0.outbound.origin.codeLabel }
            return ([count] + airports).joined(separator: " · ")
        }
        let roadStops = trip.displaySegments.reduce(0) { $0 + $1.stops.count }
        return roadStops > 0 ? "\(roadStops) stop\(roadStops == 1 ? "" : "s")" : nil
    }

    /// The worst connection risk on this trip, when it's bad enough to shout about.
    private var urgentRisk: ConnectionRisk? {
        trip.connectionPairs
            .map { Connection(inbound: $0.inbound, outbound: $0.outbound, records: statusRecords).risk }
            .first { $0.isUrgent }
    }

    private func riskBanner(_ risk: ConnectionRisk) -> some View {
        HStack(spacing: 6) {
            Image(systemName: risk.systemImage)
            Text(risk.label)
            Spacer()
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(risk.color)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(risk.color.opacity(0.16), in: .rect(cornerRadius: 10))
    }
}

/// A horizontal line used for the dashed route connector and the ticket
/// perforation. Drawn as a shape so it can take any stroke dash pattern.
struct DashedLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}

#if DEBUG
#Preview {
    ScrollView {
        VStack(spacing: 16) {
            TripCardView(trip: .sampleFlight)
            TripCardView(trip: .sampleConnection)
            TripCardView(trip: .sampleMultiModal)
            TripCardView(trip: .sampleRoadTrip)
        }
        .padding()
    }
    .background(.blue.opacity(0.1))
    .modelContainer(PreviewData.container)
    .environment(PreviewData.sync)
}
#endif
