//
//  AddTripFlowView.swift
//  Runnit iOS
//
//  A conversational, one-question-at-a-time flow for adding a trip. Replaces
//  the single static form: each screen asks one friendly question, adapts to
//  the chosen mode, and ends with a review before saving.
//

import SwiftUI
import SwiftData

// MARK: - Draft

private struct TripDraft {
    var type: TripType = .flight
    var origin: Place?
    var destination: Place?
    var departureDate = Date()
    var hasArrival = false
    var arrivalDate = Date().addingTimeInterval(3 * 3600)
    var operatorName = ""
    var vehicleNumber = ""
    var boardingPoint = ""
    var seat = ""
    var confirmation = ""
    var title = ""
    var notes = ""
}

private enum WizardStep: Hashable {
    case type, origin, destination, when, carrier, number, details, name, notes, review
}

// MARK: - Flow

struct AddTripFlowView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var draft: TripDraft = {
        #if DEBUG
        if ProcessInfo.processInfo.environment["ADD_DEMO_ROADTRIP"] == "1" {
            var d = TripDraft()
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
        return TripDraft()
    }()
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

    @AppStorage(PrefKey.appearance) private var appearanceRaw = AppAppearance.dark.rawValue

    private var steps: [WizardStep] {
        var s: [WizardStep] = [.type, .origin, .destination, .when]
        s += draft.type.isScheduledTransit ? [.carrier, .number, .details] : [.name]
        s += [.notes, .review]
        return s
    }

    private var step: WizardStep { steps[min(index, steps.count - 1)] }
    private var accent: Color { draft.type.accent }
    private var isLast: Bool { step == .review }

    var body: some View {
        ZStack {
            AppBackground(accent: accent, secondary: .purple)

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
        HStack(spacing: 12) {
            if index > 0 {
                Button { back() } label: {
                    Image(systemName: "chevron.left")
                        .font(.headline)
                        .padding(10)
                        .glassEffect(.regular, in: .circle)
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }

            ProgressView(value: Double(index + 1), total: Double(steps.count))
                .tint(accent)

            Button("Cancel") { dismiss() }
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 12)
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
        .id(step)
        .transition(.asymmetric(
            insertion: .move(edge: goingForward ? .trailing : .leading).combined(with: .opacity),
            removal: .move(edge: goingForward ? .leading : .trailing).combined(with: .opacity)
        ))
    }

    private var footer: some View {
        Button {
            isLast ? save() : next()
        } label: {
            Text(isLast ? "Save trip" : "Continue")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.glassProminent)
        .tint(accent)
        .disabled(!canAdvance || isSaving)
        .padding(.bottom, 8)
    }

    // MARK: Copy

    private var headline: String {
        switch step {
        case .type:        return "Let's plan a trip"
        case .origin:      return "Where are you starting?"
        case .destination: return "And where to?"
        case .when:        return "When do you leave?"
        case .carrier:     return draft.type == .flight ? "Which airline?" : "Which operator?"
        case .number:      return draft.type == .flight ? "Flight number?" : "Train number?"
        case .details:     return "Any details to add?"
        case .name:        return "Give it a name?"
        case .notes:       return "Anything to remember?"
        case .review:      return "Look good?"
        }
    }

    private var subhead: String? {
        switch step {
        case .type:        return "What kind of journey is this?"
        case .origin:      return "Search an airport, station, city, or address."
        case .destination: return "Your final stop."
        case .when:        return "Pick your departure — add an arrival if you know it."
        case .carrier:     return "Optional, but nice to have."
        case .number:      return "So we can find it later. Optional."
        case .details:     return draft.type == .flight ? "Gate, seat, confirmation…" : "Platform, seat, confirmation…"
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
        case .origin:      placeInput($draft.origin, icon: "location.circle.fill")
        case .destination: placeInput($draft.destination, icon: "mappin.circle.fill")
        case .when:        whenInput
        case .carrier:     bigField($draft.operatorName, placeholder: draft.type == .flight ? "e.g. United" : "e.g. Amtrak")
        case .number:      bigField($draft.vehicleNumber, placeholder: draft.type == .flight ? "e.g. UA 523" : "e.g. NE 178", caps: true)
        case .details:     detailsInput
        case .name:        bigField($draft.title, placeholder: "e.g. Summer Road Trip")
        case .notes:       notesInput
        case .review:      reviewInput
        }
    }

    private var typeInput: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
            ForEach(TripType.allCases) { type in
                Button {
                    draft.type = type
                    next()
                } label: {
                    VStack(spacing: 12) {
                        Image(systemName: type.symbol)
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundStyle(.white)
                        Text(type.label)
                            .font(.headline)
                            .foregroundStyle(.white)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 130)
                    .background(type.gradient, in: .rect(cornerRadius: 24))
                    .overlay {
                        RoundedRectangle(cornerRadius: 24)
                            .strokeBorder(.white.opacity(draft.type == type ? 0.9 : 0), lineWidth: 3)
                    }
                    .shadow(color: type.accent.opacity(0.5), radius: 14, y: 6)
                }
                .buttonStyle(.plain)
            }
        }
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
            DatePicker("Departure", selection: $draft.departureDate)
                .datePickerStyle(.graphical)
                .tint(accent)
                .padding()
                .glassEffect(.regular, in: .rect(cornerRadius: 22))

            if draft.type == .roadTrip {
                roadTripETACard
            } else {
                Toggle("I know my arrival time", isOn: $draft.hasArrival.animation())
                    .padding()
                    .glassEffect(.regular, in: .rect(cornerRadius: 18))
                if draft.hasArrival {
                    DatePicker("Arrival", selection: $draft.arrivalDate, in: draft.departureDate...)
                        .padding()
                        .glassEffect(.regular, in: .rect(cornerRadius: 18))
                }
            }
        }
        .task(id: routeKey) { await estimateDriveIfNeeded() }
        .onChange(of: draft.departureDate) { _, _ in applyRoadTripArrival() }
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
                        Text("Arriving ~ \(Format.dateTime(draft.departureDate.addingTimeInterval(dt)))")
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

