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

    @State private var status: FlightStatus?
    @State private var showingEdit = false
    @State private var showingDeleteConfirm = false

    private let statusProvider: FlightStatusProvider = ManualFlightStatusProvider()

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                RouteMapView(trip: trip)
                    .frame(height: 220)
                    .clipShape(.rect(cornerRadius: 24))

                summaryCard

                if !trip.isMultiModal, trip.type.isScheduledTransit {
                    statusCard
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
        .navigationTitle(trip.isMultiModal ? "Trip" : trip.type.label)
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
        .task(id: trip.id) {
            status = try? await statusProvider.status(for: trip)
        }
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
                    Label(Format.dateTime(trip.startDate), systemImage: "calendar")
                        .font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    Text(trip.isPast ? "Completed" : Format.relative(trip.startDate))
                        .font(.callout.weight(.medium))
                        .foregroundStyle(trip.isPast ? .secondary : trip.type.accent)
                }
            }
        }
    }

    private var statusCard: some View {
        infoCard(title: "Status") {
            HStack {
                Text(status?.state.rawValue ?? "—")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(trip.type.accent)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Departs")
                        .font(.caption).foregroundStyle(.secondary)
                    Text(Format.dateTime(trip.startDate))
                        .font(.callout.weight(.medium))
                }
            }
        }
    }

    // MARK: Itinerary

    private var itinerary: some View {
        VStack(spacing: 16) {
            ForEach(Array(trip.displaySegments.enumerated()), id: \.element.id) { idx, segment in
                legCard(index: idx, segment: segment)
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
                          time: segment.departureDate, tint: segment.type.accent)
            Divider()
            routeEndpoint(icon: "mappin.circle.fill", label: "To", place: segment.destination,
                          time: segment.arrivalDate, tint: segment.type.accent)

            if segment.type.isScheduledTransit, hasTransitDetails(segment) {
                Divider()
                transitDetails(segment)
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
            detailRow(s.type.boardingLabel, s.boardingPoint)
            detailRow("Seat", s.seat)
            detailRow("Confirmation", s.confirmation)
        }
    }

    // MARK: Building blocks

    private func routeEndpoint(icon: String, label: String, place: Place, time: Date?, tint: Color) -> some View {
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
                Text(Format.dateTime(time)).font(.caption).foregroundStyle(.secondary)
            }
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
#Preview("Single") {
    NavigationStack {
        TripDetailView(trip: .sampleFlight)
    }
    .modelContainer(PreviewData.container)
}

#Preview("Multi-modal") {
    NavigationStack {
        TripDetailView(trip: .sampleMultiModal)
    }
    .modelContainer(PreviewData.container)
}
#endif
