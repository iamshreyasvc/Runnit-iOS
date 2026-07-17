//
//  PassportView.swift
//  Runnit iOS
//
//  The "Passport", rebuilt in the Upcoming/Past design language: a full-bleed
//  world map of everywhere the traveler has been as the backdrop, with a
//  draggable glass sheet sliding up over it. The sheet distills completed trips
//  into a passport-cover hero, playful fun facts, hand-drawn charts (mode split,
//  trips by year, a twelve-month rhythm), continent coverage, stamps, and
//  achievements. Drag the sheet down to a floating pill to explore the map.
//

import SwiftUI
import SwiftData
import MapKit

struct PassportView: View {
    @Query private var allTrips: [Trip]
    @AppStorage(PrefKey.displayName) private var displayName = "Traveler"

    @State private var showingFullMap = false
    @State private var selectedTrip: Trip?
    @State private var mapSelection: PersistentIdentifier?
    @State private var camera: MapCameraPosition = .automatic
    @State private var currentCamera: MapCamera?

    // Draggable sheet: which detent it rests at, plus the live drag amount.
    @State private var sheetDetent: SheetDetent = .medium
    @GestureState private var sheetDrag: CGFloat = 0
    @Namespace private var pillNamespace

    private let accent = Color.indigo

    private var stats: TripStatistics { TripStatistics(trips: allTrips) }
    /// Completed trips, most-recent first — what the map and stats describe.
    private var pastTrips: [Trip] {
        stats.pastTrips.sorted { $0.startDate > $1.startDate }
    }

    private let statColumns = [GridItem(.adaptive(minimum: 150), spacing: 14)]
    private let stampColumns = [GridItem(.adaptive(minimum: 104), spacing: 14)]
    private let badgeColumns = [GridItem(.adaptive(minimum: 108), spacing: 14)]