    private var notesInput: some View {
        TextField("Notes", text: $draft.notes, axis: .vertical)
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
            reviewRow(icon: draft.type.symbol, title: draft.type.label, tint: accent)
            reviewRow(icon: "location.circle.fill", title: draft.origin?.name ?? "—")
            reviewRow(icon: "mappin.circle.fill", title: draft.destination?.name ?? "—")
            reviewRow(icon: "calendar", title: Format.dateTime(draft.departureDate))
            if draft.hasArrival {
                reviewRow(icon: "calendar.badge.clock", title: Format.dateTime(draft.arrivalDate))
            }
            if draft.type.isScheduledTransit, !draft.vehicleNumber.isEmpty {
                reviewRow(icon: "number", title: draft.vehicleNumber)
            }
            if !draft.title.isEmpty {
                reviewRow(icon: "textformat", title: draft.title)
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
        guard index > 0 else { return }
        goingForward = false
        withAnimation(.snappy) { index -= 1 }
    }

    private func save() {
        guard var origin = draft.origin, var destination = draft.destination else { return }
        isSaving = true
        let d = draft
        Task {
            if origin.isoCountryCode == nil { origin = await origin.reverseGeocoded() }
            if destination.isoCountryCode == nil { destination = await destination.reverseGeocoded() }

            let trip = Trip(
                type: d.type,
                title: d.title.trimmingCharacters(in: .whitespaces),
                origin: origin,
                destination: destination,
                departureDate: d.departureDate,
                arrivalDate: d.hasArrival ? d.arrivalDate : nil,
                operatorName: nilIfEmpty(d.operatorName),
                vehicleNumber: nilIfEmpty(d.vehicleNumber),
                boardingPoint: nilIfEmpty(d.boardingPoint),
                seat: nilIfEmpty(d.seat),
                confirmation: nilIfEmpty(d.confirmation),
                notes: nilIfEmpty(d.notes)
            )
            context.insert(trip)
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

#if DEBUG
#Preview {
    AddTripFlowView()
        .modelContainer(PreviewData.container)
}
#endif
