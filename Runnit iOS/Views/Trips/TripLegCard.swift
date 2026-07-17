//
//  TripLegCard.swift
//  Runnit iOS
//
//  One leg of a trip in the itinerary, as a collapsible card. The header is
//  always visible (mode, route, times, live status); tapping expands the full
//  detail — endpoints, booking info, live flight status, and directions.
//

import SwiftUI
import SwiftData

struct TripLegCard: View {
    let trip: Trip
    let index: Int
    let segment: TripSegment
    /// Cached live snapshots for this segment only (used for the gate override).
    let records: [FlightStatusRecord]
    @Binding var expanded: Set<UUID>

    private var isExpanded: Bool { expanded.contains(segment.id) }
    private var accent: Color { segment.type.accent }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if isExpanded {
                detail.padding(.top, 16)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(tint: accent.opacity(0.22))
    }

    // MARK: Header (always visible, tappable)

    private var header: some View {
        Button {
            withAnimation(.snappy(duration: 0.3)) {
                if isExpanded { expanded.remove(segment.id) } else { expanded.insert(segment.id) }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: segment.type.symbol)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(segment.type.gradient, in: .circle)
                VStack(alignment: .leading, spacing: 2) {
                    if trip.isMultiModal {
                        Text("Leg \(index + 1)").font(.caption2).foregroundStyle(.secondary)
                    }
                    Text(headerTitle).font(.headline)
                    if let subtitle = headerSubtitle {
                        Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if segment.type == .flight { FlightStatusChip(segment: segment) }
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
            }
        }
        .buttonStyle(.plain)
    }

    private var headerTitle: String {
        trip.isMultiModal
            ? "\(segment.origin.codeLabel) → \(segment.destination.codeLabel)"
            : "\(segment.type.label) details"
    }

    private var headerSubtitle: String? {
        let stopsNote = segment.hasStops
            ? "\(segment.stops.count) stop\(segment.stops.count == 1 ? "" : "s")" : nil
        guard trip.isMultiModal else { return stopsNote }
        let dep = Format.time(segment.departureDate, in: segment.origin.timeZone)
        let times = segment.arrivalDate
            .map { "\(dep) → \(Format.time($0, in: segment.destination.timeZone))" } ?? dep
        return [times, stopsNote].compactMap { $0 }.joined(separator: " · ")
    }

    // MARK: Detail (expanded)

    private var detail: some View {
        VStack(alignment: .leading, spacing: 12) {
            routeEndpoint(icon: "circle.circle", label: "From", place: segment.origin,
                          time: segment.departureDate, zone: segment.origin.timeZone)
            zoneShiftRow

            if segment.hasStops {
                Divider()
                stopsList
            }

            Divider()
            routeEndpoint(icon: "mappin.circle.fill", label: "To", place: segment.destination,
                          time: segment.arrivalDate, zone: segment.destination.timeZone)

            if segment.type.isScheduledTransit, hasTransitDetails {
                Divider()
                transitDetails
            }

            if segment.type == .flight {
                Divider()
                FlightStatusCardView(segment: segment, embedded: true)
            }

            Divider()
            HStack {
                Label("Distance", systemImage: "ruler").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(Format.distance(segment.distanceMeters)).font(.caption.weight(.medium))
            }

            if segment.type == .roadTrip { directionsButton }
        }
    }

    // MARK: Stops

    private var stopsList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("\(segment.stops.count) stop\(segment.stops.count == 1 ? "" : "s") along the way",
                  systemImage: "mappin.and.ellipse")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(Array(segment.stops.enumerated()), id: \.element.id) { index, stop in
                stopRow(index: index, stop: stop)
            }
        }
    }

    private func stopRow(index: Int, stop: RoadStop) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // A little connecting rail so the stops read as points along the drive.
            VStack(spacing: 0) {
                Image(systemName: stop.category.symbol)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(stop.category.tint.gradient, in: .circle)
                if index < segment.stops.count - 1 {
                    Rectangle().fill(.secondary.opacity(0.25))
                        .frame(width: 2, height: 14)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(stop.place.displayName).font(.subheadline.weight(.semibold))
                Text(stop.note ?? stop.category.label)
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private func routeEndpoint(icon: String, label: String, place: Place,
                               time: Date?, zone: TimeZone?) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).foregroundStyle(accent).frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.caption).foregroundStyle(.secondary)
                Text(place.name).font(.body.weight(.semibold))
                if !place.subtitle.isEmpty {
                    Text(place.subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let time {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(Format.dateTime(time, in: zone)).font(.caption).foregroundStyle(.secondary)
                    if let label = Format.zone(zone, at: time) {
                        Text(label).font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var zoneShiftRow: some View {
        if let shift = Format.zoneShift(
            from: segment.origin.timeZone, to: segment.destination.timeZone,
            departing: segment.departureDate,
            arriving: segment.arrivalDate ?? segment.departureDate
        ) {
            Label(shift, systemImage: "clock.arrow.2.circlepath")
                .font(.caption2).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Booking details

    private var hasTransitDetails: Bool {
        [segment.operatorName, segment.vehicleNumber, segment.boardingPoint,
         segment.seat, segment.confirmation].contains { ($0 ?? "").isEmpty == false }
    }

    private var transitDetails: some View {
        VStack(spacing: 8) {
            detailRow("Operator", segment.operatorName)
            detailRow(segment.type.numberLabel, segment.vehicleNumber)
            boardingRow
            detailRow("Seat", segment.seat)
            detailRow("Confirmation", segment.confirmation)
        }
    }

    /// Gate / terminal, preferring the airline's live answer over what was typed.
    @ViewBuilder
    private var boardingRow: some View {
        let record = records.first { $0.segmentID == segment.id && $0.isDisplayable(for: segment) }
        if let live = liveBoarding(record) {
            HStack(alignment: .firstTextBaseline) {
                Text(segment.type.boardingLabel).font(.callout).foregroundStyle(.secondary)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(live).font(.callout.weight(.medium))
                        Text("LIVE")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(accent)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(accent.opacity(0.18), in: .capsule)
                    }
                    if let entered = segment.boardingPoint, !entered.isEmpty, !live.contains(entered) {
                        Text(entered).font(.caption2).foregroundStyle(.secondary).strikethrough()
                    }
                }
            }
        } else {
            detailRow(segment.type.boardingLabel, segment.boardingPoint)
        }
    }

    private func liveBoarding(_ record: FlightStatusRecord?) -> String? {
        guard let record else { return nil }
        var parts: [String] = []
        if let terminal = record.depTerminal { parts.append("Terminal \(terminal)") }
        if let gate = record.depGate { parts.append("Gate \(gate)") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func detailRow(_ label: String, _ value: String?) -> some View {
        if let value, !value.isEmpty {
            HStack {
                Text(label).font(.callout).foregroundStyle(.secondary)
                Spacer()
                Text(value).font(.callout.weight(.medium))
            }
        }
    }

    private var directionsButton: some View {
        Button {
            MapsLauncher.openDirections(from: segment.origin, to: segment.destination,
                                        via: segment.stops.map(\.place))
        } label: {
            Label(segment.hasStops ? "Route with stops in Apple Maps" : "Open in Apple Maps",
                  systemImage: "location.north.line.fill")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
        }
        .buttonStyle(.glassProminent)
        .tint(accent)
    }
}
