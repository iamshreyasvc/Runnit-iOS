//
//  AddEditTripView.swift
//  Runnit iOS
//
//  Edit an existing trip (or create one). A trip is a title, optional notes, and
//  an ordered list of legs. Legs can be added, edited, reordered, and removed;
//  each leg opens in LegEditorView. Styled to match the Add Trip flow.
//

import SwiftUI
import SwiftData

/// The leg-editor sheet target: a new leg, or an existing one by index.
private enum LegEditTarget: Identifiable {
    case new
    case existing(Int)
    var id: String {
        switch self {
        case .new:              return "new"
        case .existing(let i):  return "existing-\(i)"
        }
    }
}

struct AddEditTripView: View {
    /// Existing trip to edit, or nil to create a new one.
    var trip: Trip?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage(PrefKey.appearance) private var appearanceRaw = AppAppearance.dark.rawValue

    @State private var title: String = ""
    @State private var notes: String = ""
    @State private var legs: [LegDraft] = []

    /// Which leg editor to present. Using `.sheet(item:)` (not a separate Bool +
    /// index) guarantees the sheet always reads the intended target — otherwise
    /// tapping a leg could open the "Add" branch and append a duplicate.
    @State private var legEditTarget: LegEditTarget?
    @State private var isSaving = false

    private let accent: Color = .cyan
    private var isEditing: Bool { trip != nil }
    private var canSave: Bool { !legs.isEmpty && legs.allSatisfy(\.isComplete) }

