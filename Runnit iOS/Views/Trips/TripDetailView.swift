//
//  TripDetailView.swift
//  Runnit iOS
//
//  A trip's own screen, built like the Upcoming / Past tabs: the trip's route is
//  a full-bleed, interactive map, with a draggable glass sheet of details that
//  slides up over it. While the trip is underway the live status is pinned to the
//  top of the sheet (and onto the sheet's minimized pill) so "what's happening
//  now" stays visible no matter how far the details are scrolled.
//

import SwiftUI
import SwiftData
import MapKit

struct TripDetailView: View {
    @Bindable var trip: Trip

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(FlightTracker.self) private var tracker
    @Environment(SyncEngine.self) private var sync

    @Query private var statusRecords: [FlightStatusRecord]

    @State private var showingEdit = false
    @State private var showingDeleteConfirm = false
    @State private var showingShare = false
    @State private var showingParticipants = false
    @State private var showingLeaveConfirm = false
    @State private var leaveError: String?
    @State private var showingFullMap = false
    @State private var expandedLegs: Set<UUID> = []

    // Map camera; `.automatic` frames the whole route. Tracked so the zoom
    // buttons scale around wherever the traveler has panned to.
    @State private var camera: MapCameraPosition = .automatic
    @State private var currentCamera: MapCamera?

    // Draggable detail sheet: which detent it rests at, plus the live drag amount.
    @State private var sheetDetent: SheetDetent = .medium
    @GestureState private var sheetDrag: CGFloat = 0
    @Namespace private var pillNamespace

