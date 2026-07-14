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
    }
}

#if DEBUG
#Preview {
    RootTabView()
        .modelContainer(PreviewData.container)
        .environment(FlightTracker())
}
#endif
