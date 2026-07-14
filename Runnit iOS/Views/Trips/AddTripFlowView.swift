//
//  AddTripFlowView.swift
//  Runnit iOS
//
//  A conversational, one-question-at-a-time flow for adding a trip. Each screen
//  asks one friendly question and adapts to the chosen mode. Trips can be
//  multi-modal: after each leg, an itinerary step lets you add another leg
//  (chained from the previous destination) or finish and save.
//

import SwiftUI
import SwiftData

// MARK: - Drafts

private enum WizardStep: Hashable {
    // Per-leg questions
    case type, flightLookup, origin, destination, when, carrier, number, details, itinerary
    // Trip-level finish
    case name, notes, review
}

// MARK: - Flow

struct AddTripFlowView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    /// Legs already committed, in order.
    @State private var legs: [LegDraft] = []
    /// The leg currently being entered (not yet committed).
    @State private var draft: LegDraft = {
        #if DEBUG
        if ProcessInfo.processInfo.environment["ADD_DEMO_ROADTRIP"] == "1" {
            var d = LegDraft()
            d.type = .roadTrip
            d.origin = Place(name: "San Francisco", subtitle: "California",
                             latitude: 37.7749, longitude: -122.4194,
                             isoCountryCode: "US", country: "United States", locality: "San Francisco")
            d.destination = Place(name: "Big Sur", subtitle: "California",
                                  latitude: 36.2704, longitude: -121.8081,
                                  isoCountryCode: "US", country: "United States", locality: "Big Sur")
            return d
        }
        #endif
        return LegDraft()
    }()

    @State private var title = ""
    @State private var notes = ""

    /// false → building legs; true → entering trip-level details (name/notes/review).
    @State private var finishing = false
    @State private var index: Int = {
        #if DEBUG
        if let raw = ProcessInfo.processInfo.environment["ADD_STEP"], let n = Int(raw) { return n }
        #endif
        return 0
    }()
    @State private var goingForward = true
    @State private var isSaving = false
    @State private var driveTime: TimeInterval?
    @State private var estimating = false

    // Flight auto-fill
    @Environment(FlightTracker.self) private var tracker
    @State private var lookupNumber = ""
    @State private var lookingUp = false
    @State private var lookupMessage: String?
    @State private var lookupApplied = false

    @AppStorage(PrefKey.appearance) private var appearanceRaw = AppAppearance.dark.rawValue

    private var steps: [WizardStep] {
        if finishing {
            return [.name, .notes, .review]
        }
        var s: [WizardStep] = [.type]
        // Flights start with a number+date lookup that can auto-fill the rest;
        // the manual steps stay available behind "Enter details manually".
        if draft.type == .flight { s += [.flightLookup] }
        s += [.origin, .destination, .when]
        s += draft.type.isScheduledTransit ? [.carrier, .number, .details] : []
        s += [.itinerary]
        return s
    }

    private var step: WizardStep { steps[min(index, steps.count - 1)] }
    /// A single, consistent accent for the whole modal (matches the app tint).
    /// Mode colors appear only in the small mode icons, keeping this clean.
    private let accent: Color = .cyan
    private var isReview: Bool { step == .review }
    private var canGoBack: Bool { index > 0 || finishing || !legs.isEmpty }

    /// The full itinerary so far, including the in-progress leg.
    private var itinerary: [LegDraft] { legs + [draft] }

    /// A comfortable default gap when chaining a new leg onto the last one — well
    /// clear of the 45 minutes a connection needs, and easy to shorten.
    private static let defaultLayover: TimeInterval = 2 * 3600

    var body: some View {
        ZStack {
            PlanBackground()

            VStack(spacing: 0) {
                topBar
                stepContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                footer
            }
            .padding(.horizontal)
            .overlay {
                if isSaving { ProgressView().controlSize(.large).tint(.white) }
            }
        }
        .preferredColorScheme((AppAppearance(rawValue: appearanceRaw) ?? .dark).colorScheme)
        .tint(accent)
    }

    // MARK: Chrome

    private var topBar: some View {
        VStack(spacing: 12) {
            HStack {
                if canGoBack {
                    Button { back() } label: {
                        Image(systemName: "chevron.left")
                            .font(.headline)
                            .padding(10)
                            .glassEffect(.regular, in: .circle)
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            progressBar
        }
        .padding(.top, 12)
    }

    /// A slim, inset progress capsule on its own row — clears the sheet's
    /// rounded corners and never collides with the Cancel button.
    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(accent.gradient)
                    .frame(width: max(6, geo.size.width * progressFraction))
            }
        }
        .frame(height: 5)
        .animation(.snappy(duration: 0.3), value: progressFraction)
        .accessibilityLabel("Step \(index + 1) of \(steps.count)")
    }

    private var progressFraction: Double {
        guard steps.count > 1 else { return 1 }
        return Double(index + 1) / Double(steps.count)
    }

    @ViewBuilder
    private var stepContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(headline)
                        .font(.largeTitle.weight(.bold))
                    if let sub = subhead {
                        Text(sub)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 24)

                input
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 24)
        }
        .id(finishing ? "finish-\(step)" : "leg\(legs.count)-\(step)")
        .transition(.asymmetric(
            insertion: .move(edge: goingForward ? .trailing : .leading).combined(with: .opacity),
            removal: .move(edge: goingForward ? .leading : .trailing).combined(with: .opacity)
        ))
    }

    @ViewBuilder
    private var footer: some View {
        // The itinerary and flight-lookup steps have their own action buttons;
        // every other step gets a standard Continue / Save.
        if step != .itinerary && step != .flightLookup {
            Button {
                isReview ? save() : next()
            } label: {
                Text(isReview ? "Save trip" : "Continue")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.glassProminent)
            .tint(accent)
            .disabled(!canAdvance || isSaving)
            .padding(.bottom, 8)
        }
    }

    // MARK: Copy

    private var legOrdinal: String {
        let n = legs.count + 1
        switch n {
        case 1: return "first"
        case 2: return "second"
        case 3: return "third"
        case 4: return "fourth"
        default: return "\(n)th"
        }
    }

    private var headline: String {
        switch step {
        case .type:        return legs.isEmpty ? "Plan a new trip" : "Add another leg"
        case .flightLookup: return "What's your flight?"
        case .origin:      return "Where are you starting?"
        case .destination: return "And where to?"
        case .when:        return "When do you leave?"
        case .carrier:     return draft.type == .flight ? "Which airline?" : "Which operator?"
        case .number:      return draft.type == .flight ? "Flight number?" : "Train number?"
        case .details:     return "Any details to add?"
        case .itinerary:   return "Your itinerary"
        case .name:        return "Give it a name?"
        case .notes:       return "Anything to remember?"
        case .review:      return "Look good?"
        }
    }

    private var subhead: String? {
        switch step {
        case .type:        return legs.isEmpty ? "Start with your first leg — how are you travelling?" : "How are you travelling this leg?"
        case .flightLookup: return "Enter your flight number and date — we'll fill in the rest."
        case .origin:      return legs.isEmpty ? "Search an airport, station, city, or address." : "Starts where your last leg ended — change it if you like."
        case .destination: return "Where this leg ends."
        case .when:        return "Pick your departure — add an arrival if you know it."
        case .carrier:     return "Optional, but nice to have."
        case .number:      return "So we can find it later. Optional."
        case .details:     return draft.type == .flight ? "Gate, seat, confirmation…" : "Platform, seat, confirmation…"
        case .itinerary:   return "Add another leg, or continue to finish."
        case .name:        return "Optional — a fun title for this trip."
        case .notes:       return "Optional notes, packing reminders, anything."
        case .review:      return nil
        }
    }

    // MARK: Inputs

    @ViewBuilder
    private var input: some View {
        switch step {
        case .type:        typeInput
        case .flightLookup: flightLookupInput
        case .origin:      placeInput($draft.origin, icon: "location.circle.fill")
        case .destination: placeInput($draft.destination, icon: "mappin.circle.fill")
        case .when:        whenInput
        case .carrier:     bigField($draft.operatorName, placeholder: draft.type == .flight ? "e.g. United" : "e.g. Amtrak")
        case .number:      bigField($draft.vehicleNumber, placeholder: draft.type == .flight ? "e.g. UA 523" : "e.g. NE 178", caps: true)
        case .details:     detailsInput
        case .itinerary:   itineraryInput
        case .name:        bigField($title, placeholder: "e.g. Summer Road Trip")
        case .notes:       notesInput
        case .review:      reviewInput
        }
    }

    private var typeInput: some View {
        VStack(spacing: 12) {
            ForEach(TripType.allCases) { type in
                Button {
                    draft.type = type
                    next()
                } label: {
                    HStack(spacing: 16) {
                        modeIcon(type, size: 52)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(type.label).font(.headline)
                            Text(type.blurb).font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: draft.type == type ? "checkmark.circle.fill" : "chevron.right")
                            .font(draft.type == type ? .title3 : .subheadline.weight(.semibold))
                            .foregroundStyle(draft.type == type ? AnyShapeStyle(accent) : AnyShapeStyle(.tertiary))
                    }
                    .padding(14)
                    .glassEffect(.regular, in: .rect(cornerRadius: 20))
                    .overlay {
                        RoundedRectangle(cornerRadius: 20)
                            .strokeBorder(accent.opacity(draft.type == type ? 0.7 : 0), lineWidth: 1.5)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// A mode's SF Symbol in a soft, mode-tinted rounded square — the one spot
    /// where mode color appears in this otherwise-neutral flow.
    private func modeIcon(_ type: TripType, size: CGFloat) -> some View {
        Image(systemName: type.symbol)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(type.accent)
            .frame(width: size, height: size)
            .background(type.accent.opacity(0.16), in: .rect(cornerRadius: size * 0.28))
    }

    private func placeInput(_ binding: Binding<Place?>, icon: String) -> some View {
        VStack(spacing: 16) {
            LocationSearchField(title: "", systemImage: icon, place: binding)
                .padding()
                .glassEffect(.regular, in: .rect(cornerRadius: 20))
            if let place = binding.wrappedValue {
                selectedPlaceCard(place, icon: icon)
            }
        }
    }

    private func selectedPlaceCard(_ place: Place, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(place.name).font(.headline)
                if !place.subtitle.isEmpty {
                    Text(place.subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(accent.opacity(0.15), in: .rect(cornerRadius: 18))
    }

    private var whenInput: some View {
        VStack(spacing: 16) {
            // Picked on the departure airport's clock, not the phone's.
            DatePicker("Departure", selection: $draft.departureDate)
                .datePickerStyle(.graphical)
                .tint(accent)
                .environment(\.calendar, calendar(in: draft.origin?.timeZone))
                .padding()
                .glassEffect(.regular, in: .rect(cornerRadius: 22))
            if let zone = draft.origin?.timeZone,
               let abbreviation = Format.zone(zone, at: draft.departureDate) {
                Text("Times in \(abbreviation) — local at \(draft.origin?.displayName ?? "departure")")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if draft.type == .roadTrip {
                roadTripETACard
            } else {
                Toggle("I know my arrival time", isOn: $draft.hasArrival.animation())
                    .padding()
                    .glassEffect(.regular, in: .rect(cornerRadius: 18))
                if draft.hasArrival {
                    DatePicker("Arrival", selection: $draft.arrivalDate, in: draft.departureDate...)
                        .environment(\.calendar, calendar(in: draft.destination?.timeZone))
                        .padding()
                        .glassEffect(.regular, in: .rect(cornerRadius: 18))
                }
            }
        }
        .task(id: routeKey) { await estimateDriveIfNeeded() }
        .onChange(of: draft.departureDate) { _, _ in applyRoadTripArrival() }
    }

    /// A calendar pinned to `zone`, so DatePicker reads and writes that clock.
    private func calendar(in zone: TimeZone?) -> Calendar {
        var cal = Calendar.current
        if let zone { cal.timeZone = zone }
        return cal
    }

    private var routeKey: String {
        "\(draft.origin?.latitude ?? 0),\(draft.origin?.longitude ?? 0)|\(draft.destination?.latitude ?? 0),\(draft.destination?.longitude ?? 0)"
    }

    @ViewBuilder
    private var roadTripETACard: some View {
        VStack {
            if estimating {
                HStack(spacing: 10) {
                    ProgressView().tint(accent)
                    Text("Estimating drive time…").foregroundStyle(.secondary)
                    Spacer()
                }
            } else if let dt = driveTime {
                HStack(spacing: 12) {
                    Image(systemName: "car.fill").font(.title3).foregroundStyle(accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(Format.duration(dt)) drive").font(.headline)
                        Text("Arriving ~ \(Format.dateTime(draft.departureDate.addingTimeInterval(dt), in: draft.destination?.timeZone))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("via Apple Maps").font(.caption2).foregroundStyle(.tertiary)
                }
            } else {
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                    Text("Couldn't estimate a drive route — you can still continue.")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
    }

    private func estimateDriveIfNeeded() async {
        guard draft.type == .roadTrip, let o = draft.origin, let d = draft.destination else { return }
        estimating = true
        driveTime = nil
        driveTime = await RouteEstimator.drivingTime(from: o, to: d)
        estimating = false
        applyRoadTripArrival()
    }

    private func applyRoadTripArrival() {
        guard draft.type == .roadTrip, let dt = driveTime else { return }
        draft.hasArrival = true
        draft.arrivalDate = draft.departureDate.addingTimeInterval(dt)
    }

    private var detailsInput: some View {
        VStack(spacing: 14) {
            bigField($draft.boardingPoint, placeholder: draft.type.boardingLabel)
            bigField($draft.seat, placeholder: "Seat")
            bigField($draft.confirmation, placeholder: "Confirmation #", caps: true)
        }
    }

    // MARK: Flight lookup step

    @ViewBuilder
    private var flightLookupInput: some View {
        VStack(spacing: 16) {
            bigField($lookupNumber, placeholder: "Flight number (e.g. AA 100)", caps: true)

            DatePicker("Travel date", selection: $draft.departureDate, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .tint(accent)
                .padding()
                .glassEffect(.regular, in: .rect(cornerRadius: 22))

            if lookingUp {
                HStack(spacing: 10) {
                    ProgressView().tint(accent)
                    Text("Looking up your flight…").foregroundStyle(.secondary)
                    Spacer()
                }
                .padding()
                .glassEffect(.regular, in: .rect(cornerRadius: 18))
            } else if lookupApplied {
                lookupResultCard
                Button { goToItinerary() } label: {
                    Text("Continue").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent).tint(accent)
            } else {
                Button { Task { await runWizardLookup() } } label: {
                    Label("Look up flight", systemImage: "sparkle.magnifyingglass")
                        .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent).tint(accent)
                .disabled(lookupNumber.trimmingCharacters(in: .whitespaces).isEmpty)

                if let msg = lookupMessage {
                    Text(msg).font(.callout).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Button { next() } label: {
                Text(lookupApplied ? "Edit details manually" : "Enter details manually")
                    .font(.subheadline.weight(.medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .padding(.top, 4)
        }
    }

    private var lookupResultCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Flight found", systemImage: "checkmark.seal.fill")
                .font(.headline).foregroundStyle(.green)
            if let o = draft.origin, let d = draft.destination {
                Text("\(o.displayName) → \(d.displayName)")
                    .font(.subheadline.weight(.semibold))
            }
            if !draft.operatorName.isEmpty {
                Text([draft.operatorName, draft.vehicleNumber].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
            }
            // On the departure airport's clock — the time printed on the ticket.
            Text("Departs \(Format.dateTime(draft.departureDate, in: draft.origin?.timeZone))")
                .font(.caption).foregroundStyle(.secondary)
            if let shift = Format.zoneShift(
                from: draft.origin?.timeZone, to: draft.destination?.timeZone,
                departing: draft.departureDate,
                arriving: draft.hasArrival ? draft.arrivalDate : draft.departureDate
            ) {
                Text(shift).font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(accent.opacity(0.14), in: .rect(cornerRadius: 18))
    }

    private func runWizardLookup() async {
        lookingUp = true
        lookupMessage = nil
        let outcome = await FlightAutofill.run(flightNumber: lookupNumber, date: draft.departureDate, tracker: tracker)
        lookingUp = false

        guard case .filled(let f) = outcome else {
            lookupMessage = outcome.message
            return
        }
        if let o = f.origin { draft.origin = o }
        if let d = f.destination { draft.destination = d }
        if !f.airline.isEmpty { draft.operatorName = f.airline }
        draft.vehicleNumber = f.flightNumber.isEmpty ? lookupNumber : f.flightNumber
        if let dep = f.departure { draft.departureDate = dep }
        if let arr = f.arrival { draft.hasArrival = true; draft.arrivalDate = arr }

        if draft.origin != nil, draft.destination != nil {
            lookupApplied = true
        } else {
            lookupMessage = "Found the flight, but couldn't place the airports on the map. Continue manually to set them."
        }
    }

    private func goToItinerary() {
        goingForward = true
        withAnimation(.snappy) { index = steps.count - 1 }   // itinerary is the last step
    }

    private func resetLookupState() {
        lookupNumber = ""
        lookupMessage = nil
        lookupApplied = false
        lookingUp = false
    }

    // MARK: Itinerary step

    private var itineraryInput: some View {
        VStack(spacing: 16) {
            VStack(spacing: 10) {
                ForEach(Array(itinerary.enumerated()), id: \.element.id) { idx, leg in
                    legRow(index: idx, leg: leg)
                    // Two flights meeting at one airport aren't two separate legs to
                    // the traveler — they're a connection, with a layover to judge.
                    if let connection = itinerary.connection(after: leg) {
                        ConnectionStrip(connection: connection)
                            .padding(.leading, 6)
                    }
                }
            }
            .padding()
            .glassEffect(.regular, in: .rect(cornerRadius: 22))

            Button {
                addAnotherLeg()
            } label: {
                Label("Add another leg", systemImage: "plus.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.glass)
            .tint(accent)

            Button {
                finishLegs()
            } label: {
                Text(itinerary.count > 1 ? "Continue" : "That's the whole trip")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.glassProminent)
            .tint(accent)
        }
    }

    private func legRow(index: Int, leg: LegDraft) -> some View {
        HStack(spacing: 14) {
            modeIcon(leg.type, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(leg.type.label) · \(Format.date(leg.departureDate, in: leg.origin?.timeZone))")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("\(leg.origin?.displayName ?? "—") → \(leg.destination?.displayName ?? "—")")
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer()
            Text("Leg \(index + 1)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private var notesInput: some View {
        TextField("Notes", text: $notes, axis: .vertical)
            .lineLimit(4...8)
            .padding()
            .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }

    private func bigField(_ binding: Binding<String>, placeholder: String, caps: Bool = false) -> some View {
        TextField(placeholder, text: binding)
            .font(.title3)
            .textInputAutocapitalization(caps ? .characters : .sentences)
            .padding()
            .glassEffect(.regular, in: .rect(cornerRadius: 18))
    }

    private var reviewInput: some View {
        VStack(spacing: 14) {
            ForEach(Array(legs.enumerated()), id: \.element.id) { idx, leg in
                legRow(index: idx, leg: leg)
                if let connection = legs.connection(after: leg) {
                    ConnectionStrip(connection: connection)
                        .padding(.leading, 6)
                }
                if idx < legs.count - 1 { Divider() }
            }
            if !title.isEmpty {
                Divider()
                reviewRow(icon: "textformat", title: title)
            }
        }
        .padding()
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
    }

    private func reviewRow(icon: String, title: String, tint: Color = .secondary) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(tint).frame(width: 26)
            Text(title).font(.body.weight(.medium))
            Spacer()
        }
    }

    // MARK: Navigation

    private var canAdvance: Bool {
        switch step {
        case .origin:      return draft.origin != nil
        case .destination: return draft.destination != nil
        default:           return true
        }
    }

    private func next() {
        guard canAdvance, index < steps.count - 1 else { return }
        goingForward = true
        withAnimation(.snappy) { index += 1 }
    }

    private func back() {
        goingForward = false
        if index > 0 {
            withAnimation(.snappy) { index -= 1 }
            return
        }
        // index == 0: step back across phase / leg boundaries.
        if finishing {
            finishing = false
            let restored = legs.popLast()
            withAnimation(.snappy) {
                if let restored { draft = restored }
                index = max(steps.count - 1, 0)   // itinerary of the last leg
            }
            return
        }
        if let restored = legs.popLast() {
            withAnimation(.snappy) {
                draft = restored
                index = max(steps.count - 1, 0)   // that leg's itinerary
            }
        }
    }

    /// Commit the current leg, reset the draft (chained from its destination),
    /// and loop back to the mode question for a new leg.
    private func addAnotherLeg() {
        legs.append(draft)
        var nextLeg = LegDraft()
        nextLeg.type = draft.type
        nextLeg.origin = draft.destination
        // Start the next leg after the last one actually ends, plus a workable gap
        // — departing at the exact moment you land is a connection you'd miss.
        let previousEnd = draft.hasArrival ? draft.arrivalDate : draft.departureDate
        nextLeg.departureDate = previousEnd.addingTimeInterval(Self.defaultLayover)
        draft = nextLeg
        driveTime = nil
        resetLookupState()
        goingForward = true
        withAnimation(.snappy) { index = 0 }
    }

    /// Commit the current leg and move to the trip-level finishing steps.
    private func finishLegs() {
        legs.append(draft)
        finishing = true
        goingForward = true
        withAnimation(.snappy) { index = 0 }
    }
}

// MARK: - Save

extension AddTripFlowView {
    private func save() {
        guard !legs.isEmpty else { return }
        isSaving = true
        let capturedLegs = legs
        let tripTitle = title.trimmingCharacters(in: .whitespaces)
        let tripNotes = nilIfEmpty(notes)
        Task {
            var segments: [TripSegment] = []
            for (i, leg) in capturedLegs.enumerated() {
                guard var origin = leg.origin, var destination = leg.destination else { continue }
                if origin.isoCountryCode == nil { origin = await origin.reverseGeocoded() }
                if destination.isoCountryCode == nil { destination = await destination.reverseGeocoded() }
                segments.append(TripSegment(
                    type: leg.type,
                    origin: origin,
                    destination: destination,
                    departureDate: leg.departureDate,
                    arrivalDate: leg.hasArrival ? leg.arrivalDate : nil,
                    operatorName: nilIfEmpty(leg.operatorName),
                    vehicleNumber: nilIfEmpty(leg.vehicleNumber),
                    boardingPoint: nilIfEmpty(leg.boardingPoint),
                    seat: nilIfEmpty(leg.seat),
                    confirmation: nilIfEmpty(leg.confirmation),
                    order: i
                ))
            }
            guard !segments.isEmpty else { isSaving = false; return }

            let trip = Trip.make(title: tripTitle, notes: tripNotes, segments: segments)
            context.insert(trip)
            for segment in segments { context.insert(segment) }
            try? context.save()
            isSaving = false
            dismiss()
        }
    }

    private func nilIfEmpty(_ s: String) -> String? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}

/// A calm, near-neutral background for the add-trip flow: a soft base gradient
/// with a single faint accent glow. Intentionally quieter than `AppBackground`.
/// Shared by the add-trip wizard and the trip/leg editors.
struct PlanBackground: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        ZStack {
            LinearGradient(
                colors: dark
                    ? [Color(red: 0.08, green: 0.09, blue: 0.11), Color(red: 0.03, green: 0.03, blue: 0.05)]
                    : [Color(red: 0.98, green: 0.98, blue: 1.00), Color(red: 0.92, green: 0.93, blue: 0.96)],
                startPoint: .top, endPoint: .bottom
            )
            Circle()
                .fill(Color.cyan.opacity(dark ? 0.12 : 0.08))
                .frame(width: 360, height: 360)
                .blur(radius: 150)
                .offset(x: 150, y: -320)
        }
        .ignoresSafeArea()
    }
}

#if DEBUG
#Preview {
    AddTripFlowView()
        .modelContainer(PreviewData.container)
        .environment(FlightTracker())
}
#endif
