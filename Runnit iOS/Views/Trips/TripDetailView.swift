//
//  TripDetailView.swift
//  Runnit iOS
//
//  Full trip detail: route map, live-status seam, mode-specific details, and
//  (for road trips) a one-tap Apple Maps directions button.
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

                if trip.type == .roadTrip {
                    directionsButton
                }

                if trip.type.isScheduledTransit {
                    statusCard
                    transitDetailsCard
                }

                routeCard

                if let notes = trip.notes, !notes.isEmpty {
                    infoCard(title: "Notes") {
                        Text(notes).font(.body)
                    }
                }
            }
            .padding()
        }
        .navigationTitle(trip.type.label)
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

    // MARK: Sections

    private var directionsButton: some View {
        VStack(spacing: 8) {
            Button {
                MapsLauncher.openDirections(from: trip.origin, to: trip.destination)
            } label: {
                Label("Open in Apple Maps", systemImage: "location.north.line.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.glassProminent)
            .tint(trip.type.accent)

            if let arrival = trip.arrivalDate {
                Label(
                    "\(Format.duration(arrival.timeIntervalSince(trip.departureDate))) drive · arrive \(Format.dateTime(arrival))",
                    systemImage: "car.fill"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
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
                    Text(Format.dateTime(trip.departureDate))
                        .font(.callout.weight(.medium))
                }
            }
        }
    }

    private var transitDetailsCard: some View {
        infoCard(title: "\(trip.type.label) details") {
            VStack(spacing: 10) {
                detailRow("Operator", trip.operatorName)
                detailRow(trip.type.numberLabel, trip.vehicleNumber)
                detailRow(trip.type.boardingLabel, trip.boardingPoint)
                detailRow("Seat", trip.seat)
                detailRow("Confirmation", trip.confirmation)
            }
        }
    }

    private var routeCard: some View {
        infoCard(title: "Route") {
            VStack(spacing: 10) {
                routeEndpoint(icon: "circle.circle", label: "From", place: trip.origin,
                              time: trip.departureDate)
                Divider()
                routeEndpoint(icon: "mappin.circle.fill", label: "To", place: trip.destination,
                              time: trip.arrivalDate)
                Divider()
                HStack {
                    Label("Distance", systemImage: "ruler")
                        .font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    Text(Format.distance(trip.distanceMeters)).font(.callout.weight(.medium))
                }
            }
        }
    }

    // MARK: Building blocks

    private func routeEndpoint(icon: String, label: String, place: Place, time: Date?) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(trip.type.accent)
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

/// Small non-interactive map showing the origin → destination route.
struct RouteMapView: View {
    let trip: Trip

    var body: some View {
        Map(initialPosition: .region(region)) {
            Marker(trip.origin.displayName, systemImage: "circle.circle", coordinate: trip.origin.coordinate)
                .tint(.gray)
            Marker(trip.destination.displayName, systemImage: trip.type.symbol, coordinate: trip.destination.coordinate)
                .tint(trip.type.accent)
            MapPolyline(coordinates: [trip.origin.coordinate, trip.destination.coordinate])
                .stroke(trip.type.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [2, 6]))
        }
        .mapStyle(.standard(elevation: .realistic))
        .disabled(true)
    }

    private var region: MKCoordinateRegion {
        let coords = [trip.origin.coordinate, trip.destination.coordinate]
        let lats = coords.map(\.latitude)
        let lons = coords.map(\.longitude)
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
#Preview {
    NavigationStack {
        TripDetailView(trip: .sampleFlight)
    }
    .modelContainer(PreviewData.container)
}
#endif