    var body: some View {
        NavigationStack {
            ZStack {
                PlanBackground()
                List {
                    nameSection
                    legsSection
                    connectionsSection
                    notesSection
                }
                .scrollContentBackground(.hidden)
                .listSectionSpacing(20)
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
                        .fontWeight(.semibold)
                        .disabled(!canSave || isSaving)
                }
            }
            .overlay {
                if isSaving {
                    ProgressView("Saving…").controlSize(.large)
                        .padding(24)
                        .glassEffect(.regular, in: .rect(cornerRadius: 20))
                }
            }
            .sheet(item: $legEditTarget) { target in
                switch target {
                case .existing(let idx) where legs.indices.contains(idx):
                    LegEditorView(titleText: "Edit Leg", draft: legs[idx]) { updated in
                        legs[idx] = updated
                    }
                default:
                    LegEditorView(titleText: "Add Leg", draft: newLegDraft()) { added in
                        legs.append(added)
                    }
                }
            }
            .tint(accent)
            .preferredColorScheme((AppAppearance(rawValue: appearanceRaw) ?? .dark).colorScheme)
            .onAppear(perform: loadIfEditing)
        }
    }

    // MARK: Sections

    private var nameSection: some View {
        Section {
            TextField("Trip name (optional)", text: $title)
                .listRowBackground(rowBackground)
        } header: {
            Text("Trip")
        }
    }

    private var legsSection: some View {
        Section {
            ForEach(Array(legs.enumerated()), id: \.element.id) { idx, leg in
                Button {
                    legEditTarget = .existing(idx)
                } label: {
                    legRow(index: idx, leg: leg)
                }
                .buttonStyle(.plain)
                .listRowBackground(rowBackground)
            }
            .onDelete { legs.remove(atOffsets: $0) }
            .onMove { legs.move(fromOffsets: $0, toOffset: $1) }

            Button {
                legEditTarget = .new
            } label: {
                Label("Add leg", systemImage: "plus.circle.fill")
                    .fontWeight(.semibold)
            }
            .listRowBackground(rowBackground)
        } header: {
            Text(legs.count > 1 ? "Legs (\(legs.count))" : "Legs")
        } footer: {
            if legs.count > 1 {
                Text("Swipe to delete, or tap Edit to reorder.")
            } else if legs.isEmpty {
                Text("Add at least one leg to save this trip.")
            }
        }
    }

    /// Connections implied by the current legs. Its own section on purpose: the
    /// legs ForEach has to stay one row per leg or swipe-to-delete and drag-to-
    /// reorder would map to the wrong indices.
    @ViewBuilder
    private var connectionsSection: some View {
        let connections = legs.draftConnections
        if !connections.isEmpty {
            Section {
                ForEach(connections) { connection in
                    ConnectionStrip(connection: connection)
                        .listRowBackground(rowBackground)
                }
            } header: {
                Text(connections.count > 1 ? "Connections (\(connections.count))" : "Connection")
            } footer: {
                if let worst = connections.first(where: { $0.risk.isUrgent }) {
                    Text(worst.risk == .missed
                         ? "This itinerary can't be flown as entered — check the times."
                         : "Tight on the ground. Double-check the times, or allow more room.")
                        .foregroundStyle(.orange)
                } else {
                    Text("Layovers are measured from the previous leg's arrival time.")
                }
            }
        }
    }

    private var notesSection: some View {
        Section("Notes") {
            TextField("Anything to remember…", text: $notes, axis: .vertical)
                .lineLimit(2...5)
                .listRowBackground(rowBackground)
        }
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 14).fill(.ultraThinMaterial)
    }

    private func legRow(index: Int, leg: LegDraft) -> some View {
        HStack(spacing: 12) {
            Image(systemName: leg.type.symbol)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(leg.type.gradient, in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(leg.type.label) · \(Format.date(leg.departureDate, in: leg.origin?.timeZone))")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(leg.type.accent)
                Text(leg.routeSummary)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer()
            if legs.count > 1 {
                Text("Leg \(index + 1)").font(.caption2).foregroundStyle(.tertiary)
            }
            Image(systemName: "chevron.right")
                .font(.caption).foregroundStyle(.tertiary)
        }
    }

    /// A fresh leg pre-chained from the last leg's destination, if any. It starts
    /// a couple of hours after that leg ends — a leg departing the instant the
    /// previous one lands is a connection you'd miss.
    private func newLegDraft() -> LegDraft {
        var draft = LegDraft()
        if let last = legs.last {
            draft.type = last.type
            draft.origin = last.destination
            let previousEnd = last.hasArrival ? last.arrivalDate : last.departureDate
            draft.departureDate = previousEnd.addingTimeInterval(2 * 3600)
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

    // MARK: Save

    private func save() {
        guard canSave else { return }
        isSaving = true
        let drafts = legs
        let tripTitle = title.trimmingCharacters(in: .whitespaces)
        let tripNotes = emptyToNil(notes)
        Task {
            // Resolve any missing country/locality for each leg first.
            var resolved: [(draft: LegDraft, origin: Place, destination: Place)] = []
            for leg in drafts {
                guard var origin = leg.origin, var destination = leg.destination else { continue }
                if origin.isoCountryCode == nil { origin = await origin.reverseGeocoded() }
                if destination.isoCountryCode == nil { destination = await destination.reverseGeocoded() }
                resolved.append((leg, origin, destination))
            }
            guard !resolved.isEmpty else { isSaving = false; return }

            if let trip {
                applyEdits(to: trip, resolved: resolved, title: tripTitle, notes: tripNotes)
            } else {
                var segments: [TripSegment] = []
                for (i, item) in resolved.enumerated() {
                    segments.append(makeSegment(item.draft, item.origin, item.destination, order: i))
                }
                let newTrip = Trip.make(title: tripTitle, notes: tripNotes, segments: segments)
                context.insert(newTrip)
                for segment in segments { context.insert(segment) }
            }
            try? context.save()
            isSaving = false
            dismiss()
        }
    }

    /// Update an existing trip in place. Reuses each leg's existing TripSegment
    /// (so its cached live-flight status survives), inserts genuinely-new legs,
    /// and deletes removed ones along with any orphaned flight-status records.
    private func applyEdits(to trip: Trip, resolved: [(draft: LegDraft, origin: Place, destination: Place)],
                            title: String, notes: String?) {
        let existing = Dictionary(trip.segments.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var keptIDs = Set<UUID>()
        var newList: [TripSegment] = []

        for (i, item) in resolved.enumerated() {
            let leg = item.draft
            if let sid = leg.segmentID, let seg = existing[sid] {
                // The flight identity changed → its cached status is now wrong.
                let flightChanged = seg.type != leg.type
                    || seg.vehicleNumber != emptyToNil(leg.vehicleNumber)
                    || seg.origin != item.origin
                seg.type = leg.type
                seg.origin = item.origin
                seg.destination = item.destination
                seg.departureDate = leg.departureDate
                seg.arrivalDate = leg.hasArrival ? leg.arrivalDate : nil
                seg.operatorName = emptyToNil(leg.operatorName)
                seg.vehicleNumber = emptyToNil(leg.vehicleNumber)
                seg.boardingPoint = emptyToNil(leg.boardingPoint)
                seg.seat = emptyToNil(leg.seat)
                seg.confirmation = emptyToNil(leg.confirmation)
                seg.order = i
                if flightChanged { deleteFlightRecord(segmentID: seg.id) }
                keptIDs.insert(sid)
                newList.append(seg)
            } else {
                let seg = makeSegment(leg, item.origin, item.destination, order: i)
                context.insert(seg)
                seg.trip = trip
                newList.append(seg)
            }
        }

        // Delete dropped segments and their cached status.
        let removed = trip.segments.filter { !keptIDs.contains($0.id) }
        for old in removed {
            deleteFlightRecord(segmentID: old.id)
            context.delete(old)
        }

        trip.segments = newList
        trip.title = title
        trip.notes = notes
        trip.refreshSummary()
    }

    private func makeSegment(_ leg: LegDraft, _ origin: Place, _ destination: Place, order: Int) -> TripSegment {
        TripSegment(
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
            order: order
        )
    }

    private func deleteFlightRecord(segmentID: UUID) {
        let descriptor = FetchDescriptor<FlightStatusRecord>(
            predicate: #Predicate { $0.segmentID == segmentID }
        )
        if let records = try? context.fetch(descriptor) {
            records.forEach(context.delete)
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
        .environment(FlightTracker())
}
#endif
