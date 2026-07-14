//
//  LegEditorView.swift
//  Runnit iOS
//
//  A glass-styled editor for a single leg of a trip, matching the Add Trip
//  flow's look. Includes flight auto-fill (number + date). `LegDraft` is the
//  in-memory value type shared with the trip editor.
//

import SwiftUI

/// An editable, in-memory representation of one trip leg.
struct LegDraft: Identifiable, Hashable {
    var id = UUID()
    /// The stored segment this draft came from, if any — preserved so edits
    /// mutate the same TripSegment (and keep its cached flight status) instead
    /// of replacing it.
    var segmentID: UUID?
    var type: TripType = .flight
    var origin: Place?
    var destination: Place?
    var departureDate = Date()
    var hasArrival = false
    var arrivalDate = Date().addingTimeInterval(3600)
    var operatorName = ""
    var vehicleNumber = ""
    var boardingPoint = ""
    var seat = ""
    var confirmation = ""

    init() {}

    /// Build a draft from a stored segment.
    init(segment: TripSegment) {
        segmentID = segment.id
        type = segment.type
        origin = segment.origin
        destination = segment.destination
        departureDate = segment.departureDate
        if let arrival = segment.arrivalDate {
            hasArrival = true
            arrivalDate = arrival
        }
        operatorName = segment.operatorName ?? ""
        vehicleNumber = segment.vehicleNumber ?? ""
        boardingPoint = segment.boardingPoint ?? ""
        seat = segment.seat ?? ""
        confirmation = segment.confirmation ?? ""
    }

    var isComplete: Bool { origin != nil && destination != nil }

    var routeSummary: String {
        "\(origin?.displayName ?? "—") → \(destination?.displayName ?? "—")"
    }
}

/// A modal editor for a single leg. Calls `onSave` with the result.
struct LegEditorView: View {
    let titleText: String
    @State private var draft: LegDraft
    let onSave: (LegDraft) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(FlightTracker.self) private var tracker
    @AppStorage(PrefKey.appearance) private var appearanceRaw = AppAppearance.dark.rawValue

    @State private var lookupNumber = ""
    @State private var lookingUp = false
    @State private var lookupMessage: String?
    @State private var lookupSucceeded = false

    private let accent: Color = .cyan

    init(titleText: String, draft: LegDraft, onSave: @escaping (LegDraft) -> Void) {
        self.titleText = titleText
        self._draft = State(initialValue: draft)
        self.onSave = onSave
        self._lookupNumber = State(initialValue: draft.vehicleNumber)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                PlanBackground()
                ScrollView {
                    VStack(spacing: 16) {
                        modeCard
                        if draft.type == .flight { flightLookupCard }
                        routeCard
                        whenCard
                        if draft.type.isScheduledTransit { detailsCard }
                    }
                    .padding()
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle(titleText)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onSave(draft)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(!draft.isComplete || lookingUp)
                }
            }
            .tint(accent)
            .preferredColorScheme((AppAppearance(rawValue: appearanceRaw) ?? .dark).colorScheme)
        }
    }

    // MARK: Mode

    private var modeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Mode").font(.headline)
            HStack(spacing: 10) {
                ForEach(TripType.allCases) { type in
                    Button {
                        withAnimation(.snappy) { draft.type = type }
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: type.symbol)
                                .font(.title3)
                                .foregroundStyle(draft.type == type ? AnyShapeStyle(.white) : AnyShapeStyle(type.accent))
                                .frame(width: 48, height: 44)
                                .background(
                                    draft.type == type
                                        ? AnyShapeStyle(type.accent.gradient)
                                        : AnyShapeStyle(type.accent.opacity(0.16)),
                                    in: .rect(cornerRadius: 14)
                                )
                            Text(type.label)
                                .font(.caption2)
                                .foregroundStyle(draft.type == type ? .primary : .secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    // MARK: Route

    private var routeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Route").font(.headline)
            LocationSearchField(title: "From", systemImage: "circle.circle", place: $draft.origin)
            Divider()
            LocationSearchField(title: "To", systemImage: "mappin.circle.fill", place: $draft.destination)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    // MARK: When

    private var whenCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("When").font(.headline)
            DatePicker("Departure", selection: $draft.departureDate)
                .datePickerStyle(.compact)
            Toggle("Add arrival time", isOn: $draft.hasArrival.animation())
            if draft.hasArrival {
                DatePicker("Arrival", selection: $draft.arrivalDate, in: draft.departureDate...)
                    .datePickerStyle(.compact)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    // MARK: Details

    private var detailsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(draft.type == .flight ? "Flight details" : "Train details").font(.headline)
            field(draft.type == .flight ? "Airline" : "Operator", $draft.operatorName)
            field(draft.type.numberLabel, $draft.vehicleNumber, caps: true)
            field(draft.type.boardingLabel, $draft.boardingPoint)
            field("Seat", $draft.seat)
            field("Confirmation #", $draft.confirmation, caps: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private func field(_ placeholder: String, _ binding: Binding<String>, caps: Bool = false) -> some View {
        TextField(placeholder, text: binding)
            .textInputAutocapitalization(caps ? .characters : .sentences)
            .autocorrectionDisabled(caps)
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(.quaternary.opacity(0.6), in: .rect(cornerRadius: 12))
    }

    // MARK: Flight auto-fill

    private var flightLookupCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Auto-fill", systemImage: "sparkle.magnifyingglass").font(.headline)
            Text("Enter a flight number and date to fill in the route, airline, and times. Uses one API lookup.")
                .font(.caption).foregroundStyle(.secondary)

            HStack(spacing: 10) {
                TextField("Flight number (e.g. AA 100)", text: $lookupNumber)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .onSubmit { Task { await runLookup() } }
                    .padding(.horizontal, 12).padding(.vertical, 11)
                    .background(.quaternary.opacity(0.6), in: .rect(cornerRadius: 12))

                if lookingUp {
                    ProgressView().frame(width: 44)
                } else {
                    Button { Task { await runLookup() } } label: {
                        Text("Look up").font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.glassProminent)
                    .tint(accent)
                    .disabled(lookupNumber.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

            DatePicker("Travel date", selection: $draft.departureDate, displayedComponents: .date)
                .datePickerStyle(.compact)

            if let msg = lookupMessage {
                Label(msg, systemImage: lookupSucceeded ? "checkmark.circle.fill" : "info.circle")
                    .font(.caption)
                    .foregroundStyle(lookupSucceeded ? .green : .secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(tint: accent.opacity(0.18))
    }

    private func runLookup() async {
        lookingUp = true
        lookupMessage = nil
        lookupSucceeded = false
        let outcome = await FlightAutofill.run(flightNumber: lookupNumber, date: draft.departureDate, tracker: tracker)
        lookingUp = false

        guard case .filled(let f) = outcome else {
            lookupMessage = outcome.message
            return
        }
        if let o = f.origin { draft.origin = o }
        if let d = f.destination { draft.destination = d }
        if !f.airline.isEmpty { draft.operatorName = f.airline }
        if !f.flightNumber.isEmpty { draft.vehicleNumber = f.flightNumber }
        if let dep = f.departure { draft.departureDate = dep }
        if let arr = f.arrival { draft.hasArrival = true; draft.arrivalDate = arr }
        lookupSucceeded = true
        lookupMessage = "Filled: \(f.routeSummary)"
    }
}

#if DEBUG
#Preview {
    let usage = APIUsageTracker()
    return LegEditorView(titleText: "Edit Leg", draft: LegDraft()) { _ in }
        .environment(usage)
        .environment(FlightTracker(usage: usage))
}
#endif