    /// How tall the sheet rests. `minimized` collapses it to a floating pill so
    /// the whole travel map is exposed.
    private enum SheetDetent: CaseIterable {
        case minimized, medium, large
        func height(in total: CGFloat) -> CGFloat {
            switch self {
            case .minimized: return 76
            case .medium:    return total * 0.58
            case .large:     return total * 0.92
            }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                if stats.totalTrips == 0 {
                    AppBackground(accent: accent, secondary: .pink)
                    emptyState
                } else {
                    GeometryReader { proxy in
                        ZStack(alignment: .bottom) {
                            mapBackground
                            mapTopControls
                            passportSheet(height: proxy.size.height)
                        }
                    }
                }
            }
            .navigationTitle(stats.totalTrips == 0 ? "Passport" : "")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(item: $selectedTrip) { TripDetailView(trip: $0) }
            .fullScreenCover(isPresented: $showingFullMap) {
                FullMapView(trips: pastTrips, title: "Where I've Been")
            }
        }
    }

    // MARK: - Travel map backdrop

    /// The full-bleed world map behind the sheet: every completed trip's route
    /// and destination pin. The area above the sheet stays fully interactive.
    private var mapBackground: some View {
        Map(position: $camera, selection: $mapSelection) {
            ForEach(pastTrips) { trip in
                ForEach(trip.displaySegments) { segment in
                    // Real roads for routed road trips; otherwise a clean endpoint
                    // hop (intermediate stops are intentionally omitted here).
                    let coords = segment.routedCoordinates ?? [segment.origin.coordinate, segment.destination.coordinate]
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
        .mapControls { MapCompass() }
        .onMapCameraChange(frequency: .continuous) { currentCamera = $0.camera }
        .onChange(of: mapSelection) { _, id in
            // Guard against the nil we write below re-entering and clearing the
            // selection we just made.
            guard let id else { return }
            selectedTrip = pastTrips.first { $0.persistentModelID == id }
            mapSelection = nil
        }
        .ignoresSafeArea()
    }

    /// A custom destination pin — the mode glyph in a tinted disc, ringed white.
    private func mapPin(_ trip: Trip) -> some View {
        Image(systemName: trip.type.symbol)
            .font(.system(size: 12, weight: .black))
            .foregroundStyle(.white)
            .frame(width: 28, height: 28)
            .background(trip.type.gradient, in: .circle)
            .overlay(Circle().strokeBorder(.white, lineWidth: 2))
            .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
    }

    /// Floating map controls: a passport-summary badge on the left, expand and
    /// zoom on the right. Kept clear of the map's ignored safe area.
    private var mapTopControls: some View {
        HStack(alignment: .top) {
            coverageBadge
            Spacer(minLength: 0)
            VStack(spacing: 10) {
                Button { showingFullMap = true } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.subheadline.weight(.semibold))
                        .padding(12)
                        .glassEffect(.regular, in: .circle)
                }
                .buttonStyle(.plain)

                zoomControls
            }
        }
        .padding(.horizontal)
        .padding(.top, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// A small glass badge summarizing coverage — sits where the Trips map shows
    /// its live badge.
    private var coverageBadge: some View {
        HStack(spacing: 7) {
            Image(systemName: "globe.americas.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(accent)
            Text("\(stats.uniqueCountries.count) \(stats.uniqueCountries.count == 1 ? "country" : "countries")")
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: .capsule)
    }

    private var zoomControls: some View {
        VStack(spacing: 0) {
            zoomButton("plus") { zoom(by: 0.5) }
            Divider().frame(width: 22).opacity(0.6)
            zoomButton("minus") { zoom(by: 2) }
        }
        .glassEffect(.regular, in: .capsule)
    }

    private func zoomButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.subheadline.weight(.bold))
                .frame(width: 42, height: 40)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    /// Smoothly scale the camera distance around its current center. Clamped so
    /// it can't zoom past street or globe level.
    private func zoom(by factor: Double) {
        guard let cam = currentCamera else { return }
        let distance = min(max(cam.distance * factor, 400), 40_000_000)
        withAnimation(.smooth(duration: 0.35)) {
            camera = .camera(MapCamera(centerCoordinate: cam.centerCoordinate,
                                       distance: distance,
                                       heading: cam.heading,
                                       pitch: cam.pitch))
        }
    }

    // MARK: - Draggable passport sheet

    private func passportSheet(height: CGFloat) -> some View {
        let dragging = sheetDrag != 0
        let resting = sheetDetent.height(in: height)
        let live = min(max(resting - sheetDrag, SheetDetent.minimized.height(in: height)),
                       SheetDetent.large.height(in: height))
        return ZStack(alignment: .bottom) {
            if sheetDetent == .minimized && !dragging {
                minimizedPill.transition(.opacity)
            } else {
                expandedSheet(sheetHeight: live, containerHeight: height)
                    .transition(.opacity)
            }
        }
        .animation(.snappy(duration: 0.32), value: sheetDetent)
    }

    private func expandedSheet(sheetHeight: CGFloat, containerHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            grabHandle(height: containerHeight)
            HStack {
                passportPill(minimized: false)
                Spacer(minLength: 0)
            }
            .padding(.horizontal)
            .padding(.bottom, 12)

            ScrollView {
                VStack(spacing: 24) {
                    PassportHeroCard(name: displayName,
                                     trips: stats.totalTrips,
                                     countries: stats.uniqueCountries.count,
                                     continents: stats.continents.count)
                        .appear(0)
                    funFactsSection.appear(1)
                    if !stats.modeBreakdown.isEmpty { gettingAroundSection.appear(2) }
                    if !stats.tripsByYear.isEmpty { yearSection.appear(3) }
                    rhythmSection.appear(4)
                    if !stats.continents.isEmpty { coverageSection.appear(5) }
                    statsSection.appear(6)
                    if !stats.uniqueCountries.isEmpty { stampsSection.appear(7) }
                    highlightsSection.appear(8)
                    achievementsSection.appear(9)
                }
                .padding(.horizontal)
                .padding(.top, 2)
                .padding(.bottom, 48)
            }
            .scrollIndicators(.hidden)
        }
        .frame(height: sheetHeight, alignment: .top)
        .frame(maxWidth: .infinity)
        .background {
            UnevenRoundedRectangle(topLeadingRadius: 30, topTrailingRadius: 30)
                .fill(.ultraThinMaterial)
                .ignoresSafeArea(edges: .bottom)
                .shadow(color: .black.opacity(0.18), radius: 14, y: -3)
        }
    }

    /// The tab title as a liquid-glass pill — icon, "Passport", and the country
    /// count. Shares a matchedGeometry id so it morphs into the floating pill.
    private func passportPill(minimized: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "book.closed.fill")
                .font(.headline.weight(.bold))
                .foregroundStyle(accent)
            Text("Passport")
                .font(.title2.weight(.heavy))
            Text("\(stats.uniqueCountries.count)")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .background(.secondary.opacity(0.15), in: .capsule)
            if minimized {
                Image(systemName: "chevron.up")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .glassEffect(.regular, in: .capsule)
        .matchedGeometryEffect(id: "passportPill", in: pillNamespace)
    }

    private func grabHandle(height: CGFloat) -> some View {
        Capsule()
            .fill(.secondary.opacity(0.5))
            .frame(width: 40, height: 5)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
            .gesture(
                DragGesture(coordinateSpace: .global)
                    .updating($sheetDrag) { value, state, _ in state = value.translation.height }
                    .onEnded { value in
                        let target = sheetDetent.height(in: height) - value.translation.height
                        sheetDetent = SheetDetent.allCases.min {
                            abs($0.height(in: height) - target) < abs($1.height(in: height) - target)
                        } ?? .medium
                    }
            )
            .onTapGesture {
                sheetDetent = sheetDetent == .large ? .medium : .large
            }
    }

    private var minimizedPill: some View {
        passportPill(minimized: true)
            .padding(.bottom, 10)
            .contentShape(.capsule)
            .onTapGesture { sheetDetent = .medium }
            .gesture(
                DragGesture().onEnded { value in
                    if value.translation.height < -24 { sheetDetent = .medium }
                }
            )
    }

    // MARK: - Sheet sections

    private var funFactsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Fun Facts", systemImage: "sparkles", tint: .yellow)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(stats.funFacts) { FunFactCard(fact: $0) }
                }
                .padding(.horizontal, 2)
            }
            .scrollClipDisabled()
        }
    }

    private var gettingAroundSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Getting Around", systemImage: "arrow.triangle.swap", tint: .blue)
            ModeSplitDonut(modes: stats.modeBreakdown)
        }
    }

    private var yearSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Trips by Year", systemImage: "chart.bar.fill", tint: accent)
            YearBarChart(data: stats.tripsByYear, tint: accent)
        }
    }

    private var rhythmSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Travel Rhythm", systemImage: "waveform.path.ecg", tint: .pink)
            MonthRhythmChart(months: stats.tripsByMonth, tint: .pink)
        }
    }

    private var coverageSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "World Coverage", systemImage: "globe", tint: .teal)
            ContinentCoverageCard(visited: stats.continents)
        }
    }

    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "By the Numbers", systemImage: "number", tint: .green)
            LazyVGrid(columns: statColumns, spacing: 14) {
                StatCard(title: "Total distance",
                         value: Format.distance(stats.totalDistanceMeters),
                         systemImage: "ruler", tint: .blue)
                StatCard(title: "This year",
                         value: "\(stats.tripsThisYear) trips",
                         systemImage: "calendar", tint: .green)
                StatCard(title: "Cities",
                         value: "\(stats.uniqueCities)",
                         systemImage: "building.2.fill", tint: .purple)
                if stats.totalTravelTime > 0 {
                    StatCard(title: "Time in transit",
                             value: Format.duration(stats.totalTravelTime),
                             systemImage: "clock.fill", tint: .orange)
                }
            }
        }
    }

    private var stampsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Stamps", systemImage: "seal.fill", tint: .indigo,
                         accessory: "\(stats.uniqueCountries.count)")
            LazyVGrid(columns: stampColumns, spacing: 14) {
                ForEach(stats.uniqueCountries) { PassportStamp(country: $0) }
            }
        }
    }

    @ViewBuilder
    private var highlightsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Highlights", systemImage: "star.fill", tint: .orange)
            VStack(spacing: 10) {
                if let longest = stats.longestTrip {
                    highlightRow(icon: "arrow.up.right.circle.fill", tint: .orange,
                                 title: "Longest trip",
                                 detail: "\(longest.displayTitle) · \(Format.distance(longest.distanceMeters))")
                }
                if let city = stats.favoriteCity {
                    highlightRow(icon: "heart.fill", tint: .pink,
                                 title: "Favorite city",
                                 detail: "\(city.name) · \(city.count) \(city.count == 1 ? "visit" : "visits")")
                }
                if let first = stats.firstTrip {
                    highlightRow(icon: "flag.checkered", tint: .purple,
                                 title: "First trip",
                                 detail: "\(first.displayTitle) · \(Format.date(first.departureDate, in: first.startPlace.timeZone))")
                }
                if let recent = stats.mostRecentTrip {
                    highlightRow(icon: "clock.fill", tint: .teal,
                                 title: "Most recent",
                                 detail: "\(recent.displayTitle) · \(Format.date(recent.departureDate, in: recent.startPlace.timeZone))")
                }
            }
            .glassCard()
        }
    }

    private func highlightRow(icon: String, tint: Color, title: String, detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(detail).font(.callout.weight(.medium)).lineLimit(1)
            }
            Spacer()
        }
    }

    private var achievementsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            let unlocked = stats.achievements.filter(\.isUnlocked).count
            SectionTitle(title: "Achievements", systemImage: "trophy.fill", tint: .yellow,
                         accessory: "\(unlocked)/\(stats.achievements.count)")
            LazyVGrid(columns: badgeColumns, spacing: 14) {
                ForEach(stats.achievements) { AchievementBadge(achievement: $0) }
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        ContentUnavailableView(
            "Your Passport is empty",
            systemImage: "book.closed",
            description: Text("Completed trips unlock a travel map, stamps, charts, and fun facts here.")
        )
        .padding(.top, 80)
    }
}

#if DEBUG
#Preview {
    PassportView()
        .modelContainer(PreviewData.container)
}
#endif
