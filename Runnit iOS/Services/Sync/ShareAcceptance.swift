//
//  ShareAcceptance.swift
//  Runnit iOS
//
//  Receiving an invite.
//
//  Tapping a share link in Messages or Mail opens the app with a
//  `CKShare.Metadata` in hand, and the only place iOS hands it over is a
//  UIKit scene delegate — SwiftUI has no equivalent hook. So the app keeps a
//  minimal delegate whose sole jobs are accepting shares and registering for
//  the silent pushes that tell the sync engines something changed.
//

import CloudKit
import Observation
import SwiftUI
import UIKit

/// Bridges an accepted invite back into the app.
///
/// A singleton because the scene delegate is created by UIKit and has no way to
/// reach the SwiftUI environment. The app registers the live sync engine here at
/// launch; until it does, invites are held rather than dropped, which matters
/// because a cold launch from a share link arrives before the app is ready.
@MainActor
@Observable
final class ShareAcceptanceCoordinator {
    static let shared = ShareAcceptanceCoordinator()

    /// True while an invite is being accepted, so the UI can say something.
    private(set) var isAccepting = false
    /// Set when accepting fails, for a one-off alert.
    var failureMessage: String?

    private var sync: SyncEngine?
    private var pending: [CKShare.Metadata] = []

    /// Resolved lazily — see `CloudContainer`. The coordinator itself is touched
    /// during launch, so it must not drag CloudKit up with it.
    private var container: CKContainer { CloudContainer.shared }

    private init() {}

    /// Called once the app's sync engine exists. Drains anything that arrived
    /// during launch.
    func register(_ sync: SyncEngine) {
        self.sync = sync
        guard !pending.isEmpty else { return }
        let queued = pending
        pending.removeAll()
        Task { await accept(queued) }
    }

    /// Entry point from the scene delegate.
    func handle(_ metadata: CKShare.Metadata) {
        guard sync != nil else {
            pending.append(metadata)
            return
        }
        Task { await accept([metadata]) }
    }

    private func accept(_ metadata: [CKShare.Metadata]) async {
        guard !metadata.isEmpty else { return }
        isAccepting = true
        defer { isAccepting = false }

        do {
            _ = try await container.accept(metadata)
            // Accepting only grants access; the trip itself arrives on the next
            // sync of the shared database.
            await sync?.start()
        } catch {
            failureMessage = error.localizedDescription
        }
    }
}

/// The app's UIKit delegate. Deliberately tiny — it exists for the two things
/// SwiftUI can't express.
final class AppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // CKSyncEngine keeps itself current from CloudKit's silent pushes; they
        // only arrive if the app is registered to receive them.
        //
        // Harmless while the Push Notifications capability is off: registration
        // simply fails and sync falls back to fetching on launch and foreground.
        // Turning the capability on in Xcode is all that's needed to light it up.
        application.registerForRemoteNotifications()
        return true
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting session: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: session.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}

/// Exists solely to catch accepted CloudKit shares.
final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(_ windowScene: UIWindowScene,
                     userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
        Task { @MainActor in
            ShareAcceptanceCoordinator.shared.handle(metadata)
        }
    }
}
