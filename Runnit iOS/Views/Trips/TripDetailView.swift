//
//  TripDetailView.swift
//  Runnit iOS
//
//  Full trip detail, reorganized for scannability: live status (when underway)
//  and the route map up top, a consolidated overview card, then a collapsible
//  per-leg itinerary that keeps the details a tap away instead of all at once.
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
                // While the trip is underway, "what's happening now" comes first.
                if isUnderway {
                    TripStatusCardView(trip: trip)
                }

                RouteMapView(trip: trip)
                    .frame(height: 220)
                    .clipShape(.rect(cornerRadius: 24))

                TripOverviewCard(trip: trip)

                // A connection in trouble outranks everything — unless the live
                // card up top is already saying exactly that.
                if !isUnderway, let urgent = connections.first(where: { $0.risk.isUrgent }) {
                    connectionAlert(urgent)
                }

                itinerary

                if let notes = trip.notes, !notes.isEmpty {
                    notesCard(notes)
                }
            }
            .padding()
        }
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarMenu }
        .sheet(isPresented: $showingEdit) { AddEditTripView(trip: trip) }
        .confirmationDialog("Delete this trip?", isPresented: $showingDeleteConfirm,
                            titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                context.delete(trip)
                try? context.save()
                dismiss()
            }
        }
        .refreshable {
            if let seg = primaryFlightSegment { await tracker.refresh(seg, in: context) }
        }
        .onAppear(perform: expandKeyLegs)
        .task { await backfillTimeZones() }
    }

    private var toolbarMenu: some ToolbarContent {
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

    /// Auto-expand the legs most worth seeing on open: the next/active flight, any
    /// flight at risk of being missed, and — for a single-leg trip — its only leg.
    private func expandKeyLegs() {
        if let seg = primaryFlightSegment { expandedLegs.insert(seg.id) }
        for connection in connections where connection.risk.isUrgent {
            expandedLegs.insert(connection.outbound.id)
        }
        if trip.displaySegments.count == 1, let only = trip.displaySegments.first {
            expandedLegs.insert(only.id)
        }
    }

    /// Fill in any airport saved without a timezone so its times show on its own
    /// clock rather than the device's. Idempotent: skips places already resolved.
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

    // MARK: Itinerary

    private var itinerary: some View {
        VStack(spacing: 16) {
            if trip.isMultiModal {
                SectionTitle(title: "Itinerary", systemImage: "list.bullet",
                             tint: trip.type.accent)
            }
            ForEach(Array(trip.displaySegments.enumerated()), id: \.element.id) { idx, segment in
                TripLegCard(trip: trip, index: idx, segment: segment,
                            records: statusRecords.filter { $0.segmentID == segment.id },
                            expanded: $expandedLegs)
                if let pair = trip.connectionPairs.first(where: { $0.inbound.id == segment.id }) {
                    ConnectionCardView(inbound: pair.inbound, outbound: pair.outbound)
                }
            }
        }
    }

    private func notesCard(_ notes: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle(title: "Notes", systemImage: "note.text", tint: trip.type.accent)
            Text(notes).font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassCard()
        }
    }

    // MARK: Derived state

    private var isUnderway: Bool {
        TripStatus(trip: trip, records: statusRecords) != nil
    }

    /// The flight leg a traveler most likely cares about now: the next unfinished
    /// flight, else the last flight in the trip.
    private var primaryFlightSegment: TripSegment? {
        let flights = trip.displaySegments.filter { $0.type == .flight }
        return flights.first { $0.endDate >= Date() } ?? flights.last
    }

    private var navigationTitle: String {
        guard trip.isMultiModal else { return trip.type.label }
        let allFlights = trip.displaySegments.allSatisfy { $0.type == .flight }
        return trip.isConnecting && allFlights ? "Connection" : "Trip"
    }

    private var connections: [Connection] {
        trip.connectionPairs.map {
            Connection(inbound: $0.inbound, outbound: $0.outbound, records: statusRecords)
        }
    }

    private func connectionAlert(_ connection: Connection) -> some View {
        let risk = connection.risk
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: risk.systemImage).font(.headline).foregroundStyle(risk.color)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(risk.label) at \(connection.airport.displayName)")
                    .font(.subheadline.weight(.semibold))
                Text(connection.advisory)
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(tint: risk.color.opacity(0.3))
    }
}

/// Small non-interactive map showing every leg of the trip.
struct RouteMapView: View {
    let trip: Trip

    private var segments: [TripSegment] { trip.displaySegments }

    var body: some View {
        Map(initialPosition: .region(region)) {
            if let first = segments.first {
                Marker(first.origin.displayName, systemImage: "circle.circle",
                       coordinate: first.origin.coordinate)
                    .tint(.gray)
            }
            ForEach(segments) { segment in
                // Route through any intermediate stops so a detour reads truthfully.
                MapPolyline(coordinates: segment.routePlaces.map(\.coordinate))
                    .stroke(segment.type.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [2, 6]))
                ForEach(segment.stops) { stop in
                    Marker(stop.place.displayName, systemImage: stop.category.symbol,
                           coordinate: stop.place.coordinate)
                        .tint(stop.category.tint)
                }
                Marker(segment.destination.displayName, systemImage: segment.type.symbol,
                       coordinate: segment.destination.coordinate)
                    .tint(segment.type.accent)
            }
        }
        .mapStyle(.standard(elevation: .realistic))
        .disabled(true)
    }

    private var coords: [CLLocationCoordinate2D] {
        segments.flatMap { $0.routePlaces.map(\.coordinate) }
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
    func flightTrackingPreviewEnv() -> some View {
        environment(FlightTracker())
    }
}

#Preview("Single") {
    NavigationStack { TripDetailView(trip: .sampleFlight) }
        .modelContainer(PreviewData.container)
        .flightTrackingPreviewEnv()
}

#Preview("Multi-modal") {
    NavigationStack { TripDetailView(trip: .sampleMultiModal) }
        .modelContainer(PreviewData.container)
        .flightTrackingPreviewEnv()
}

#Preview("Connection") {
    NavigationStack { TripDetailView(trip: .sampleConnection) }
        .modelContainer(PreviewData.container)
        .flightTrackingPreviewEnv()
}
#endif
