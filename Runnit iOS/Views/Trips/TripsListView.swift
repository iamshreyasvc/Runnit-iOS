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
import CoreLocation
import Combine

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

    @Environment(\.modelContext) private var context
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
    // Draggable trip sheet: which detent it rests at, plus the live drag amount.
    @State private var sheetDetent: SheetDetent = .medium
    @GestureState private var sheetDrag: CGFloat = 0
    // Whether the year-filter dropdown bubble is open.
    @State private var showYearMenu = false
    // Live device location for the "center on me" button, and the current map
    // camera so recenters and zoom steps preserve the existing zoom level.
    @State private var location = LocationProvider()
    @State private var currentCamera: MapCamera?
    @Namespace private var pillNamespace

    /// The clock this tab classifies against. Ticked every minute so a trip that
    /// crosses its (effective) end while the screen is open migrates between
    /// Upcoming and Past on its own — no interaction required.
    @State private var now = Date()
    private let clock = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    /// How tall the trip sheet rests. `minimized` collapses it to a floating
    /// pill; the rest is exposed, fully-interactive map.
    private enum SheetDetent: CaseIterable {
        case minimized, medium, large
        func height(in total: CGFloat) -> CGFloat {
            switch self {
            case .minimized: return 76      // just the floating pill
            case .medium:    return total * 0.55
            case .large:     return total * 0.92
            }
        }
    }
    @State private var selectedYear: Int? = {
        #if DEBUG
        if let raw = ProcessInfo.processInfo.environment["YEAR"], let y = Int(raw) { return y }
        #endif
        return nil
    }()

    /// Trips for this tab (before the year filter).
    private var shown: [Trip] {
        switch filter {
        case .upcoming: return allTrips.filter { !isSettled($0) }.sorted { $0.startDate < $1.startDate }
        case .past:     return allTrips.filter(isSettled).sorted { $0.startDate > $1.startDate }
        }
    }

    /// A trip files under Past only once it is actually over, judged on its
    /// *effective* end — live records can push it later (a delayed flight is
    /// still in the air after its booked arrival: never Past) or pull it earlier
    /// (a leg that already landed is over even if the booked arrival hasn't
    /// come round: never Upcoming). While `TripStatus` says the trip is
    /// happening it always stays on Upcoming, where the live card lives.
    private func isSettled(_ trip: Trip) -> Bool {
        guard TripStatus(trip: trip, records: statusRecords, now: now) == nil else { return false }
        return TripStatus.effectiveEnd(of: trip, records: statusRecords, now: now) < now
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
        shown.contains { TripStatus(trip: $0, records: statusRecords, now: now) != nil }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                if shown.isEmpty {
                    AppBackground(accent: filter.accent, secondary: .teal)
                    emptyState
                } else {
                    GeometryReader { proxy in
                        let layout = MapLayout(containerSize: proxy.size)
                        ZStack(alignment: .bottom) {
                            mapBackground
                            switch layout {
                            case .stacked:
                                tripSheet(height: proxy.size.height)
                            case .sideBySide:
                                tripPanel(layout: layout)
                            }
                            mapTopControls(layout: layout)
                        }
                    }
                }
            }
            // The Upcoming/Past title now lives inside the sheet as a pill; keep
            // the bar minimal so the map reads full-bleed behind it.
            .navigationTitle(shown.isEmpty ? filter.rawValue : "")
            .navigationBarTitleDisplayMode(.inline)
            .onReceive(clock) { now = $0 }
            // Fill in real routes for every trip on this tab — active and past —
            // so their maps draw the true path (a road trip's roads, an Indian
            // train's rail line) without needing the trip's detail view to be
            // opened first. No tracker is passed, so flight-track fetches (which
            // spend FR24 credits) stay confined to the detail view; the free
            // road-trip and train routing runs here. Re-runs when the tab's set
            // of trips changes; RouteRefresher no-ops legs already routed.
            .task(id: shown.map(\.persistentModelID)) {
                await RouteRefresher.refresh(shown.flatMap(\.displaySegments), in: context)
            }
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
                location.request()
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

    /// The full-bleed map behind the trip sheet. Nothing overlays the area above
    /// the sheet, so its routes and pins stay fully interactive — pan, zoom, and
    /// tap inline without opening the full-screen view.
    private var mapBackground: some View {
        map.ignoresSafeArea()
    }

    /// The draggable trip sheet pinned to the bottom. Everything above it is
    /// unobstructed, fully-interactive map. Slide it down to minimize it to a
    /// floating pill (tap or swipe the pill up to bring the list back).
    private func tripSheet(height: CGFloat) -> some View {
        let dragging = sheetDrag != 0
        let resting = sheetDetent.height(in: height)
        let live = min(max(resting - sheetDrag, SheetDetent.minimized.height(in: height)),
                       SheetDetent.large.height(in: height))
        return ZStack(alignment: .bottom) {
            // Cross-fade the bodies with opacity so the shared pill's
            // matchedGeometry morph is the star of the transition.
            if sheetDetent == .minimized && !dragging {
                minimizedPill(layout: .stacked)
                    .transition(.opacity)
            } else {
                expandedSheet(sheetHeight: live, containerHeight: height)
                    .transition(.opacity)
            }
        }
        .animation(.snappy(duration: 0.32), value: sheetDetent)
    }

    /// The full glass sheet: grab handle, the tab-title pill, then the scrolling
    /// trip list (year filters + cards).
    private func expandedSheet(sheetHeight: CGFloat, containerHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            grabHandle(height: containerHeight)
            panelHeader(layout: .stacked)
            panelContent
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

    /// Pinned header shared by the bottom sheet and the landscape panel: the
    /// title pill, the year filter, and — in landscape, where the panel can be
    /// tucked away — the collapse control. One row in both layouts; the panel
    /// just shrinks the type and padding to fit its narrower column.
    private func panelHeader(layout: MapLayout) -> some View {
        let compact = layout.usesCompactChrome
        return HStack(spacing: compact ? 8 : 10) {
            filterPill(compact: compact)
            Spacer(minLength: 0)
            if !years.isEmpty { yearDropdown(compact: compact) }
            if compact { collapseButton }
        }
        // `nil` keeps the platform default, leaving the portrait sheet untouched.
        .padding(.horizontal, compact ? 12 : nil)
        .padding(.top, compact ? 14 : 0)
        .padding(.bottom, 12)
    }

    /// The scrolling body shared by the bottom sheet and the landscape panel.
    private var panelContent: some View {
        ScrollView {
            VStack(spacing: 16) {
                if showsLiveSection {
                    ActiveTripsBox(trips: shown) { selectedTrip = $0 }
                }
                cardsList
            }
            .padding(.horizontal)
            .padding(.top, 2)
            .padding(.bottom, 48)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: Landscape side panel

    /// The landscape counterpart of the trip sheet: a floating glass card on the
    /// leading edge, full height, with the map fully visible beside it. Collapses
    /// to the same floating pill — swipe the panel toward the leading edge (or
    /// tap the chevron) to tuck it away, and tap the pill to bring it back.
    private func tripPanel(layout: MapLayout) -> some View {
        // A leading column the full height of the safe area. The panel fills it;
        // the collapsed pill sits at its bottom, where the sheet's pill lives in
        // portrait, so the morph between the two reads as the same object.
        HStack(spacing: 0) {
            Group {
                if sheetDetent == .minimized {
                    minimizedPill(layout: layout)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .transition(.opacity)
                } else {
                    VStack(spacing: 0) {
                        panelHeader(layout: layout)
                        panelContent
                    }
                    .frame(width: layout.panelWidth, alignment: .top)
                    .frame(maxHeight: .infinity)
                    .background {
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .shadow(color: .black.opacity(0.18), radius: 14, x: 3)
                    }
                    .gesture(
                        DragGesture(coordinateSpace: .global).onEnded { value in
                            if value.translation.width < -40 { sheetDetent = .minimized }
                        }
                    )
                    .transition(.opacity)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, layout.gutter)
        .padding(.vertical, layout.gutter)
        .animation(.snappy(duration: 0.32), value: sheetDetent)
    }

    /// Tucks the landscape panel away, leaving the whole map clear.
    private var collapseButton: some View {
        Button {
            sheetDetent = .minimized
        } label: {
            Image(systemName: "chevron.left")
                .font(.footnote.weight(.bold))
                .foregroundStyle(.secondary)
                .frame(width: 34, height: 34)
                .glassEffect(.regular, in: .circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Hide trip list")
    }

    /// The tab title as a liquid-glass pill — icon, "Upcoming"/"Past", and count.
    /// Shares a matchedGeometry id so it morphs into the minimized floating pill.
    /// `chevron` is the glyph hinting how to restore the collapsed list —
    /// omitted while the sheet/panel is open.
    private func filterPill(compact: Bool = false, chevron: String? = nil) -> some View {
        HStack(spacing: compact ? 7 : 10) {
            Image(systemName: filter.symbol)
                .font((compact ? Font.subheadline : .headline).weight(.bold))
                .foregroundStyle(filter.accent)
            Text(filter.rawValue)
                .font((compact ? Font.headline : .title2).weight(.heavy))
                .lineLimit(1)
            Text("\(displayed.count)")
                .font((compact ? Font.caption : .subheadline).weight(.bold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, compact ? 7 : 9)
                .padding(.vertical, compact ? 2 : 3)
                .background(.secondary.opacity(0.15), in: .capsule)
            if let chevron {
                Image(systemName: chevron)
                    .font((compact ? Font.caption : .subheadline).weight(.bold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, compact ? 14 : 20)
        .padding(.vertical, compact ? 10 : 14)
        .glassEffect(.regular, in: .capsule)
        .matchedGeometryEffect(id: "filterPill", in: pillNamespace)
    }

    /// The grab strip at the top of the sheet. Dragging it resizes the sheet and
    /// snaps to the nearest detent (drag all the way down to minimize); a tap
    /// toggles between medium and large.
    private func grabHandle(height: CGFloat) -> some View {
        Capsule()
            .fill(.secondary.opacity(0.5))
            .frame(width: 40, height: 5)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
            .gesture(
                // Global space so the handle sliding up under the finger as the
                // sheet grows can't feed back into the translation and cause jitter.
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

    /// The collapsed sheet: the title pill floating at the bottom. Tap it, or
    /// swipe it up, to bring the list back. It's the same pill as the sheet's
    /// title, so minimizing/restoring morphs between the two positions.
    private func minimizedPill(layout: MapLayout) -> some View {
        let sideways = layout == .sideBySide
        // Match the header pill's size in each layout so the matchedGeometry
        // morph is a move, not a resize.
        return filterPill(compact: sideways, chevron: sideways ? "chevron.right" : "chevron.up")
            .padding(.bottom, 10)
            .contentShape(.capsule)
            .onTapGesture { sheetDetent = .medium }
            .gesture(
                // Restore with a swipe back out of the edge it tucked into.
                DragGesture().onEnded { value in
                    let restored = sideways
                        ? value.translation.width > 24
                        : value.translation.height < -24
                    if restored { sheetDetent = .medium }
                }
            )
    }

    // MARK: Map controls, live badge, and route preview

    /// Floating controls above the map: the live badge (or a tapped route's
    /// preview) on the left and the full-screen expand button on the right. Kept
    /// out of the map's ignored safe area so they clear the navigation bar, and
    /// in landscape inset past the side panel so nothing hides beneath it.
    private func mapTopControls(layout: MapLayout) -> some View {
        VStack(spacing: 8) {
            HStack(alignment: .top) {
                if previewTrip == nil, let status = liveStatus {
                    liveBadge(status)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                Spacer(minLength: 0)
                // Landscape has far less height to spend, and the toolbar's add
                // button sits directly above — draw the column tighter there.
                VStack(spacing: layout.usesCompactChrome ? 6 : 10) {
                    Button {
                        showingFullMap = true
                    } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.subheadline.weight(.semibold))
                            .padding(12)
                            .glassEffect(.regular, in: .circle)
                    }
                    .buttonStyle(.plain)

                    zoomControls

                    // Recenter on the traveler's location, keeping the zoom level.
                    Button {
                        recenterOnUser()
                    } label: {
                        Image(systemName: "location.fill")
                            .font(.subheadline.weight(.semibold))
                            .padding(12)
                            .glassEffect(.regular, in: .circle)
                    }
                    .buttonStyle(.plain)
                }
            }
            if let trip = previewTrip {
                routePreview(trip)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.horizontal)
        .padding(.leading, layout.leadingInset(collapsed: sheetDetent == .minimized))
        .padding(.top, layout.usesCompactChrome ? 12 : 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.snappy(duration: 0.3), value: previewTrip?.persistentModelID)
        .animation(.snappy(duration: 0.32), value: sheetDetent)
    }

    /// A clean vertical +/− zoom control, styled to match the round map buttons.
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

    /// Smoothly scale the camera distance around its current center, keeping the
    /// heading and pitch. Clamped so it can't zoom past street or globe level.
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

    /// Recenter on the device location without changing the zoom level (uses the
    /// current camera distance). Falls back to framing the trips if we don't have
    /// a fix yet.
    private func recenterOnUser() {
        withAnimation(.smooth(duration: 0.4)) {
            if let coord = location.coordinate {
                camera = .camera(MapCamera(centerCoordinate: coord,
                                           distance: currentCamera?.distance ?? 3_000_000))
            } else {
                camera = .userLocation(fallback: .automatic)
            }
        }
    }

    /// The most imminent live trip's reading — drives the floating live badge.
    private var liveStatus: TripStatus? {
        guard showsLiveSection else { return nil }
        return shown
            .compactMap { TripStatus(trip: $0, records: statusRecords, now: now) }
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
                    // Real routes when cached, straight lines otherwise — and
                    // the live aircraft while a flight leg is airborne.
                    SegmentRouteContent(segment: segment,
                                        live: statusRecords.liveRecord(for: segment))
                }
                Annotation(trip.endPlace.displayName, coordinate: trip.endPlace.coordinate) {
                    mapPin(trip)
                }
                .tag(trip.persistentModelID)
                .annotationTitles(.hidden)
            }
            UserAnnotation()
        }
        .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll))
        .mapControls {
            MapCompass()
            MapScaleView()
        }
        .onMapCameraChange(frequency: .continuous) { context in
            currentCamera = context.camera
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

    // MARK: Year filter dropdown

    /// The year filter as a compact dropdown chip inline with the title pill.
    /// Tapping it opens a bubble popover that emerges from the pill row.
    private func yearDropdown(compact: Bool = false) -> some View {
        Button {
            showYearMenu = true
        } label: {
            HStack(spacing: compact ? 5 : 8) {
                Text(selectedYear.map(String.init) ?? "All")
                    .font((compact ? Font.subheadline : .title2).weight(.heavy))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font((compact ? Font.caption2 : .subheadline).weight(.bold))
                    .foregroundStyle(filter.accent)
                    .rotationEffect(.degrees(showYearMenu ? 180 : 0))
            }
            .padding(.horizontal, compact ? 12 : 18)
            .padding(.vertical, compact ? 10 : 14)
            .glassEffect(.regular, in: .capsule)
        }
        .buttonStyle(.plain)
        .animation(.snappy(duration: 0.25), value: showYearMenu)
        .popover(isPresented: $showYearMenu, arrowEdge: .top) {
            VStack(spacing: 4) {
                yearMenuRow(title: "All", year: nil)
                ForEach(years, id: \.self) { year in
                    yearMenuRow(title: String(year), year: year)
                }
            }
            .padding(10)
            .frame(minWidth: 190)
            .presentationCompactAdaptation(.popover)
        }
    }

    private func yearMenuRow(title: String, year: Int?) -> some View {
        let isSelected = selectedYear == year
        return Button {
            selectedYear = year
            showYearMenu = false
        } label: {
            HStack(spacing: 12) {
                Text(title).font(.body.weight(.semibold))
                Spacer(minLength: 16)
                if isSelected {
                    Image(systemName: "checkmark").font(.subheadline.weight(.bold))
                }
            }
            .foregroundStyle(isSelected ? filter.accent : .primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? filter.accent.opacity(0.15) : .clear)
            )
            .contentShape(.rect)
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
                        // Navigate by setting `selectedTrip` — the same path the
                        // Happening Now box and the map's route preview use — so the
                        // whole screen drives one `navigationDestination(item:)`.
                        // Mixing that with closure-based NavigationLinks shadows the
                        // item destination and silently breaks those other taps.
                        Button {
                            selectedTrip = trip
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

/// Publishes the device's current coordinate for the map's "center on me"
/// button. Read-only: it never writes anything, and only updates while the
/// Trips screen is on-screen.
@Observable
final class LocationProvider: NSObject, CLLocationManagerDelegate {
    @ObservationIgnored private let manager = CLLocationManager()
    var coordinate: CLLocationCoordinate2D?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func request() {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
        manager.startUpdatingLocation()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let last = locations.last { coordinate = last.coordinate }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.startUpdatingLocation()
        default:
            break
        }
    }
}

#if DEBUG
#Preview("Portrait") {
    TripsListView(filter: .upcoming)
        .modelContainer(PreviewData.container)
        .environment(FlightTracker())
}

#Preview("Landscape", traits: .landscapeLeft) {
    TripsListView(filter: .upcoming)
        .modelContainer(PreviewData.container)
        .environment(FlightTracker())
}
#endif
