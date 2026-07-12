//
//  AccountView.swift
//  Runnit iOS
//
//  Traveler profile, lifetime stats, and app preferences.
//

import SwiftUI
import SwiftData

struct AccountView: View {
    @Query private var allTrips: [Trip]

    @AppStorage(PrefKey.appearance) private var appearanceRaw = AppAppearance.dark.rawValue
    @AppStorage(PrefKey.distanceUnit) private var distanceUnitRaw = DistanceUnit.automatic.rawValue
    @AppStorage(PrefKey.displayName) private var displayName = "Traveler"

    private var stats: TripStatistics { TripStatistics(trips: allTrips) }
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground(accent: .purple, secondary: .cyan)
                ScrollView {
                    VStack(spacing: 20) {
                        profileHeader
                        lifetimeStats
                        preferencesCard
                        aboutCard
                    }
                    .padding()
                }
            }
            .navigationTitle("Account")
        }
    }

    // MARK: Profile

    private var profileHeader: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(.white, .cyan.gradient)
                .shadow(color: .cyan.opacity(0.5), radius: 12, y: 4)

            TextField("Your name", text: $displayName)
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)

            Text("Frequent traveler")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .glassCard(cornerRadius: 28, tint: .cyan.opacity(0.22))
    }

    private var lifetimeStats: some View {
        HStack(spacing: 12) {
            statPill("\(allTrips.count)", "Trips", "suitcase.fill", .blue)
            statPill("\(stats.uniqueCountries.count)", "Countries", "globe", .green)
            statPill(Format.distance(allTrips.reduce(0) { $0 + $1.distanceMeters }),
                     "Traveled", "ruler", .orange)
        }
    }

    private func statPill(_ value: String, _ label: String, _ icon: String, _ tint: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon).foregroundStyle(tint)
            Text(value).font(.headline).minimumScaleFactor(0.6).lineLimit(1)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 88)
        .glassCard(cornerRadius: 20, tint: tint.opacity(0.22))
    }

    // MARK: Preferences

    private var preferencesCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Preferences").font(.headline)

            VStack(spacing: 6) {
                Text("Appearance")
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(.secondary)
                Picker("Appearance", selection: $appearanceRaw) {
                    ForEach(AppAppearance.allCases) { Text($0.label).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
            }

            VStack(spacing: 6) {
                Text("Distance units")
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(.secondary)
                Picker("Distance units", selection: $distanceUnitRaw) {
                    ForEach(DistanceUnit.allCases) { Text($0.label).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    // MARK: About

    private var aboutCard: some View {
        VStack(spacing: 0) {
            aboutRow("Navigation app", "Apple Maps", "location.north.line.fill")
            Divider()
            aboutRow("Version", appVersion, "info.circle")
        }
        .glassCard()
    }

    private func aboutRow(_ title: String, _ value: String, _ icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(.cyan).frame(width: 26)
            Text(title)
            Spacer()
            Text(value).foregroundStyle(.secondary)
        }
        .padding(.vertical, 10)
    }
}

#if DEBUG
#Preview {
    AccountView()
        .modelContainer(PreviewData.container)
        .preferredColorScheme(.dark)
}
#endif
