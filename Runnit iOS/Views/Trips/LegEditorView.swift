//
//  LegEditorView.swift
//  Runnit iOS
//
//  A form for editing a single leg of a trip, plus the `LegDraft` value type
//  shared by the trip editor. Fields adapt to the selected mode.
//

import SwiftUI

/// An editable, in-memory representation of one trip leg.
struct LegDraft: Identifiable, Hashable {
    var id = UUID()
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

/// A modal form to add or edit a single leg. Calls `onSave` with the result.
struct LegEditorView: View {
    let titleText: String
    @State private var draft: LegDraft
    let onSave: (LegDraft) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(FlightTracker.self) private var tracker

    @State private var lookupNumber = ""
    @State private var lookingUp = false
    @State private var lookupMessage: String?
    @State private var lookupSucceeded = false

    init(titleText: String, draft: LegDraft, onSave: @escaping (LegDraft) -> Void) {
        self.titleText = titleText
        self._draft = State(initialValue: draft)
        self.onSave = onSave
        self._lookupNumber = State(initialValue: draft.vehicleNumber)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Type", selection: $draft.type) {
                        ForEach(TripType.allCases) { type in
                            Label(type.label, systemImage: type.symbol).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if draft.type == .flight { flightLookupSection }

                Section("Route") {
                    LocationSearchField(title: "From", systemImage: "circle.circle", place: $draft.origin)
                    LocationSearchField(title: "To", systemImage: "mappin.circle.fill", place: $draft.destination)
                }

                Section("When") {
                    DatePicker("Departure", selection: $draft.departureDate)
                    Toggle("Add arrival time", isOn: $draft.hasArrival.animation())
                    if draft.hasArrival {
                        DatePicker("Arrival", selection: $draft.arrivalDate, in: draft.departureDate...)
                    }
                }

                if draft.type.isScheduledTransit {
                    Section(draft.type == .flight ? "Flight details" : "Train details") {
                        TextField(draft.type == .flight ? "Airline" : "Operator", text: $draft.operatorName)
                        TextField(draft.type.numberLabel, text: $draft.vehicleNumber)
                            .textInputAutocapitalization(.characters)
                        TextField(draft.type.boardingLabel, text: $draft.boardingPoint)
                        TextField("Seat", text: $draft.seat)
                        TextField("Confirmation #", text: $draft.confirmation)
                            .textInputAutocapitalization(.characters)
                    }
                }
            }
            .navigationTitle(titleText)
            .navigationBarTitleDisplayMode(.inline)
            .disabled(lookingUp)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onSave(draft)
                        dismiss()
                    }
                    .disabled(!draft.isComplete || lookingUp)
                }
            }
        }
    }

    // MARK: Flight auto-fill

    private var flightLookupSection: some View {
        Section {
            HStack {
                TextField("Flight number (e.g. AA 100)", text: $lookupNumber)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .onSubmit { Task { await runLookup() } }
                if lookingUp {
                    ProgressView()
                } else {
                    Button("Look up") { Task { await runLookup() } }
                        .buttonStyle(.borderless)
                        .disabled(lookupNumber.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            DatePicker("Travel date", selection: $draft.departureDate, displayedComponents: .date)
            if let msg = lookupMessage {
                Label(msg, systemImage: lookupSucceeded ? "checkmark.circle.fill" : "info.circle")
                    .font(.caption)
                    .foregroundStyle(lookupSucceeded ? .green : .secondary)
            }
        } header: {
            Text("Auto-fill")
        } footer: {
            Text("Enter a flight number and date to fill in the route, airline, and times automatically. Uses one API lookup.")
        }
    }

    private func runLookup() async {
        lookingUp = true
        lookupMessage = nil
        lookupSucceeded = false
        let outcome = await FlightAutofill.run(flightNumber: lookupNumber, date: draft.departureDate, tracker: tracker)
        lookingUp = false

        if case .filled(let f) = outcome {
            if let o = f.origin { draft.origin = o }
            if let d = f.destination { draft.destination = d }
            if !f.airline.isEmpty { draft.operatorName = f.airline }
            if !f.flightNumber.isEmpty { draft.vehicleNumber = f.flightNumber }
            if let dep = f.departure { draft.departureDate = dep }
            if let arr = f.arrival { draft.hasArrival = true; draft.arrivalDate = arr }
            lookupSucceeded = true
            lookupMessage = "Filled: \(f.routeSummary)"
        } else {
            lookupMessage = outcome.message
        }
    }
}
