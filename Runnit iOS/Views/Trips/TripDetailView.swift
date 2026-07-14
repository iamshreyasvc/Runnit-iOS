//
//  TripDetailView.swift
//  Runnit iOS
//
//  Full trip detail: a multi-leg route map, an overall summary, a per-leg
//  itinerary (with mode-specific details and per-drive Apple Maps directions),
//  and notes.
//

import SwiftUI
import SwiftData
import MapKit

struct TripDetailView: View {
    @Bindable var trip: Trip

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(FlightTracker.self) private var tracker

    @Query private var statusRecords: [FlightStatusRecord]

    @State private var showingEdit = false
    @State private var showingDeleteConfirm = false
    @State private var expandedLegs: Set<UUID> = []

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // While the trip is underway, "what's happening now" comes first —
                // ahead of the map, ahead of the itinerary.
                if isUnderway {
                    TripStatusCardView(trip: trip)
                }

                RouteMapView(trip: trip)
                    .frame(height: 220)
                    .clipShape(.rect(cornerRadius: 24))

                summaryCard

                // A connection in trouble outranks everything else on this screen —
                // unless the live card is already up top saying exactly that.
                if !isUnderway, let urgent = connections.first(where: { $0.risk.isUrgent }) {
                    connectionAlert(urgent)
                }

                // Single-leg flights show the full live status card up front.
                if !trip.isMultiModal, let seg = trip.displaySegments.first, seg.type == .flight {
                    FlightStatusCardView(segment: seg)
                }

                itinerary

