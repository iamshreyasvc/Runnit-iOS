//
//  TripsListView.swift
//  Runnit iOS
//
//  A single filter (Upcoming or Past) as its own tab: an interactive, zoomable
//  map of that tab's trips on top, with the trip cards scrolling below.
//

import SwiftUI
import SwiftData
import MapKit

enum TripFilter: String, CaseIterable, Identifiable {
    case upcoming = "Upcoming"
    case past = "Past"
    var id: String { rawValue }

    var accent: Color { self == .upcoming ? .blue : .indigo }
    var emptySymbol: String { self == .upcoming ? "airplane.departure" : "clock.arrow.circlepath" }
}

struct TripsListView: View {
    let filter: TripFilter

    @Query(sort: \Trip.departureDate, order: .forward) private var allTrips: [Trip]
    @State private var showingAdd = false
    @State private var selectedTrip: Trip?
    @State private var mapSelection: PersistentIdentifier?

    private var shown: [Trip] {
        switch filter {
        case .upcoming: return allTrips.filter(\.isUpcoming).sorted { $0.departureDate < $1.departureDate }
        case .past:     return allTrips.filter(\.isPast).sorted { $0.departureDate > $1.departureDate }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground(accent: filter.accent, secondary: .teal)
                if shown.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: 0) {
                        mapHeader
                        tripList
                    }
                }
            }
            .navigationTitle(filter.rawValue)
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(item: $selectedTrip) { TripDetailView(trip: $0) }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAdd = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAdd) {
                AddTripFlowView()
            }
            .onAppear {
                #if DEBUG
                if ProcessInfo.processInfo.environment["SHOW_ADD"] == "1", filter == .upcoming {
                    showingAdd = true
                }
                #endif
            }
        }
    }

    // MARK: Map header (interactive + zoomable)

    private var mapHeader: some View {
        Map(selection: $mapSelection) {
            ForEach(shown) { trip in
                MapPolyline(coordinates: [trip.origin.coordinate, trip.destination.coordinate])
                    .stroke(trip.type.accent.opacity(0.85),
                            style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [1, 6]))
                Marker(trip.destination.displayName, systemImage: trip.type.symbol,
                       coordinate: trip.destination.coordinate)
                    .tint(trip.type.accent)
                    .tag(trip.persistentModelID)
            }
        }
        .mapStyle(.standard(elevation: .realistic))
        .frame(height: 320)
        .clipShape(.rect(cornerRadius: 24))
        .padding([.horizontal, .top])
        .onChange(of: mapSelection) { _, id in
            guard let id else { return }
            selectedTrip = shown.first { $0.persistentModelID == id }
            mapSelection = nil
        }
    }

    private var tripList: some View {
        ScrollView {
            GlassEffectContainer(spacing: 16) {
                LazyVStack(spacing: 16) {
                    ForEach(shown) { trip in
                        NavigationLink {
                            TripDetailView(trip: trip)
                        } label: {
                            TripCardView(trip: trip)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding()
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No \(filter.rawValue.lowercased()) trips", systemImage: filter.emptySymbol)
        } description: {
            Text(filter == .upcoming
                 ? "Add a flight, train, or road trip to see it here."
                 : "Completed trips will appear here.")
        } actions: {
            if filter == .upcoming {
                Button {
                    showingAdd = true
                } label: {
                    Label("Add Trip", systemImage: "plus")
                }
                .buttonStyle(.glassProminent)
            }
        }
    }
}

#if DEBUG
#Preview {
    TripsListView(filter: .upcoming)
        .modelContainer(PreviewData.container)
}
#endif
