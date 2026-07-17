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
                        // Road trips draw the real roads when routed; otherwise a
                        // straight line through the leg's places.
                        let coords = segment.routedCoordinates ?? segment.routePlaces.map(\.coordinate)
                        // Casing under a solid, gradient-tinted line — a crisp,
                        // navigation-grade route rather than a faint dashed hop.
                        MapPolyline(coordinates: coords)
                            .stroke(.black.opacity(0.22),
                                    style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
                        MapPolyline(coordinates: coords)
                            .stroke(segment.type.gradient,
                                    style: StrokeStyle(lineWidth: 4.5, lineCap: .round, lineJoin: .round))
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
