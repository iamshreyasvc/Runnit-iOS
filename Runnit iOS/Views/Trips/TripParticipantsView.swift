//
//  TripParticipantsView.swift
//  Runnit iOS
//
//  Who's on a trip, and what each of them can do.
//
//  Built in the same mould as the profile editor — a navigation stack of glass
//  cards over the ambient background — so managing people feels like the rest of
//  the app rather than a settings screen. Access is changed from the row itself:
//  the question "can Priya edit this?" is answered where Priya is, not behind a
//  separate detail screen.
//

import CloudKit
import SwiftData
import SwiftUI

struct TripParticipantsView: View {
    let trip: Trip

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var showingShare = false
    @State private var showingLeaveConfirm = false

    private let manager = ShareManager()

    private var accent: Color { trip.type.accent }
    private var others: [ShareParticipantSummary] { trip.collaborators.filter { !$0.isOwner } }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground(accent: accent, secondary: accent)
                ScrollView {
                    VStack(spacing: Spacing.md) {
                        ownerCard.appear(0)

                        if others.isEmpty {
                            emptyState.appear(1)
                        } else {
                            participantList.appear(1)
                        }

                        if trip.isOwnedByMe {
                            addPeopleButton.appear(2)
                        } else {
                            leaveButton.appear(2)
                        }

                        if let errorMessage {
                            errorNote(errorMessage)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, Spacing.sm)
                    .padding(.bottom, Spacing.xl)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("People")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showingShare) { ShareTripSheet(trip: trip) }
            .confirmationDialog("Leave this trip?", isPresented: $showingLeaveConfirm,
                                titleVisibility: .visible) {
                Button("Leave", role: .destructive) { Task { await leave() } }
            }
            .task { await refresh() }
        }
    }

    // MARK: Owner

    private var ownerCard: some View {
        HStack(spacing: 12) {
            ProfileAvatar(name: ownerName, accent: ownerAccent, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(trip.isOwnedByMe ? "You" : ownerName)
                    .font(.subheadline.weight(.semibold))
                Text("Organizer")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            HStack(spacing: 4) {
                Image(systemName: "crown.fill")
                    .font(.caption2.weight(.bold))
                Text("Full access")
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(accent)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(accent.opacity(0.15), in: .capsule)
        }
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 26))
    }

    private var ownerName: String {
        trip.ownerParticipant?.displayName ?? (trip.isOwnedByMe ? "You" : "Organizer")
    }

    private var ownerAccent: Color {
        trip.ownerParticipant?.accent ?? accent
    }

    // MARK: Participants

    private var participantList: some View {
        VStack(spacing: 0) {
            ForEach(Array(others.enumerated()), id: \.element.id) { index, person in
                if index > 0 { Divider().padding(.leading, 56) }
                row(for: person)
            }
        }
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 26))
    }

    private func row(for person: ShareParticipantSummary) -> some View {
        HStack(spacing: 12) {
            ProfileAvatar(name: person.name ?? "", accent: person.accent, size: 40)
                // A pending invite is a lighter presence than someone who joined.
                .opacity(person.acceptance == .accepted ? 1 : 0.55)

            VStack(alignment: .leading, spacing: 2) {
                Text(person.displayName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                if person.acceptance != .accepted {
                    Text(person.acceptance.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let handle = person.handle, person.name != nil {
                    Text(handle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: 8)
            permissionControl(for: person)
        }
        .padding(.vertical, 10)
    }

    /// The owner changes access straight from the row; everyone else just reads it.
    @ViewBuilder
    private func permissionControl(for person: ShareParticipantSummary) -> some View {
        if trip.isOwnedByMe {
            Menu {
                Picker("Access", selection: permissionBinding(for: person)) {
                    ForEach(SharePermission.allCases) { option in
                        Label(option.label, systemImage: option.symbol).tag(option)
                    }
                }
                Divider()
                Button(role: .destructive) {
                    Task { await remove(person) }
                } label: {
                    Label("Remove", systemImage: "person.fill.xmark")
                }
            } label: {
                permissionChip(for: person, showsChevron: true)
            }
            .disabled(isWorking)
        } else {
            permissionChip(for: person, showsChevron: false)
        }
    }

    private func permissionChip(for person: ShareParticipantSummary,
                                showsChevron: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: person.permission.symbol)
                .font(.caption2.weight(.bold))
            Text(person.permission.label)
                .font(.caption.weight(.semibold))
            if showsChevron {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
        }
        .foregroundStyle(person.permission == .readWrite ? accent : .secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background((person.permission == .readWrite ? accent : Color.secondary).opacity(0.15),
                    in: .capsule)
    }

    private func permissionBinding(for person: ShareParticipantSummary) -> Binding<SharePermission> {
        Binding(
            get: { person.permission },
            set: { newValue in
                guard newValue != person.permission else { return }
                Task { await setPermission(newValue, for: person) }
            }
        )
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "person.2")
                .font(.title2.weight(.semibold))
                .foregroundStyle(accent)
                .frame(width: 62, height: 62)
                .glassEffect(.regular, in: .circle)

            Text("No one's joined yet")
                .font(.headline)
            Text(trip.isOwnedByMe
                 ? "Invite a travel companion and they'll see this trip's legs, map, and live status."
                 : "You're the only guest on this trip so far.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.lg)
        .padding(.horizontal, Spacing.md)
        .glassEffect(.regular, in: .rect(cornerRadius: 26))
    }

    // MARK: Actions

    private var addPeopleButton: some View {
        Button { showingShare = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "person.badge.plus")
                Text("Add People")
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .buttonStyle(.glassProminent)
        .tint(accent)
    }

    private var leaveButton: some View {
        Button(role: .destructive) { showingLeaveConfirm = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "person.fill.xmark")
                Text("Leave Trip")
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .buttonStyle(.glass)
        .tint(.red)
    }

    private func errorNote(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.footnote)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .glassCard(tint: .orange.opacity(0.2))
    }

    // MARK: Work

    /// Pull the roster from CloudKit. What's stored on the trip is only a
    /// snapshot of the last time we asked, and someone may have accepted since.
    private func refresh() async {
        guard trip.isShared else { return }
        do {
            let share = trip.isOwnedByMe
                ? try await manager.share(for: trip, defaultPermission: .readWrite)
                : try await manager.participantShare(for: trip)
            guard let share else { return }
            await manager.refreshParticipants(on: trip, from: share)
            try? context.save()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func setPermission(_ permission: SharePermission,
                               for person: ShareParticipantSummary) async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            try await manager.setPermission(permission, for: person, on: trip)
            try? context.save()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func remove(_ person: ShareParticipantSummary) async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            try await manager.remove(person, from: trip)
            try? context.save()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func leave() async {
        do {
            try await manager.leave(trip, in: context)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#if DEBUG
#Preview {
    TripParticipantsView(trip: .sampleFlight)
        .modelContainer(PreviewData.container)
        .preferredColorScheme(.dark)
}
#endif
