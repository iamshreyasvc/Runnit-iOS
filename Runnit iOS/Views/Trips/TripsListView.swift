//
//  TripsListView.swift
//  Runnit iOS
//
//  A single filter (Upcoming or Past) as its own tab: a full-bleed interactive
//  map of that tab's trips as the backdrop, with a glass sheet of trip cards
//  that slides up over it. Tapping a route or pin previews the trip.
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
    // The trip whose route/pin is tapped on the map, shown as a floating preview.
    @State private var previewTrip: Trip?
    // Map camera; `.automatic` frames all currently shown trips.
    @State private var camera: MapCameraPosition = .automatic
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
            ZStack(alignment: .top) {
                if shown.isEmpty {
                    AppBackground(accent: filter.accent, secondary: .teal)
                    emptyState
                } else {
                    mapBackground
                    tripsSheet
                    mapTopControls
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

    // MARK: Map background + sliding trip sheet

    /// Only Upcoming can hold a trip that's under way.
    private var showsLiveSection: Bool { filter == .upcoming && hasActiveTrip }

    /// The full-bleed map the trip sheet slides up over. Its routes and pins stay
    /// interactive in the region above the sheet.
    private var mapBackground: some View {
        map.ignoresSafeArea()
    }

    /// A scroll view layered over the map: a transparent peek region keeps the top
    /// of the map visible and interactive, and the glass sheet of trips slides up
    /// over it as the list scrolls.
    private var tripsSheet: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    // The map shows through here; hit-testing is off so pans and
                    // taps in this band reach the map, not the scroll view.
                    Color.clear
                        .frame(height: proxy.size.height * 0.44)
                        .allowsHitTesting(false)

                    sheetBody(minHeight: proxy.size.height * 0.62)
                }
            }
            .scrollIndicators(.hidden)
        }
        .ignoresSafeArea(edges: .bottom)
    }

    private func sheetBody(minHeight: CGFloat) -> some View {
        VStack(spacing: 16) {
            Capsule()
                .fill(.secondary.opacity(0.5))
                .frame(width: 40, height: 5)
                .padding(.top, 8)

            if showsLiveSection {
                ActiveTripsBox(trips: shown) { selectedTrip = $0 }
            }
            if !years.isEmpty { yearPills }
            cardsList
        }
        .padding(.horizontal)
        .padding(.bottom, 48)
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .top)
        .background {
            UnevenRoundedRectangle(topLeadingRadius: 30, topTrailingRadius: 30)
                .fill(.ultraThinMaterial)
                .ignoresSafeArea(edges: .bottom)
                .shadow(color: .black.opacity(0.18), radius: 14, y: -3)
        }
    }

    // MARK: Map controls, live badge, and route preview

    /// Floating controls above the map: the live badge (or a tapped route's
    /// preview) on the left and the full-screen expand button on the right. Kept
    /// out of the map's ignored safe area so they clear the navigation bar.
    private var mapTopControls: some View {
        VStack(spacing: 8) {
            HStack(alignment: .top) {
                if previewTrip == nil, let status = liveStatus {
                    liveBadge(status)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                Spacer(minLength: 0)
                Button {
                    showingFullMap = true
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.subheadline.weight(.semibold))
                        .padding(12)
                        .glassEffect(.regular, in: .circle)
                }
                .buttonStyle(.plain)
            }
            if let trip = previewTrip {
                routePreview(trip)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.horizontal)
        .padding(.top, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.snappy(duration: 0.3), value: previewTrip?.persistentModelID)
    }

    /// The most imminent live trip's reading — drives the floating live badge.
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

    /// The popup shown when a route or pin is tapped: a glass card summarizing the
    /// trip, with a button to open its detail.
    private func routePreview(_ trip: Trip) -> some View {
        HStack(spacing: 12) {
            Image(systemName: trip.type.symbol)
                .font(.footnote.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(trip.type.gradient, in: .circle)

            VStack(alignment: .leading, spacing: 2) {
                Text(trip.displayTitle)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text("\(trip.startPlace.codeLabel) → \(trip.endPlace.codeLabel) · \(Format.date(trip.startDate, in: trip.startPlace.timeZone))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Button {
                selectedTrip = trip
                mapSelection = nil
            } label: {
                Text("Open")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(trip.type.accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .glassEffect(.regular, in: .capsule)
            }
            .buttonStyle(.plain)

            Button {
                mapSelection = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
        .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
    }

    // MARK: Interactive map

    /// Solid, casing-backed route lines per leg and a custom pin at each
    /// destination. `.automatic` frames all currently shown trips.
    private var map: some View {
        Map(position: $camera, selection: $mapSelection) {
            ForEach(displayed) { trip in
                ForEach(trip.displaySegments) { segment in
                    let coords = [segment.origin.coordinate, segment.destination.coordinate]
                    // A darker, wider casing under each solid line reads like a
                    // navigation route — crisp against land and water alike.
                    MapPolyline(coordinates: coords)
                        .stroke(.black.opacity(0.22),
                                style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
                    MapPolyline(coordinates: coords)
                        .stroke(segment.type.gradient,
                                style: StrokeStyle(lineWidth: 4.5, lineCap: .round, lineJoin: .round))
                }
                Annotation(trip.endPlace.displayName, coordinate: trip.endPlace.coordinate) {
                    mapPin(trip)
                }
                .tag(trip.persistentModelID)
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll))
        .mapControls {
            MapCompass()
            MapScaleView()
        }
        .onChange(of: mapSelection) { _, id in
            previewTrip = id.flatMap { pid in displayed.first { $0.persistentModelID == pid } }
        }
        .onChange(of: displayed.map(\.persistentModelID)) { _, _ in
            camera = .automatic
        }
    }

    /// A custom destination pin: the mode glyph in a tinted disc, ringed white,
    /// enlarged while selected.
    private func mapPin(_ trip: Trip) -> some View {
        Image(systemName: trip.type.symbol)
            .font(.system(size: 13, weight: .black))
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(trip.type.gradient, in: .circle)
            .overlay(Circle().strokeBorder(.white, lineWidth: 2))
            .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
            .scaleEffect(mapSelection == trip.persistentModelID ? 1.25 : 1)
            .animation(.snappy, value: mapSelection)
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
            // Animate only the selection highlight; the card list swaps instantly.
            .animation(.snappy(duration: 0.28), value: selectedYear)
        }
        .scrollClipDisabled()
        .frame(maxWidth: .infinity, alignment: .leading)
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

    private var cardsList: some View {
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

    /// IDs of trips already shown in the live "Happening Now" box, so the card
    /// list can omit them — an active trip appears once, not twice.
    private var liveTripIDs: Set<PersistentIdentifier> {
        guard showsLiveSection else { return [] }
        return Set(shown
            .filter { TripStatus(trip: $0, records: statusRecords) != nil }
            .map(\.persistentModelID))
    }

    /// Buckets the displayed trips into time-period sections, preserving the
    /// tab's existing sort order (soonest-first for Upcoming, recent-first for Past).
    /// Trips currently in the live box are left out so they aren't listed twice.
    private var sections: [TripSection] {
        var order: [String] = []
        var buckets: [String: [Trip]] = [:]
        for trip in displayed where !liveTripIDs.contains(trip.persistentModelID) {
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
