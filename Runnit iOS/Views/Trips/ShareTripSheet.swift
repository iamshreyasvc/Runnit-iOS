//
//  ShareTripSheet.swift
//  Runnit iOS
//
//  Inviting people to a trip.
//
//  The system share sheet is unavoidable — it's the only way to pick contacts
//  and actually send an iCloud invite. What it isn't good at is the question
//  that matters first: how much access is this person getting? So that decision
//  is asked here, in the app's own conversational one-question-at-a-time voice,
//  and carried into the system sheet as the access it's allowed to grant.
//

import CloudKit
import SwiftData
import SwiftUI
import UIKit

struct ShareTripSheet: View {
    let trip: Trip

    @Environment(\.dismiss) private var dismiss

    @State private var permission: SharePermission = .readWrite
    @State private var share: CKShare?
    @State private var presentingSystemSheet = false
    @State private var isPreparing = false
    @State private var errorMessage: String?

    private let manager = ShareManager()

    private var accent: Color { trip.type.accent }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground(accent: accent, secondary: accent)
                ScrollView {
                    VStack(spacing: Spacing.lg) {
                        header.appear(0)
                        permissionCard.appear(1)
                        inviteButton.appear(2)
                        if let errorMessage {
                            errorNote(errorMessage).appear(3)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, Spacing.sm)
                    .padding(.bottom, Spacing.xl)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Share Trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .sheet(isPresented: $presentingSystemSheet) {
            if let share {
                CloudSharingSheet(share: share,
                                  container: CloudContainer.shared,
                                  permission: permission) {
                    Task { await manager.refreshParticipants(on: trip, from: share) }
                }
                .ignoresSafeArea()
            }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 12) {
            Image(systemName: trip.type.symbol)
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 54, height: 54)
                .background(trip.type.gradient, in: .circle)
                .shadow(color: accent.opacity(0.5), radius: 12, y: 5)

            Text(trip.displayTitle)
                .font(.title3.weight(.bold))
                .multilineTextAlignment(.center)
                .lineLimit(2)

            Text("Anyone you invite can see this trip's legs, map, and live status.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.md)
    }

    // MARK: Permission

    private var permissionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Access", systemImage: "lock.fill", tint: accent)

            Picker("Access", selection: $permission) {
                ForEach(SharePermission.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .tint(accent)

            // The explainer swaps with the choice, so the consequence is read at
            // the moment of choosing rather than recalled afterwards.
            Text(permission.blurb)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentTransition(.opacity)
                .animation(.smooth(duration: 0.25), value: permission)
        }
        .glassCard(tint: accent.opacity(0.28))
    }

    // MARK: Invite

    private var inviteButton: some View {
        Button {
            Task { await prepareAndPresent() }
        } label: {
            HStack(spacing: 8) {
                if isPreparing {
                    ProgressView().controlSize(.small).tint(.white)
                } else {
                    Image(systemName: "person.badge.plus")
                }
                Text(trip.isShared ? "Invite More People" : "Invite People")
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .buttonStyle(.glassProminent)
        .tint(accent)
        .disabled(isPreparing)
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

    // MARK: Actions

    /// Create (or reuse) the share, then hand off to the system sheet. The share
    /// has to exist on the server before anyone can be invited to it, which is
    /// why this can spin briefly on a slow connection.
    private func prepareAndPresent() async {
        isPreparing = true
        errorMessage = nil
        defer { isPreparing = false }

        do {
            share = try await manager.share(for: trip, defaultPermission: permission)
            presentingSystemSheet = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - System sharing sheet

/// `UICloudSharingController` wrapped for SwiftUI.
///
/// There's no SwiftUI equivalent: sending an iCloud share means picking people
/// from Contacts and handing the invite to Messages or Mail, and only this
/// controller does that. The permission chosen in the app restricts what it
/// offers, so the two screens can't disagree.
struct CloudSharingSheet: UIViewControllerRepresentable {
    let share: CKShare
    let container: CKContainer
    let permission: SharePermission
    var onChange: () -> Void = {}

    func makeCoordinator() -> Coordinator { Coordinator(onChange: onChange) }

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: share, container: container)
        controller.availablePermissions = permission == .readWrite
            ? [.allowReadWrite, .allowPrivate]
            : [.allowReadOnly, .allowPrivate]
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: UICloudSharingController, context: Context) {}

    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        private let onChange: () -> Void

        init(onChange: @escaping () -> Void) {
            self.onChange = onChange
        }

        func itemTitle(for controller: UICloudSharingController) -> String? {
            controller.share?[CKShare.SystemFieldKey.title] as? String
        }

        func cloudSharingControllerDidSaveShare(_ controller: UICloudSharingController) {
            onChange()
        }

        func cloudSharingControllerDidStopSharing(_ controller: UICloudSharingController) {
            onChange()
        }

        func cloudSharingController(_ controller: UICloudSharingController,
                                    failedToSaveShareWithError error: Error) {
            onChange()
        }
    }
}

#if DEBUG
#Preview {
    ShareTripSheet(trip: .sampleFlight)
        .modelContainer(PreviewData.container)
        .preferredColorScheme(.dark)
}
#endif