    /// How tall the detail sheet rests. `minimized` collapses it to a floating
    /// pill; the rest is exposed, fully-interactive map.
    private enum SheetDetent: CaseIterable {
        case minimized, medium, large
        func height(in total: CGFloat) -> CGFloat {
            switch self {
            case .minimized: return 88       // just the floating pill
            case .medium:    return total * 0.5
            case .large:     return total * 0.92
            }
        }
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                mapBackground
                mapTopControls
                detailSheet(height: proxy.size.height)
            }
        }
        // The title lives in the sheet's pill; keep the bar minimal so the map
        // reads full-bleed behind the back button and menu.
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarMenu }
        .sheet(isPresented: $showingEdit) { AddEditTripView(trip: trip) }
        .sheet(isPresented: $showingShare) { ShareTripSheet(trip: trip) }
        .sheet(isPresented: $showingParticipants) { TripParticipantsView(trip: trip) }
        .confirmationDialog("Leave this trip?", isPresented: $showingLeaveConfirm,
                            titleVisibility: .visible) {
            Button("Leave", role: .destructive) { Task { await leaveTrip() } }
        } message: {
            Text("It stays on \(trip.ownerParticipant?.shortName ?? "the owner")'s device. You can be invited again later.")
        }
        .alert("Couldn't leave the trip",
               isPresented: .init(get: { leaveError != nil },
                                  set: { if !$0 { leaveError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(leaveError ?? "")
        }
        .fullScreenCover(isPresented: $showingFullMap) {
            FullMapView(trips: [trip], title: navigationTitle)
        }
        .confirmationDialog("Delete this trip?", isPresented: $showingDeleteConfirm,
                            titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                // Note the CloudKit records first — once the objects are gone
                // there's nothing left to work out what to delete on the server.
                sync.willDelete(trip)
                context.delete(trip)
                try? context.save()
                dismiss()
            }
        }
        .refreshable {
            if let seg = primaryFlightSegment { await tracker.refresh(seg, in: context) }
            // Also advance the travelled track while a flight is in the air.
            await RouteRefresher.refresh(trip.displaySegments, in: context, tracker: tracker)
        }
        .onAppear(perform: expandKeyLegs)
        .task { await backfillTimeZones() }
        // Adding a stop re-plans the route, and the new one is often outside the
        // old frame — a stop added mid-drive reads as nothing having happened if
        // the map keeps its previous camera. Re-fit whenever the route changes,
        // from this page's own rail or from the Edit Trip sheet.
        .onChange(of: routePlaces) { _, _ in
            withAnimation(.smooth(duration: 0.45)) { camera = .automatic }
        }
    }

    /// Stop participating in a trip someone shared with us. The trip only leaves
    /// this device once CloudKit confirms it, so a failure here doesn't lose the
    /// copy we can still read.
    private func leaveTrip() async {
        do {
            try await ShareManager().leave(trip, in: context)
            dismiss()
        } catch {
            leaveError = error.localizedDescription
        }
    }

    /// Every place the trip passes through, in order: each leg's origin, its
    /// stops, its destination. Changes whenever a stop or leg is added, edited,
    /// reordered, or removed.
    private var routePlaces: [Place] {
        trip.displaySegments.flatMap(\.routePlaces)
    }

    /// The menu is built from what this person may actually do. A view-only
    /// guest is offered neither Edit nor Delete — only the way out.
    private var toolbarMenu: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                // Sharing needs the server for every step — creating the share,
                // sending the invite, changing access. Without an iCloud account
                // none of it can run, so the menu doesn't offer it at all.
                if trip.isOwnedByMe && sync.isCloudAvailable {
                    Button { showingShare = true } label: {
                        Label(trip.isShared ? "Invite More People" : "Share Trip",
                              systemImage: "person.badge.plus")
                    }
                    if trip.isShared {
                        Button { showingParticipants = true } label: {
                            Label("Manage People", systemImage: "person.2.fill")
                        }
                    }
                    Divider()
                }
                if trip.canEdit {
                    Button { showingEdit = true } label: { Label("Edit", systemImage: "pencil") }
                }
                if trip.isOwnedByMe {
                    Button(role: .destructive) { showingDeleteConfirm = true } label: {
                        Label("Delete", systemImage: "trash")
                    }
                } else {
                    Button(role: .destructive) { showingLeaveConfirm = true } label: {
                        Label("Leave Trip", systemImage: "person.fill.xmark")
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .padding(8)
                    .glassEffect(.regular, in: .circle)
            }
        }
    }

    // MARK: Full-bleed interactive map

    /// The trip's route as a full-bleed map behind the sheet. Everything above the
    /// sheet is unobstructed, so its routes and pins stay pannable and zoomable.
    private var mapBackground: some View {
        map.ignoresSafeArea()
    }

    /// Casing-backed, gradient-tinted route lines per leg, a neutral start dot, and
    /// a custom mode pin at each destination — the same language as the trip map on
    /// the Upcoming / Past tabs. `.automatic` frames the whole route.
    private var map: some View {
        Map(position: $camera) {
            if let first = trip.displaySegments.first {
                Annotation(first.origin.displayName, coordinate: first.origin.coordinate) {
                    Circle()
                        .fill(.gray.gradient)
                        .frame(width: 15, height: 15)
                        .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                        .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
                }
                .annotationTitles(.hidden)
            }
            ForEach(trip.displaySegments) { segment in
                // Road trips draw the actual roads, flights their flown track —
                // and an airborne flight carries the live aircraft on the line.
                SegmentRouteContent(segment: segment,
                                    live: statusRecords.liveRecord(for: segment))
                ForEach(segment.stops) { stop in
                    Annotation(stop.place.displayName, coordinate: stop.place.coordinate) {
                        Image(systemName: stop.category.symbol)
                            .font(.system(size: 10, weight: .black))
                            .foregroundStyle(.white)
                            .frame(width: 22, height: 22)
                            .background(stop.category.tint.gradient, in: .circle)
                            .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                            .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
                    }
                    .annotationTitles(.hidden)
                }
                Annotation(segment.destination.displayName, coordinate: segment.destination.coordinate) {
                    Image(systemName: segment.type.symbol)
                        .font(.system(size: 13, weight: .black))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(segment.type.gradient, in: .circle)
                        .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                        .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll))
        .mapControls {
            MapCompass()
            MapScaleView()
        }
        .onMapCameraChange(frequency: .continuous) { context in
            currentCamera = context.camera
        }
        // Fill in (or refresh) the real path for each leg — driving directions for
        // road trips, the flown track for flights. Keyed on the routed legs'
        // geometry so it re-runs when a stop is added, moved, or removed.
        .task(id: routeGeometrySignature) {
            await RouteRefresher.refresh(trip.displaySegments, in: context, tracker: tracker)
        }
    }

    /// Fingerprint of every routed leg's geometry, so the route refresh re-runs
    /// only when a road or flight leg's origin, stops, or destination change.
    private var routeGeometrySignature: String {
        trip.displaySegments
            .filter { $0.type == .roadTrip || $0.type == .flight }
            .map(\.geometrySignature)
            .joined(separator: "~")
    }

    /// Floating controls above the map, kept out of the map's ignored safe area so
    /// they clear the navigation bar: full-screen expand and a +/− zoom stepper.
    private var mapTopControls: some View {
        HStack {
            Spacer(minLength: 0)
            VStack(spacing: 10) {
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
            }
        }
        .padding(.horizontal)
        .padding(.top, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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

    /// Scale the camera distance around its current center, keeping heading/pitch.
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

    // MARK: Draggable detail sheet

    /// The draggable detail sheet pinned to the bottom. Slide it down to minimize
    /// it to a floating pill (tap or swipe the pill up to bring the details back).
    private func detailSheet(height: CGFloat) -> some View {
        let dragging = sheetDrag != 0
        let resting = sheetDetent.height(in: height)
        let live = min(max(resting - sheetDrag, SheetDetent.minimized.height(in: height)),
                       SheetDetent.large.height(in: height))
        return ZStack(alignment: .bottom) {
            if sheetDetent == .minimized && !dragging {
                minimizedPill
                    .transition(.opacity)
            } else {
                expandedSheet(sheetHeight: live, containerHeight: height)
                    .transition(.opacity)
            }
        }
        .animation(.snappy(duration: 0.32), value: sheetDetent)
    }

    /// The full glass sheet: grab handle, a pinned header (the title pill, plus the
    /// live status while underway), then the scrolling details.
    private func expandedSheet(sheetHeight: CGFloat, containerHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            // Draggable header: the grab handle, the title row, and — while
            // underway — the live card. The resize gesture covers this whole
            // region, so you can grab the sheet anywhere up here (including the
            // active-leg card), not just the thin handle. The scrolling details
            // below keep their own scroll gesture.
            VStack(spacing: 12) {
                grabHandleBar

                HStack(spacing: 10) {
                    titlePill(minimized: false)
                    Spacer(minLength: 0)
                    TripSyncBadge(state: trip.syncState.resolved(cloudAvailable: sync.isCloudAvailable),
                                  size: 13)
                    activeShortcut
                    shareControl
                    statusPill
                }
                accessBanner
                // The one thing that matters mid-trip, pinned above the scroll.
                if isUnderway {
                    TripStatusCardView(trip: trip)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 12)
            .contentShape(.rect)
            .gesture(sheetDragGesture(height: containerHeight))

            ScrollView {
                VStack(spacing: 16) {
                    // While underway the pinned card already shows the route and
                    // times, so the overview drops to just its extra metrics.
                    TripOverviewCard(trip: trip, compact: isUnderway)

                    if !isUnderway, let urgent = connections.first(where: { $0.risk.isUrgent }) {
                        connectionAlert(urgent)
                    }

                    itinerary

                    if let notes = trip.notes, !notes.isEmpty {
                        notesCard(notes)
                    }
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

    /// The grab strip. A tap toggles medium / large; dragging is handled by the
    /// header's drag gesture, so the whole top region resizes the sheet.
    private var grabHandleBar: some View {
        Capsule()
            .fill(.secondary.opacity(0.5))
            .frame(width: 40, height: 5)
            .padding(.top, 10)
            .padding(.bottom, 2)
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
            .onTapGesture {
                sheetDetent = sheetDetent == .large ? .medium : .large
            }
    }

    /// Resize the sheet from a drag, snapping to the nearest detent on release
    /// (drag all the way down to minimize). Measured in *global* space: the header
    /// slides up under the finger as the sheet grows, and a local measurement would
    /// feed that movement back into the translation — the source of the jitter at
    /// in-between positions.
    private func sheetDragGesture(height: CGFloat) -> some Gesture {
        DragGesture(coordinateSpace: .global)
            .updating($sheetDrag) { value, state, _ in state = value.translation.height }
            .onEnded { value in
                let target = sheetDetent.height(in: height) - value.translation.height
                sheetDetent = SheetDetent.allCases.min {
                    abs($0.height(in: height) - target) < abs($1.height(in: height) - target)
                } ?? .medium
            }
    }

    /// The collapsed sheet: the title pill floating at the bottom. Tap it, or swipe
    /// it up, to bring the details back. It's the same pill as the sheet's header,
    /// so minimizing / restoring morphs between the two positions.
    private var minimizedPill: some View {
        titlePill(minimized: true)
            .padding(.bottom, 10)
            .contentShape(.capsule)
            .onTapGesture { sheetDetent = .medium }
            .gesture(
                DragGesture().onEnded { value in
                    if value.translation.height < -24 { sheetDetent = .medium }
                }
            )
    }

    /// The trip's title as a liquid-glass pill — mode icon, the "Flight" / "Trip" /
    /// "Connection" label, and the route codes. While underway it carries a live
    /// pulse and the current headline instead, so the minimized pill still tells
    /// you what's happening. Shares a matchedGeometry id so it morphs between the
    /// header and the minimized position.
    private func titlePill(minimized: Bool) -> some View {
        let live = liveStatus
        return HStack(spacing: 10) {
            if let live {
                LiveDot(color: live.tint)
                VStack(alignment: .leading, spacing: 1) {
                    Text(live.headline)
                        .font(.subheadline.weight(.bold))
                        .lineLimit(1)
                    Text("\(trip.startPlace.codeLabel) → \(trip.endPlace.codeLabel)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } else {
                Image(systemName: trip.type.symbol)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(trip.type.accent)
                VStack(alignment: .leading, spacing: 1) {
                    Text(navigationTitle)
                        .font(.headline.weight(.heavy))
                        .lineLimit(1)
                    Text("\(trip.startPlace.codeLabel) → \(trip.endPlace.codeLabel)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            if minimized {
                Image(systemName: "chevron.up")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 2)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .glassEffect(.regular, in: .capsule)
        .matchedGeometryEffect(id: "titlePill", in: pillNamespace)
    }

    /// The relative-time / completed pill on the right of the header — hidden while
    /// underway, since the pinned live card already carries a status.
    @ViewBuilder
    private var statusPill: some View {
        if !isUnderway {
            Text(isSettled ? "Completed" : Format.relative(trip.startDate))
                .font(.caption.weight(.semibold))
                .foregroundStyle(isSettled ? .secondary : trip.type.accent)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background((isSettled ? Color.secondary : trip.type.accent).opacity(0.15),
                            in: .capsule)
        }
    }

    /// Whether this trip is effectively over — judged on live records, not just
    /// the planned times, so a leg that landed early reads "Completed" rather
    /// than counting down to a booked arrival that no longer matters.
    private var isSettled: Bool {
        liveStatus == nil
            && TripStatus.effectiveEnd(of: trip, records: statusRecords) < Date()
    }

    /// A right-indented shortcut beside the title bubble for the leg happening now:
    /// driving directions in Apple Maps while on the road, boarding passes in
    /// Wallet while it's a flight. Only shown while that leg is active.
    @ViewBuilder
    private var activeShortcut: some View {
        if let leg = liveStatus?.focusSegment {
            switch leg.type {
            case .roadTrip:
                shortcutButton("arrow.triangle.turn.up.right.diamond.fill", tint: leg.type.accent) {
                    MapsLauncher.openDirections(from: leg.origin, to: leg.destination)
                }
            case .flight:
                shortcutButton("wallet.pass.fill", tint: leg.type.accent) {
                    WalletLauncher.openBoardingPasses()
                }
            default:
                EmptyView()
            }
        }
    }

    // MARK: Sharing

    /// The trip's people, sitting level with the title pill.
    ///
    /// An unshared trip of our own shows an invite button instead — sharing is a
    /// headline feature, and burying it in the overflow menu would mean nobody
    /// finds it. Once shared, the same slot becomes the faces on the trip, which
    /// tap through to manage them.
    @ViewBuilder
    private var shareControl: some View {
        if trip.isShared {
            // Who's on the trip is worth showing even offline — it's cached and
            // still true. Tapping through to manage them isn't, since every
            // action in there needs the server.
            let faces = ParticipantStack(participants: trip.collaborators, size: 30)
                .frame(height: 46)
                .padding(.horizontal, 10)
                .glassEffect(.regular, in: .capsule)

            if sync.isCloudAvailable {
                Button { showingParticipants = true } label: { faces }
                    .buttonStyle(.plain)
            } else {
                faces
            }
        } else if trip.isOwnedByMe && sync.isCloudAvailable {
            // No account means no invite can be sent, so don't offer one —
            // the trip's cloud badge and the Account screen explain why.
            shortcutButton("person.badge.plus", tint: trip.type.accent) {
                showingShare = true
            }
        }
    }

    /// A quiet line explaining a trip we don't fully control, shown instead of
    /// leaving the missing Edit and Add Stop affordances unexplained.
    @ViewBuilder
    private var accessBanner: some View {
        if !trip.isOwnedByMe {
            HStack(spacing: 7) {
                Image(systemName: trip.canEdit ? "person.2.fill" : "lock.fill")
                    .font(.caption2.weight(.bold))
                Text(accessBannerText)
                    .font(.caption)
                    .lineLimit(1)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .glassEffect(.regular, in: .capsule)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var accessBannerText: String {
        let owner = trip.ownerParticipant?.shortName
        let who = owner.map { "Shared with you by \($0)" } ?? "Shared with you"
        return trip.canEdit ? who : "\(who) · View only"
    }

    /// A liquid-glass icon button sized to sit level with the title pill.
    private func shortcutButton(_ icon: String, tint: Color,
                                action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.headline.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 46, height: 46)
                .glassEffect(.regular, in: .circle)
        }
        .buttonStyle(.plain)
    }

    // MARK: Itinerary

    private var itinerary: some View {
        VStack(spacing: 16) {
            if trip.isMultiModal {
                SectionTitle(title: "Itinerary", systemImage: "list.bullet",
                             tint: trip.type.accent)
            }
            ForEach(Array(trip.displaySegments.enumerated()), id: \.element.id) { idx, segment in
                TripLegCard(trip: trip, index: idx, segment: segment,
                            records: statusRecords.filter { $0.segmentID == segment.id },
                            expanded: $expandedLegs)
                    .appear(idx)
                if let pair = trip.connectionPairs.first(where: { $0.inbound.id == segment.id }) {
                    ConnectionCardView(inbound: pair.inbound, outbound: pair.outbound)
                        .appear(idx)
                }
            }
        }
    }

    private func notesCard(_ notes: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle(title: "Notes", systemImage: "note.text", tint: trip.type.accent)
            Text(notes).font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassCard()
        }
    }

    // MARK: Derived state

    private var isUnderway: Bool { liveStatus != nil }

    /// The live reading for this trip, or nil when it isn't happening right now.
    private var liveStatus: TripStatus? {
        TripStatus(trip: trip, records: statusRecords)
    }

    /// Auto-expand the legs most worth seeing on open: the next/active flight, any
    /// flight at risk of being missed, and — for a single-leg trip — its only leg.
    private func expandKeyLegs() {
        if let seg = primaryFlightSegment { expandedLegs.insert(seg.id) }
        for connection in connections where connection.risk.isUrgent {
            expandedLegs.insert(connection.outbound.id)
        }
        if trip.displaySegments.count == 1, let only = trip.displaySegments.first {
            expandedLegs.insert(only.id)
        }
    }

    /// Fill in any airport saved without a timezone so its times show on its own
    /// clock rather than the device's. Idempotent: skips places already resolved.
    private func backfillTimeZones() async {
        var changed = false
        for segment in trip.segments {
            if segment.origin.timeZoneIdentifier == nil {
                segment.origin = await segment.origin.reverseGeocoded()
                changed = changed || segment.origin.timeZoneIdentifier != nil
            }
            if segment.destination.timeZoneIdentifier == nil {
                segment.destination = await segment.destination.reverseGeocoded()
                changed = changed || segment.destination.timeZoneIdentifier != nil
            }
        }
        if changed { try? context.save() }
    }

    /// The flight leg a traveler most likely cares about now: the next unfinished
    /// flight, else the last flight in the trip.
    private var primaryFlightSegment: TripSegment? {
        let flights = trip.displaySegments.filter { $0.type == .flight }
        return flights.first { $0.endDate >= Date() } ?? flights.last
    }

    private var navigationTitle: String {
        guard trip.isMultiModal else { return trip.type.label }
        let allFlights = trip.displaySegments.allSatisfy { $0.type == .flight }
        return trip.isConnecting && allFlights ? "Connection" : "Trip"
    }

    private var connections: [Connection] {
        trip.connectionPairs.map {
            Connection(inbound: $0.inbound, outbound: $0.outbound, records: statusRecords)
        }
    }

    private func connectionAlert(_ connection: Connection) -> some View {
        let risk = connection.risk
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: risk.systemImage).font(.headline).foregroundStyle(risk.color)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(risk.label) at \(connection.airport.displayName)")
                    .font(.subheadline.weight(.semibold))
                Text(connection.advisory)
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(tint: risk.color.opacity(0.3))
    }
}

/// A small breathing dot marking a live reading, sized for the title pill.
private struct LiveDot: View {
    let color: Color
    @State private var expanded = false

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.25))
                .frame(width: 22, height: 22)
                .scaleEffect(expanded ? 1 : 0.5)
                .opacity(expanded ? 0 : 1)
            Circle().fill(color).frame(width: 9, height: 9)
        }
        .frame(width: 22, height: 22)
        .onAppear {
            withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) {
                expanded = true
            }
        }
    }
}

#if DEBUG
private extension View {
    /// The observable services this screen reads. Neither does any work until
    /// asked, so previews stay offline.
    func tripDetailPreviewEnv() -> some View {
        environment(FlightTracker())
            .environment(PreviewData.sync)
    }
}

#Preview("Single") {
    NavigationStack { TripDetailView(trip: .sampleFlight) }
        .modelContainer(PreviewData.container)
        .tripDetailPreviewEnv()
}

#Preview("Multi-modal") {
    NavigationStack { TripDetailView(trip: .sampleMultiModal) }
        .modelContainer(PreviewData.container)
        .tripDetailPreviewEnv()
}

#Preview("Connection") {
    NavigationStack { TripDetailView(trip: .sampleConnection) }
        .modelContainer(PreviewData.container)
        .tripDetailPreviewEnv()
}
#endif
