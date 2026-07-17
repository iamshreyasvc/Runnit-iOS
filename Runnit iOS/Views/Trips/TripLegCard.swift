//
//  TripLegCard.swift
//  Runnit iOS
//
//  One leg of a trip in the itinerary, as a collapsible card. The header is
//  always visible (mode, route, times, live status); tapping expands the full
//  detail — the route rail from origin through any stops to the destination,
//  booking info, live flight status, and directions.
//

import SwiftUI
import SwiftData

/// The stop-editor sheet target: a new stop appended to this leg, or one of its
/// existing stops by index.
private enum StopSheet: Identifiable {
    case new
    case existing(Int)
    var id: String {
        switch self {
        case .new:              return "new"
        case .existing(let i):  return "existing-\(i)"
        }
    }
}

struct TripLegCard: View {
    let trip: Trip
    let index: Int
    let segment: TripSegment
    /// Cached live snapshots for this segment only (used for the gate override).
    let records: [FlightStatusRecord]
    @Binding var expanded: Set<UUID>

    @Environment(\.modelContext) private var context
    @State private var stopSheet: StopSheet?

    private var isExpanded: Bool { expanded.contains(segment.id) }
    private var accent: Color { segment.type.accent }
    /// Only a drive has stops along the way to add or reorder.
    private var editsStops: Bool { segment.type == .roadTrip }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if isExpanded {
                detail.padding(.top, 16)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(tint: accent.opacity(0.22))
        .sheet(item: $stopSheet, content: stopEditor)
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
            routeRail
            zoneShiftRow

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

    // MARK: Route rail
    //
    // The whole leg as one vertical line: origin at the top, each stop threaded
    // onto the line in travel order with its category icon, destination at the
    // bottom. A drive also carries a node for adding the next stop.

    private var routeRail: some View {
        VStack(spacing: 0) {
            railRow(hasTop: false, hasBottom: true) {
                originMarker
            } content: {
                endpointContent(label: "From", place: segment.origin,
                                time: segment.departureDate, zone: segment.origin.timeZone)
            }

            ForEach(Array(segment.stops.enumerated()), id: \.element.id) { index, stop in
                stopRow(index: index, stop: stop)
            }

            if editsStops { addStopRow }

            railRow(hasTop: true, hasBottom: false) {
                destinationMarker
            } content: {
                endpointContent(label: "To", place: segment.destination,
                                time: segment.arrivalDate, zone: segment.destination.timeZone)
            }
        }
        .animation(.snappy(duration: 0.28), value: segment.stops)
    }

    /// One node on the rail: the line above and below it, the marker sitting on
    /// the line, and the row's text. Rows stack with no spacing, so consecutive
    /// line halves meet and read as a single unbroken rail.
    private func railRow<Marker: View, Content: View>(
        hasTop: Bool, hasBottom: Bool,
        @ViewBuilder marker: () -> Marker,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 12) {
            VStack(spacing: 0) {
                railLine(visible: hasTop)
                marker()
                railLine(visible: hasBottom)
            }
            .frame(width: 30)
            content()
            Spacer(minLength: 0)
        }
    }

    /// Half of the connector between two nodes. It stays in the layout when
    /// hidden so the first and last markers line up with the ones between them.
    private func railLine(visible: Bool) -> some View {
        Rectangle()
            .fill(visible ? AnyShapeStyle(accent.opacity(0.35)) : AnyShapeStyle(.clear))
            .frame(width: 2)
            .frame(minHeight: 9)
    }

    /// A ring rather than a filled icon, so the start of the leg reads as an open
    /// point — but the same 28pt as every other node, so the rail stays even.
    private var originMarker: some View {
        Circle()
            .strokeBorder(accent, lineWidth: 4)
            .frame(width: 28, height: 28)
    }

    private var destinationMarker: some View {
        Image(systemName: "mappin")
            .font(.caption.weight(.black))
            .foregroundStyle(.white)
            .frame(width: 28, height: 28)
            .background(accent.gradient, in: .circle)
    }

    private func endpointContent(label: String, place: Place,
                                 time: Date?, zone: TimeZone?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.caption).foregroundStyle(.secondary)
                Text(place.name).font(.body.weight(.semibold))
                if !place.subtitle.isEmpty {
                    Text(place.subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            if let time {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(Format.dateTime(time, in: zone)).font(.caption).foregroundStyle(.secondary)
                    if let label = Format.zone(zone, at: time) {
                        Text(label).font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: Stops

    private func stopRow(index: Int, stop: RoadStop) -> some View {
        railRow(hasTop: true, hasBottom: true) {
            Image(systemName: stop.category.symbol)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(stop.category.tint.gradient, in: .circle)
        } content: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(stop.place.displayName).font(.subheadline.weight(.semibold))
                    Text(stop.note ?? stop.category.label)
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if editsStops {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 4)
            .contentShape(.rect)
            .onTapGesture { if editsStops { stopSheet = .existing(index) } }
            .contextMenu { if editsStops { stopMenu(index: index) } }
        }
    }

    /// Reordering by menu rather than drag: the card's rail lives inside the
    /// detail page's scroll view, where a long-press drag would fight the scroll.
    @ViewBuilder
    private func stopMenu(index: Int) -> some View {
        Button { stopSheet = .existing(index) } label: {
            Label("Edit stop", systemImage: "pencil")
        }
        if index > 0 {
            Button { moveStop(at: index, by: -1) } label: {
                Label("Move up", systemImage: "arrow.up")
            }
        }
        if index < segment.stops.count - 1 {
            Button { moveStop(at: index, by: 1) } label: {
                Label("Move down", systemImage: "arrow.down")
            }
        }
        Button(role: .destructive) { removeStop(at: index) } label: {
            Label("Remove stop", systemImage: "trash")
        }
    }

    /// The "add" node, sitting on the rail right where the new stop will land —
    /// after the last stop, before the destination.
    private var addStopRow: some View {
        railRow(hasTop: true, hasBottom: true) {
            Image(systemName: "plus")
                .font(.caption.weight(.black))
                .foregroundStyle(accent)
                .frame(width: 28, height: 28)
                .background(accent.opacity(0.12), in: .circle)
                .overlay {
                    Circle().strokeBorder(accent.opacity(0.5),
                                          style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                }
        } content: {
            Text(segment.hasStops ? "Add another stop" : "Add a stop")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(accent)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
                .onTapGesture { stopSheet = .new }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    // MARK: Stop edits
    //
    // The segment is a stored model, so these write straight through — no editor
    // round-trip. Stops carry no summary fields, so the trip needs no refresh.

    @ViewBuilder
    private func stopEditor(_ sheet: StopSheet) -> some View {
        switch sheet {
        case .new:
            StopEditorView(titleText: "Add Stop") { stop in
                segment.stops.append(stop)
                save()
            }
        case .existing(let index):
            let current = segment.stops.indices.contains(index) ? segment.stops[index] : nil
            StopEditorView(titleText: "Edit Stop", stop: current) { updated in
                guard segment.stops.indices.contains(index) else { return }
                segment.stops[index] = updated
                save()
            }
        }
    }

    private func moveStop(at index: Int, by offset: Int) {
        let target = index + offset
        guard segment.stops.indices.contains(index),
              segment.stops.indices.contains(target) else { return }
        segment.stops.swapAt(index, target)
        save()
    }

    private func removeStop(at index: Int) {
        guard segment.stops.indices.contains(index) else { return }
        segment.stops.remove(at: index)
        save()
    }

    private func save() { try? context.save() }

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
