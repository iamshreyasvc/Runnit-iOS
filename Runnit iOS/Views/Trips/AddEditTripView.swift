//
//  AddEditTripView.swift
//  Runnit iOS
//
//  Add or edit a trip. Fields adapt to the selected mode: flights and trains
//  reveal carrier / number / boarding / seat; road trips keep it to route and
//  date. Origin & destination use LocationSearchField.
//

import SwiftUI
import SwiftData

struct AddEditTripView: View {
    /// Existing trip to edit, or nil to create a new one.
    var trip: Trip?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var type: TripType = .flight
    @State private var title: String = ""
    @State private var origin: Place?
    @State private var destination: Place?
    @State private var departureDate: Date = Date()
    @State private var hasArrival: Bool = false
    @State private var arrivalDate: Date = Date().addingTimeInterval(3600)

    @State private var operatorName: String = ""
    @State private var vehicleNumber: String = ""
    @State private var boardingPoint: String = ""
    @State private var seat: String = ""
    @State private var confirmation: String = ""
    @State private var notes: String = ""

    @State private var isSaving = false

    private var isEditing: Bool { trip != nil }
    private var canSave: Bool { origin != nil && destination != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Type", selection: $type) {
                        ForEach(TripType.allCases) { type in
                            Label(type.label, systemImage: type.symbol).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Route") {
                    LocationSearchField(title: "From", systemImage: "circle.circle", place: $origin)
                    LocationSearchField(title: "To", systemImage: "mappin.circle.fill", place: $destination)
                }

                Section("When") {
                    DatePicker("Departure", selection: $departureDate)
                    Toggle("Add arrival time", isOn: $hasArrival.animation())
                    if hasArrival {
                        DatePicker("Arrival", selection: $arrivalDate, in: departureDate...)
                    }
                }

                if type.isScheduledTransit {
                    Section(type == .flight ? "Flight details" : "Train details") {
                        TextField(type == .flight ? "Airline" : "Operator", text: $operatorName)
                        TextField(type.numberLabel, text: $vehicleNumber)
                            .textInputAutocapitalization(.characters)
                        TextField(type.boardingLabel, text: $boardingPoint)
                        TextField("Seat", text: $seat)
                        TextField("Confirmation #", text: $confirmation)
                            .textInputAutocapitalization(.characters)
                    }
                } else {
                    Section("Details") {
                        TextField("Trip name (optional)", text: $title)
                    }
                }

                Section("Notes") {
                    TextField("Anything to remember…", text: $notes, axis: .vertical)
                        .lineLimit(2...5)
                }
            }
            .navigationTitle(isEditing ? "Edit Trip" : "New Trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave || isSaving)
                }
            }
            .overlay {
                if isSaving {
                    ProgressView("Saving…").controlSize(.large)
                }
            }
            .onAppear(perform: loadIfEditing)
        }
    }

    private func loadIfEditing() {
        guard let trip else { return }
        type = trip.type
        title = trip.title
        origin = trip.origin
        destination = trip.destination
        departureDate = trip.departureDate
        if let arrival = trip.arrivalDate {
            hasArrival = true
            arrivalDate = arrival
        }
        operatorName = trip.operatorName ?? ""
        vehicleNumber = trip.vehicleNumber ?? ""
        boardingPoint = trip.boardingPoint ?? ""
        seat = trip.seat ?? ""
        confirmation = trip.confirmation ?? ""
        notes = trip.notes ?? ""
    }

    private func save() {
        guard var origin, var destination else { return }
        isSaving = true
        Task {
            // Ensure country / locality are populated for the Passport & Map.
            if origin.isoCountryCode == nil { origin = await origin.reverseGeocoded() }
            if destination.isoCountryCode == nil { destination = await destination.reverseGeocoded() }

            let target = trip ?? Trip(origin: origin, destination: destination)
            target.type = type
            target.title = title
            target.origin = origin
            target.destination = destination
            target.departureDate = departureDate
            target.arrivalDate = hasArrival ? arrivalDate : nil
            target.operatorName = emptyToNil(operatorName)
            target.vehicleNumber = emptyToNil(vehicleNumber)
            target.boardingPoint = emptyToNil(boardingPoint)
            target.seat = emptyToNil(seat)
            target.confirmation = emptyToNil(confirmation)
            target.notes = emptyToNil(notes)

            if trip == nil {
                context.insert(target)
            }
            try? context.save()
            isSaving = false
            dismiss()
        }
    }

    private func emptyToNil(_ string: String) -> String? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

#if DEBUG
#Preview {
    AddEditTripView()
        .modelContainer(PreviewData.container)
}
#endif
