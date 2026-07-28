//
//  RootTabView.swift
//  Runnit iOS
//
//  App shell: five Liquid Glass tabs with a minimizing tab bar. Upcoming and
//  Past are separate tabs; Map is its own full, zoomable tab.
//

import SwiftUI
import SwiftData

enum AppTab: String, Hashable {
    case upcoming, past, passport, account
}

struct RootTabView: View {
    // Trips and their live records drive the notification schedule and the Home
    // Screen widget snapshot; both are rebuilt whenever the data changes.
    @Query private var trips: [Trip]
    @Query private var statusRecords: [FlightStatusRecord]
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage(PrefKey.appearance) private var appearanceRaw = AppAppearance.dark.rawValue
    private var appearance: AppAppearance {
        #if DEBUG
        if let raw = ProcessInfo.processInfo.environment["APPEARANCE"],
           let a = AppAppearance(rawValue: raw) {
            return a
        }
        #endif
        return AppAppearance(rawValue: appearanceRaw) ?? .dark
    }

    @State private var selection: AppTab = {
        #if DEBUG
        if let raw = ProcessInfo.processInfo.environment["INITIAL_TAB"],
           let tab = AppTab(rawValue: raw) {
            return tab
        }
        #endif
        return .upcoming
    }()

    var body: some View {
        TabView(selection: $selection) {
            Tab("Upcoming", systemImage: "airplane.departure", value: AppTab.upcoming) {
                TripsListView(filter: .upcoming)
            }
            Tab("Past", systemImage: "clock.arrow.circlepath", value: AppTab.past) {
                TripsListView(filter: .past)
            }
            Tab("Passport", systemImage: "book.closed", value: AppTab.passport) {
                PassportView()
            }
            Tab("Account", systemImage: "person.crop.circle", value: AppTab.account) {
                AccountView()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tint(.cyan)
        .preferredColorScheme(appearance.colorScheme)
        // Keep local notifications and the widget snapshot in step with the data.
        // A signature over the trips that matter (id + times) re-runs this only
        // when something a notification or the widget would show actually moves.
        .task(id: tripSignature) { await syncBackground() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await syncBackground() } }
        }
    }

    /// Rebuild the notification schedule and Home Screen snapshot, and surface any
    /// delay the app has already learned about. Cheap and idempotent.
    private func syncBackground() async {
        await TripNotifications.reschedule(for: trips)
        await TripNotifications.surfaceDelays(for: trips, records: statusRecords)
        WidgetSnapshotWriter.write(trips: trips, records: statusRecords)
    }

    /// A fingerprint of the trips a notification or widget would show — their ids
    /// and departure instants — so background sync re-runs on add, delete, or a
    /// retimed leg, but not on unrelated writes.
    private var tripSignature: String {
        trips
            .filter { !$0.isSample }
            .sorted { $0.id.uuidString < $1.id.uuidString }
            .map { "\($0.id.uuidString):\($0.departureDate.timeIntervalSince1970)" }
            .joined(separator: "|")
    }
}

#if DEBUG
#Preview {
    RootTabView()
        .modelContainer(PreviewData.container)
        .environment(FlightTracker())
}
#endif
