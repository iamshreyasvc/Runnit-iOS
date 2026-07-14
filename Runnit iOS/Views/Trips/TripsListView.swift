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
    var symbol: String { self == .upcoming ? "airplane.departure" : "clock.arrow.circlepath" }
    var emptySymbol: String { symbol }
}

struct TripsListView: View {
    let filter: TripFilter

    @Query(sort: \Trip.departureDate, order: .forward) private var allTrips: [Trip]
    @Query private var statusRecords: [FlightStatusRecord]
    @State private var showingAdd = false
    @State private var showingFullMap = false
    @State private var selectedTrip: Trip?
    @State private var mapSelection: PersistentIdentifier?
    @Namespace private var pillNamespace
    @State private var selectedYear: Int? = {
        #if DEBUG
        if let raw = ProcessInfo.processInfo.environment["YEAR"], let y = Int(raw) { return y }
        #endif
        return nil
    }()

    /// Trips for this tab (before the year filter).
    private var shown: [Trip] {
        switch filter {
        case .upcoming: return allTrips.filter(\.isUpcoming).sorted { $0.startDate < $1.startDate }
        case .past:     return allTrips.filter(\.isPast).sorted { $0.startDate > $1.startDate }
        }
    }

    /// Distinct years present in this tab, ordered soonest-first for Upcoming
    /// and most-recent-first for Past.
    private var years: [Int] {
        let set = Set(shown.map { Calendar.current.component(.year, from: $0.startDate) })
        return set.sorted(by: filter == .upcoming ? (<) : (>))
    }

    /// Trips after applying the selected year pill.
    private var displayed: [Trip] {
        guard let year = selectedYear, years.contains(year) else { return shown }
        return shown.filter { Calendar.current.component(.year, from: $0.startDate) == year }
    }

    /// Whether anything is live right now. Checked here as well as inside the box
    /// so an inactive box contributes no stack spacing to the list.
    private var hasActiveTrip: Bool {
        shown.contains { TripStatus(trip: $0, records: statusRecords) != nil }
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
                        if years.count > 1 { yearPills }
                        tripList
                    }
                }
            }
            .sectionHeader(filter.rawValue, systemImage: filter.symbol, tint: filter.accent,
                           subtitle: shown.isEmpty ? nil : "\(displayed.count) \(displayed.count == 1 ? "trip" : "trips")")
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
            .fullScreenCover(isPresented: $showingFullMap) {
                FullMapView(trips: displayed, title: filter.rawValue)
            }
            .onAppear {
                #if DEBUG
                if ProcessInfo.processInfo.environment["SHOW_ADD"] == "1", filter == .upcoming {
                    showingAdd = true
                }
                if ProcessInfo.processInfo.environment["SHOW_FULLMAP"] == "1", filter == .upcoming {
                    showingFullMap = true
                }
                if let raw = ProcessInfo.processInfo.environment["OPEN_TRIP_INDEX"],
                   let i = Int(raw), filter == .upcoming, displayed.indices.contains(i) {
                    selectedTrip = displayed[i]
                }
                #endif
            }
        }
    }

    // MARK: Map header (interactive + zoomable)

    private var mapHeader: some View {
        Map(selection: $mapSelection) {
            ForEach(displayed) { trip in
                // One dashed line per leg, tinted by that leg's mode.
                ForEach(trip.displaySegments) { segment in
                    MapPolyline(coordinates: [segment.origin.coordinate, segment.destination.coordinate])
                        .stroke(segment.type.accent.opacity(0.85),
                                style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [1, 6]))
                }
                // A single tappable marker at the trip's final destination.
                Marker(trip.endPlace.displayName, systemImage: trip.type.symbol,
                       coordinate: trip.endPlace.coordinate)
                    .tint(trip.type.accent)
                    .tag(trip.persistentModelID)
            }
        }
        .mapStyle(.standard(elevation: .realistic))
        .frame(height: 320)
        .clipShape(.rect(cornerRadius: 24))
        .overlay(alignment: .topTrailing) {
            Button {
                showingFullMap = true
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.subheadline.weight(.semibold))
                    .padding(10)
                    .glassEffect(.regular, in: .circle)
            }
            .buttonStyle(.plain)
            .padding(12)
        }
        .padding([.horizontal, .top])
        .onChange(of: mapSelection) { _, id in
            guard let id else { return }
            selectedTrip = displayed.first { $0.persistentModelID == id }
            mapSelection = nil
        }
    }

    // MARK: Year filter pills

    private var yearPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                yearOption(title: "All", year: nil)
                ForEach(years, id: \.self) { year in
                    yearOption(title: String(year), year: year)
                }
            }
            .padding(5)
            .glassEffect(.regular, in: .capsule)
            .padding(.horizontal)
            // Animate only the selection highlight; the card list swaps instantly.
            .animation(.snappy(duration: 0.28), value: selectedYear)
        }
        .scrollClipDisabled()
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    private func yearOption(title: String, year: Int?) -> some View {
        let isSelected = selectedYear == year
        return Button {
            selectedYear = year
        } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isSelected ? .white : .primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(filter.accent.gradient)
                            .matchedGeometryEffect(id: "yearHighlight", in: pillNamespace)
                    }
                }
        }
        .buttonStyle(.plain)
    }

    private var tripList: some View {
        ScrollView {
            GlassEffectContainer(spacing: 16) {
                LazyVStack(spacing: 16) {
                    // Scrolls with the cards rather than sitting above them: a box
                    // with three live trips in it is taller than the space the list
                    // can spare, and pinning it would leave nothing to scroll.
                    // Only Upcoming can hold a trip that's under way — once the last
                    // leg lands the trip has already moved to Past.
                    if filter == .upcoming, hasActiveTrip {
                        ActiveTripsBox(trips: shown) { selectedTrip = $0 }
                    }
                    ForEach(displayed) { trip in
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
        .environment(FlightTracker())
}
#endif
