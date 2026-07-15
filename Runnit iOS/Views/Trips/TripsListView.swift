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
    // Drives the collapsing map header: how far the list has scrolled, and the
    // natural height of the section below the map (measured while expanded).
    @State private var scrollY: CGFloat = 0
    @State private var extraHeight: CGFloat = 0
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
                        if !years.isEmpty { yearPills }
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

    // MARK: Map card (interactive + zoomable)

    /// Whether the live "Happening Now" section is shown, merged into the map
    /// card. Only Upcoming can hold a trip that's under way.
    private var showsLiveSection: Bool { filter == .upcoming && hasActiveTrip }

    /// How collapsed the header is, 0 (top) → 1 (scrolled past the threshold).
    /// Drives the map shrinking and the section below folding away, so scrolling
    /// the list reveals more of it on both tabs.
    private var collapse: CGFloat {
        let threshold: CGFloat = 150
        return min(max(scrollY / threshold, 0), 1)
    }

    /// The map's height for the current collapse state.
    private var mapHeight: CGFloat {
        let expanded: CGFloat = showsLiveSection ? 210 : 250
        let collapsed: CGFloat = 120
        return expanded - (expanded - collapsed) * collapse
    }

    /// The map sits inside a clean, untinted glass card: a titled header, the map
    /// framed within it, and — when something is live — the "Happening Now"
    /// section merged in directly below, otherwise a small summary footer. Reads
    /// as one cohesive unit rather than a slab floating above the list, and
    /// minimizes as the list scrolls.
    private var mapHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: mapTitle, systemImage: "map.fill",
                         tint: filter.accent, accessory: mapAccessory)

            map
                .frame(height: mapHeight)
                .clipShape(.rect(cornerRadius: 16))
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
                    .padding(10)
                }
                // As the header collapses and the live section folds away, a
                // compact badge fades in so what's happening now is still visible.
                .overlay(alignment: .topLeading) {
                    if collapse > 0, let status = liveStatus {
                        liveBadge(status)
                            .opacity(collapse)
                            .padding(10)
                    }
                }
                .onChange(of: mapSelection) { _, id in
                    guard let id else { return }
                    selectedTrip = displayed.first { $0.persistentModelID == id }
                    mapSelection = nil
                }

            // The live box / summary folds up and fades as the header collapses.
            // Its natural height is measured only while expanded, so the collapse
            // interpolation stays stable.
            extraSection
                .background {
                    GeometryReader { geo in
                        Color.clear
                            .onAppear { extraHeight = geo.size.height }
                            .onChange(of: geo.size.height) { _, h in
                                if collapse == 0 { extraHeight = h }
                            }
                    }
                }
                .frame(height: max(0, extraHeight * (1 - collapse)), alignment: .top)
                .opacity(1 - collapse)
                .clipped()
        }
        .glassCard()
        .padding([.horizontal, .top])
        .padding(.bottom, 12)
    }

    /// The content merged in below the map: the live box when something is under
    /// way, otherwise the small tap-hint + distance summary.
    @ViewBuilder private var extraSection: some View {
        if showsLiveSection {
            ActiveTripsBox(trips: shown, embedded: true) { selectedTrip = $0 }
        } else {
            mapSummary
        }
    }

    /// The most imminent live trip's reading — drives the collapsed-header badge.
    private var liveStatus: TripStatus? {
        guard showsLiveSection else { return nil }
        return shown
            .compactMap { TripStatus(trip: $0, records: statusRecords) }
            .min { ($0.timeRemaining ?? .greatestFiniteMagnitude) < ($1.timeRemaining ?? .greatestFiniteMagnitude) }
    }

    /// A small tinted pill — the active phase's icon wrapped in a circular
    /// progress ring, plus a short label — matching the "Happening Now" styling.
    private func liveBadge(_ status: TripStatus) -> some View {
        HStack(spacing: 7) {
            ZStack {
                Circle()
                    .stroke(.white.opacity(0.3), lineWidth: 2.5)
                if let progress = status.progress {
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(.white, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                Image(systemName: status.puckIcon)
                    .font(.system(size: 10, weight: .bold))
            }
            .frame(width: 22, height: 22)

            Text(status.headline)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(.white)
        .padding(.leading, 7)
        .padding(.trailing, 12)
        .padding(.vertical, 6)
        .background(status.tint.gradient, in: .capsule)
        .shadow(color: status.tint.opacity(0.4), radius: 5, y: 2)
    }

    /// The interactive map itself, shared by the card frame above.
    private var map: some View {
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
    }

    private var mapTitle: String {
        filter == .upcoming ? "Where you're headed" : "Where you've been"
    }

    /// Distinct final destinations pinned on the map.
    private var destinationCount: Int {
        Set(displayed.map(\.endPlace.displayName)).count
    }

    private var mapAccessory: String? {
        guard destinationCount > 0 else { return nil }
        return "\(destinationCount) \(destinationCount == 1 ? "place" : "places")"
    }

    /// A footer tying the map to the list below: how to use it, plus the total
    /// distance across the shown trips.
    private var mapSummary: some View {
        let distance = displayed.reduce(0) { $0 + $1.distanceMeters }
        return HStack(spacing: 6) {
            Image(systemName: "hand.tap")
            Text("Tap a pin to open a trip")
            Spacer(minLength: 0)
            if distance > 0 {
                Text(Format.distance(distance))
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
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
                    let groups = sections
                    let showHeaders = groups.count > 1
                    ForEach(Array(groups.enumerated()), id: \.element.id) { groupIndex, section in
                        if showHeaders {
                            sectionLabel(section)
                                .padding(.top, groupIndex == 0 ? 0 : 8)
                        }
                        ForEach(Array(section.trips.enumerated()), id: \.element.id) { index, trip in
                            NavigationLink {
                                TripDetailView(trip: trip)
                            } label: {
                                TripCardView(trip: trip)
                            }
                            .buttonStyle(.pressableCard)
                            .appear(index)
                        }
                    }
                }
            }
            .padding()
        }
        .onScrollGeometryChange(for: CGFloat.self) { geo in
            geo.contentOffset.y + geo.contentInsets.top
        } action: { _, y in
            scrollY = y
        }
    }

    /// A lightweight header above each time-period group of cards.
    private func sectionLabel(_ section: TripSection) -> some View {
        HStack {
            Text(section.title)
                .font(.subheadline.weight(.bold))
            Spacer()
            Text("\(section.trips.count)")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 2)
    }

    // MARK: Time-period grouping

    private struct TripSection: Identifiable {
        let id = UUID()
        let title: String
        let trips: [Trip]
    }

    /// Buckets the displayed trips into time-period sections, preserving the
    /// tab's existing sort order (soonest-first for Upcoming, recent-first for Past).
    private var sections: [TripSection] {
        var order: [String] = []
        var buckets: [String: [Trip]] = [:]
        for trip in displayed {
            let title = bucketTitle(for: trip.startDate)
            if buckets[title] == nil { order.append(title) }
            buckets[title, default: []].append(trip)
        }
        return order.map { TripSection(title: $0, trips: buckets[$0] ?? []) }
    }

    private func bucketTitle(for date: Date) -> String {
        let cal = Calendar.current
        let now = Date()
        if filter == .upcoming {
            if cal.isDateInToday(date) { return "Today" }
            if let week = cal.dateInterval(of: .weekOfYear, for: now), week.contains(date) {
                return "This Week"
            }
            if cal.isDate(date, equalTo: now, toGranularity: .month) { return "This Month" }
            if cal.isDate(date, equalTo: now, toGranularity: .year) { return "Later This Year" }
            return String(cal.component(.year, from: date))
        } else {
            if cal.isDate(date, equalTo: now, toGranularity: .month) { return "This Month" }
            if cal.isDate(date, equalTo: now, toGranularity: .year) { return "Earlier This Year" }
            if let lastYear = cal.date(byAdding: .year, value: -1, to: now),
               cal.isDate(date, equalTo: lastYear, toGranularity: .year) {
                return "Last Year"
            }
            return String(cal.component(.year, from: date))
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
