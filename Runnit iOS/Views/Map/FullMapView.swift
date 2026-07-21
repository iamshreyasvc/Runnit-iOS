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

    @Query private var statusRecords: [FlightStatusRecord]

    var body: some View {
        NavigationStack {
            Map(selection: $mapSelection) {
                ForEach(trips) { trip in
                    ForEach(trip.displaySegments) { segment in
                        // Real routes when cached, straight lines otherwise —
                        // and the live aircraft while a flight leg is airborne.
                        SegmentRouteContent(segment: segment,
                                            live: statusRecords.liveRecord(for: segment))
                    }
                    Annotation(trip.endPlace.displayName, coordinate: trip.endPlace.coordinate) {
                        Image(systemName: trip.type.symbol)
                            .font(.system(size: 13, weight: .black))
                            .foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                            .background(trip.type.gradient, in: .circle)
                            .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                            .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                    }
                    .tag(trip.persistentModelID)
                    .annotationTitles(.hidden)
                }
            }
            .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll))
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
