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
    @State private var acceptance = ShareAcceptanceCoordinator.shared

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
        // Accepting an invite happens outside any screen — the app is opened by
        // a link in Messages. Both the wait and the failure need somewhere to
        // show, or tapping an invite looks like nothing happened.
        .overlay(alignment: .top) {
            if acceptance.isAccepting { joiningBanner }
        }
        .animation(.smooth(duration: 0.3), value: acceptance.isAccepting)
        .alert("Couldn't open this trip",
               isPresented: .init(get: { acceptance.failureMessage != nil },
                                  set: { if !$0 { acceptance.failureMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(acceptance.failureMessage ?? "")
        }
    }

    /// A brief glass pill while an invite is being accepted.
    private var joiningBanner: some View {
        HStack(spacing: 9) {
            ProgressView().controlSize(.small)
            Text("Joining trip…")
                .font(.subheadline.weight(.semibold))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: .capsule)
        .padding(.top, 8)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

#if DEBUG
#Preview {
    RootTabView()
        .modelContainer(PreviewData.container)
        .environment(FlightTracker())
        .environment(PreviewData.sync)
}
#endif
