//
//  AddEditTripView.swift
//  Runnit iOS
//
//  Edit an existing trip (or create one). A trip is a title, optional notes, and
//  an ordered list of legs. Legs can be added, edited, reordered, and removed;
//  each leg opens in LegEditorView.
//

import SwiftUI
import SwiftData

struct AddEditTripView: View {
    /// Existing trip to edit, or nil to create a new one.
    var trip: Trip?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var title: String = ""
    @State private var notes: String = ""
    @State private var legs: [LegDraft] = []

    /// Sheet state: editing an existing leg (by index) or adding a new one.
    @State private var editingIndex: Int?
    @State private var showingLegEditor = false
    @State private var isSaving = false

    private var isEditing: Bool { trip != nil }
    private var canSave: Bool { !legs.isEmpty && legs.allSatisfy(\.isComplete) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Trip name") {
                    TextField("Optional title", text: $title)
                }

                Section {
                    ForEach(Array(legs.enumerated()), id: \.element.id) { idx, leg in
                        Button {
                            editingIndex = idx
                            showingLegEditor = true
                        } label: {
                            legRow(index: idx, leg: leg)
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete { legs.remove(atOffsets: $0) }
                    .onMove { legs.move(fromOffsets: $0, toOffset: $1) }

                    Button {
                        editingIndex = nil
                        showingLegEditor = true
                    } label: {
                        Label("Add leg", systemImage: "plus.circle.fill")
                    }
                } header: {
                    Text(legs.count > 1 ? "Legs (\(legs.count))" : "Legs")
                } footer: {
                    if legs.count > 1 {
                        Text("Swipe to delete, or use Edit to reorder legs.")
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
                ToolbarItem(placement: .topBarLeading) {
                    if legs.count > 1 { EditButton() }
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
            .sheet(isPresented: $showingLegEditor) {
                if let idx = editingIndex, legs.indices.contains(idx) {
                    LegEditorView(titleText: "Edit Leg", draft: legs[idx]) { updated in
                        legs[idx] = updated
                    }
                } else {
                    LegEditorView(titleText: "Add Leg", draft: newLegDraft()) { added in
                        legs.append(added)
                    }
                }
            }
            .onAppear(perform: loadIfEditing)
        }
    }

    private func legRow(index: Int, leg: LegDraft) -> some View {
        HStack(spacing: 12) {
            Image(systemName: leg.type.symbol)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(leg.type.gradient, in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(leg.type.label) · \(Format.date(leg.departureDate))")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(leg.type.accent)
                Text(leg.routeSummary)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption).foregroundStyle(.tertiary)
        }
    }

    /// A fresh leg pre-chained from the last leg's destination, if any.
    private func newLegDraft() -> LegDraft {
        var draft = LegDraft()
        if let last = legs.last {
            draft.origin = last.destination
            draft.departureDate = last.hasArrival ? last.arrivalDate : last.departureDate
        }
        return draft
    }

    private func loadIfEditing() {
        guard let trip, legs.isEmpty else { return }
        title = trip.title
        notes = trip.notes ?? ""
        legs = trip.orderedSegments.map(LegDraft.init(segment:))
        if legs.isEmpty {
            // A trip somehow without segments — seed from its flat summary.
            legs = trip.displaySegments.map(LegDraft.init(segment:))
        }
    }

    private func save() {
        guard canSave else { return }
        isSaving = true
        let capturedLegs = legs
        let tripTitle = title.trimmingCharacters(in: .whitespaces)
        let tripNotes = emptyToNil(notes)
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
                    operatorName: emptyToNil(leg.operatorName),
                    vehicleNumber: emptyToNil(leg.vehicleNumber),
                    boardingPoint: emptyToNil(leg.boardingPoint),
                    seat: emptyToNil(leg.seat),
                    confirmation: emptyToNil(leg.confirmation),
                    order: i
                ))
            }
            guard !segments.isEmpty else { isSaving = false; return }

            if let trip {
                // Replace the trip's legs wholesale, then re-derive its summary.
                for old in trip.segments { context.delete(old) }
                trip.segments = []
                for segment in segments {
                    context.insert(segment)
                    segment.trip = trip
                }
                trip.segments = segments
                trip.title = tripTitle
                trip.notes = tripNotes
                trip.refreshSummary()
            } else {
                let newTrip = Trip.make(title: tripTitle, notes: tripNotes, segments: segments)
                context.insert(newTrip)
                for segment in segments { context.insert(segment) }
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
    AddEditTripView(trip: .sampleMultiModal)
        .modelContainer(PreviewData.container)
}
#endif