                if let notes = trip.notes, !notes.isEmpty {
                    infoCard(title: "Notes") {
                        Text(notes).font(.body)
                    }
                }
            }
            .padding()
        }
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button { showingEdit = true } label: { Label("Edit", systemImage: "pencil") }
                    Button(role: .destructive) { showingDeleteConfirm = true } label: {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showingEdit) {
            AddEditTripView(trip: trip)
        }
        .confirmationDialog("Delete this trip?", isPresented: $showingDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                context.delete(trip)
                try? context.save()
                dismiss()
            }
        }
        .refreshable {
            // Pull-to-refresh spends at most one call: the most relevant flight leg.
            if let seg = primaryFlightSegment {
                await tracker.refresh(seg, in: context)
            }
        }
        .onAppear {
            // Auto-expand the leg most worth looking at (next/active flight)…
            if let seg = primaryFlightSegment { expandedLegs.insert(seg.id) }
            // …and the flight you're at risk of missing, whose gate you need now.
            for connection in connections where connection.risk.isUrgent {
                expandedLegs.insert(connection.outbound.id)
            }
        }
        .task { await backfillTimeZones() }
    }

    /// Fill in any airport that was saved without a timezone (older trips, or a
    /// MapKit result that carried no zone). Without this, that airport's times
    /// fall back to the device clock — so an arrival in Atlanta reads in Pacific
    /// time. Resolving it once lets every time show on its own airport's clock,
    /// the way airlines display them. Idempotent: skips places already resolved.
    private func backfillTimeZones() async {
        var changed = false
        for segment in trip.segments {
            if segment.origin.timeZoneIdentifier == nil {
                segment.origin = await segment.origin.reverseGeocoded()
                changed = changed || segment.origin.timeZoneIdentifier != nil
            }
            if segment.destination.timeZoneIdentifier == nil {
                segment.destination = await segment.destination.reverseGeocoded()
                changed = changed || segment.destination.timeZoneIdentifier != nil
            }
        }
        if changed { try? context.save() }
    }

    /// Whether the live status card is on screen — it takes over as the trip's
    /// headline the moment the trip starts happening.
    private var isUnderway: Bool {
        TripStatus(trip: trip, records: statusRecords) != nil
    }

    /// The flight leg a traveler most likely cares about right now: the next
    /// flight not yet finished, else the last flight in the trip.
    private var primaryFlightSegment: TripSegment? {
        let flights = trip.displaySegments.filter { $0.type == .flight }
        return flights.first { $0.endDate >= Date() } ?? flights.last
    }

    /// A pure-flight connecting itinerary is a "Connection"; anything else with
    /// several legs is just a "Trip".
    private var navigationTitle: String {
        guard trip.isMultiModal else { return trip.type.label }
        let allFlights = trip.displaySegments.allSatisfy { $0.type == .flight }
        return trip.isConnecting && allFlights ? "Connection" : "Trip"
    }

    // MARK: Connections

    /// Every connection in this trip, resolved against the cached live snapshots.
    /// Read-only: nothing here ever triggers a fetch.
    private var connections: [Connection] {
        trip.connectionPairs.map {
            Connection(inbound: $0.inbound, outbound: $0.outbound, records: statusRecords)
        }
    }

    /// The compact banner for a connection in trouble. The full detail still sits
    /// in the itinerary between the two legs — this just hoists the verdict.
    private func connectionAlert(_ connection: Connection) -> some View {
        let risk = connection.risk
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: risk.systemImage)
                .font(.headline)
                .foregroundStyle(risk.color)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(risk.label) at \(connection.airport.displayName)")
                    .font(.subheadline.weight(.semibold))
                Text(connection.advisory)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(tint: risk.color.opacity(0.3))
    }

    // MARK: Summary

    private var summaryCard: some View {
        infoCard(title: trip.displayTitle) {
            VStack(spacing: 12) {
                HStack {
                    Label("\(trip.legCount) \(trip.legCount == 1 ? "leg" : "legs")",
                          systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                        .font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    Text(Format.distance(trip.distanceMeters)).font(.callout.weight(.medium))
                }
                Divider()
                HStack {
                    Label(Format.dateTime(trip.startDate, in: trip.startPlace.timeZone),
                          systemImage: "calendar")
                        .font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    Text(trip.isPast ? "Completed" : Format.relative(trip.startDate))
                        .font(.callout.weight(.medium))
                        .foregroundStyle(trip.isPast ? .secondary : trip.type.accent)
                }
            }
        }
    }

    // MARK: Itinerary

    private var itinerary: some View {
        VStack(spacing: 16) {
            ForEach(Array(trip.displaySegments.enumerated()), id: \.element.id) { idx, segment in
                legCard(index: idx, segment: segment)
                // When this leg feeds a connection, the gap to the next leg *is*
                // the connection — spell it out instead of an empty route line.
                if let pair = trip.connectionPairs.first(where: { $0.inbound.id == segment.id }) {
                    ConnectionCardView(inbound: pair.inbound, outbound: pair.outbound)
                }
            }
        }
    }

    private func legCard(index: Int, segment: TripSegment) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: segment.type.symbol)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(segment.type.gradient, in: .circle)
                VStack(alignment: .leading, spacing: 1) {
                    if trip.isMultiModal {
                        Text("Leg \(index + 1)").font(.caption2).foregroundStyle(.secondary)
                    }
                    Text(segment.type.label).font(.headline)
                }
                Spacer()
            }

            routeEndpoint(icon: "circle.circle", label: "From", place: segment.origin,
                          time: segment.departureDate, tint: segment.type.accent,
                          zone: segment.origin.timeZone)
            zoneShiftRow(segment)
            Divider()
            routeEndpoint(icon: "mappin.circle.fill", label: "To", place: segment.destination,
                          time: segment.arrivalDate, tint: segment.type.accent,
                          zone: segment.destination.timeZone)

            if segment.type.isScheduledTransit, hasTransitDetails(segment) {
                Divider()
                transitDetails(segment)
            }

            // Multi-leg flights keep live status behind a disclosure so the
            // itinerary stays scannable; single-leg flights show it up top.
            if trip.isMultiModal, segment.type == .flight {
                Divider()
                flightDisclosure(segment)
            }

            HStack {
                Label("Distance", systemImage: "ruler")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(Format.distance(segment.distanceMeters)).font(.caption.weight(.medium))
            }

            if segment.type == .roadTrip {
                directionsButton(segment)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(tint: segment.type.accent.opacity(0.22))
    }

    private func flightDisclosure(_ segment: TripSegment) -> some View {
        DisclosureGroup(isExpanded: expansionBinding(for: segment.id)) {
            FlightStatusCardView(segment: segment, embedded: true)
                .padding(.top, 8)
        } label: {
            HStack(spacing: 8) {
                Text("Flight status").font(.subheadline.weight(.semibold))
                Spacer()
                FlightStatusChip(segment: segment)
            }
        }
        .tint(segment.type.accent)
    }

    private func expansionBinding(for id: UUID) -> Binding<Bool> {
        Binding(
            get: { expandedLegs.contains(id) },
            set: { isOn in
                if isOn { expandedLegs.insert(id) } else { expandedLegs.remove(id) }
            }
        )
    }

    private func directionsButton(_ segment: TripSegment) -> some View {
        Button {
            MapsLauncher.openDirections(from: segment.origin, to: segment.destination)
        } label: {
            Label("Open in Apple Maps", systemImage: "location.north.line.fill")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
        }
        .buttonStyle(.glassProminent)
        .tint(segment.type.accent)
    }

    private func hasTransitDetails(_ s: TripSegment) -> Bool {
        [s.operatorName, s.vehicleNumber, s.boardingPoint, s.seat, s.confirmation]
            .contains { ($0 ?? "").isEmpty == false }
    }

    private func transitDetails(_ s: TripSegment) -> some View {
        VStack(spacing: 8) {
            detailRow("Operator", s.operatorName)
            detailRow(s.type.numberLabel, s.vehicleNumber)
            boardingRow(s)
            detailRow("Seat", s.seat)
            detailRow("Confirmation", s.confirmation)
        }
    }

    /// Gate / terminal, preferring the airline's live answer over what was typed
    /// when the trip was created. Gates get reassigned constantly, and a stale
    /// hand-entered gate is worse than none — but we still show what you entered,
    /// struck through, so a surprising change is visible rather than silent.
    @ViewBuilder
    private func boardingRow(_ s: TripSegment) -> some View {
        let record = statusRecords.first { $0.segmentID == s.id && $0.isDisplayable(for: s) }
        if let live = liveBoarding(record) {
            HStack(alignment: .firstTextBaseline) {
                Text(s.type.boardingLabel).font(.callout).foregroundStyle(.secondary)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(live).font(.callout.weight(.medium))
                        Text("LIVE")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(s.type.accent)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(s.type.accent.opacity(0.18), in: .capsule)
                    }
                    if let entered = s.boardingPoint, !entered.isEmpty, !live.contains(entered) {
                        Text(entered)
                            .font(.caption2).foregroundStyle(.secondary).strikethrough()
                    }
                }
            }
        } else {
            detailRow(s.type.boardingLabel, s.boardingPoint)
        }
    }

    /// "Terminal 3 · Gate 34" from the live snapshot, when it knows either.
    private func liveBoarding(_ record: FlightStatusRecord?) -> String? {
        guard let record else { return nil }
        var parts: [String] = []
        if let terminal = record.depTerminal { parts.append("Terminal \(terminal)") }
        if let gate = record.depGate { parts.append("Gate \(gate)") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: Building blocks

    private func routeEndpoint(icon: String, label: String, place: Place, time: Date?,
                               tint: Color, zone: TimeZone? = nil) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .frame(width: 22)
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
                    Text(Format.dateTime(time, in: zone))
                        .font(.caption).foregroundStyle(.secondary)
                    if let label = Format.zone(zone, at: time) {
                        Text(label).font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    /// The clock change across a leg, spelled out between its endpoints.
    @ViewBuilder
    private func zoneShiftRow(_ segment: TripSegment) -> some View {
        if let shift = Format.zoneShift(
            from: segment.origin.timeZone, to: segment.destination.timeZone,
            departing: segment.departureDate,
            arriving: segment.arrivalDate ?? segment.departureDate
        ) {
            Label(shift, systemImage: "clock.arrow.2.circlepath")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
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

    private func infoCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }
}

/// Small non-interactive map showing every leg of the trip.
struct RouteMapView: View {
    let trip: Trip

    private var segments: [TripSegment] { trip.displaySegments }

    var body: some View {
        Map(initialPosition: .region(region)) {
            // First origin marker.
            if let first = segments.first {
                Marker(first.origin.displayName, systemImage: "circle.circle",
                       coordinate: first.origin.coordinate)
                    .tint(.gray)
            }
            ForEach(segments) { segment in
                MapPolyline(coordinates: [segment.origin.coordinate, segment.destination.coordinate])
                    .stroke(segment.type.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [2, 6]))
                Marker(segment.destination.displayName, systemImage: segment.type.symbol,
                       coordinate: segment.destination.coordinate)
                    .tint(segment.type.accent)
            }
        }
        .mapStyle(.standard(elevation: .realistic))
        .disabled(true)
    }

    private var coords: [CLLocationCoordinate2D] {
        segments.flatMap { [$0.origin.coordinate, $0.destination.coordinate] }
    }

    private var region: MKCoordinateRegion {
        let all = coords.isEmpty ? [CLLocationCoordinate2D(latitude: 0, longitude: 0)] : coords
        let lats = all.map(\.latitude)
        let lons = all.map(\.longitude)
        let center = CLLocationCoordinate2D(
            latitude: (lats.min()! + lats.max()!) / 2,
            longitude: (lons.min()! + lons.max()!) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max((lats.max()! - lats.min()!) * 1.6, 0.5),
            longitudeDelta: max((lons.max()! - lons.min()!) * 1.6, 0.5)
        )
        return MKCoordinateRegion(center: center, span: span)
    }
}

#if DEBUG
private extension View {
    /// Injects the flight-tracking environment objects previews need.
    func flightTrackingPreviewEnv() -> some View {
        environment(FlightTracker())
    }
}

#Preview("Single") {
    NavigationStack {
        TripDetailView(trip: .sampleFlight)
    }
    .modelContainer(PreviewData.container)
    .flightTrackingPreviewEnv()
}

#Preview("Multi-modal") {
    NavigationStack {
        TripDetailView(trip: .sampleMultiModal)
    }
    .modelContainer(PreviewData.container)
    .flightTrackingPreviewEnv()
}

#Preview("Connection") {
    NavigationStack {
        TripDetailView(trip: .sampleConnection)
    }
    .modelContainer(PreviewData.container)
    .flightTrackingPreviewEnv()
}
#endif
