//
//  FullMapView.swift
//  Runnit iOS
//
//  A full-screen, zoomable map of a set of trips, presented from the map
//  header's expand button on the Upcoming / Past tabs.
//

import SwiftUI
import SwiftData
import MapKit

struct FullMapView: View {
    let trips: [Trip]
    var title: String = "Map"

    @Environment(\.dismiss) private var dismiss
    @State private var mapSelection: PersistentIdentifier?
    @State private var selectedTrip: Trip?

    var body: some View {
        NavigationStack {
            Map(selection: $mapSelection) {
                ForEach(trips) { trip in
                    ForEach(trip.displaySegments) { segment in
                        MapPolyline(coordinates: [segment.origin.coordinate, segment.destination.coordinate])
                            .stroke(segment.type.accent.opacity(0.85),
                                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [1, 6]))
                    }
                    Marker(trip.endPlace.displayName, systemImage: trip.type.symbol,
                           coordinate: trip.endPlace.coordinate)
                        .tint(trip.type.accent)
                        .tag(trip.persistentModelID)
                }
            }
            .mapStyle(.standard(elevation: .realistic))
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(item: $selectedTrip) { TripDetailView(trip: $0) }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onChange(of: mapSelection) { _, id in
                guard let id else { return }
                selectedTrip = trips.first { $0.persistentModelID == id }
                mapSelection = nil
            }
        }
    }
}

#if DEBUG
#Preview {
    FullMapView(trips: Trip.allSamples)
        .modelContainer(PreviewData.container)
}
#endif
