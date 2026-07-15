//
//  PassportView.swift
//  Runnit iOS
//
//  The "Passport": a traveler's document distilled from completed trips —
//  a passport-cover hero, fun facts, world coverage, stamps, and achievements.
//

import SwiftUI
import SwiftData

struct PassportView: View {
    @Query private var allTrips: [Trip]
    @AppStorage(PrefKey.displayName) private var displayName = "Traveler"

    private var stats: TripStatistics { TripStatistics(trips: allTrips) }

    private let statColumns = [GridItem(.adaptive(minimum: 150), spacing: 14)]
    private let stampColumns = [GridItem(.adaptive(minimum: 110), spacing: 14)]
    private let badgeColumns = [GridItem(.adaptive(minimum: 108), spacing: 14)]

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground(accent: .indigo, secondary: .pink)
                content
            }
            .sectionHeader("Passport", systemImage: "book.closed", tint: .indigo,
                           subtitle: subtitle)
        }
    }

    private var subtitle: String? {
        guard stats.totalTrips > 0 else { return nil }
        let count = stats.uniqueCountries.count
        return "\(count) \(count == 1 ? "country" : "countries") visited"
    }

    @ViewBuilder
    private var content: some View {
        if stats.totalTrips == 0 {
            ContentUnavailableView(
                "Your Passport is empty",
                systemImage: "book.closed",
                description: Text("Completed trips unlock stamps, stats, and fun facts here.")
            )
            .padding(.top, 80)
        } else {
            ScrollView {
                VStack(spacing: 24) {
                    PassportHeroCard(name: displayName,
                                     trips: stats.totalTrips,
                                     countries: stats.uniqueCountries.count,
                                     continents: stats.continents.count)
                        .appear(0)
                    funFactsSection.appear(1)
                    statsSection.appear(2)
                    if !stats.continents.isEmpty { coverageSection.appear(3) }
                    if !stats.uniqueCountries.isEmpty { stampsSection.appear(4) }
                    highlightsSection.appear(5)
                    achievementsSection.appear(6)
                }
                .padding()
            }
        }
    }

    // MARK: Fun facts

    private var funFactsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Fun Facts", systemImage: "sparkles", tint: .yellow)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(stats.funFacts) { FunFactCard(fact: $0) }
                }
                .padding(.horizontal, 2)
            }
            .scrollClipDisabled()
        }
    }

    // MARK: Stats

    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "By the Numbers", systemImage: "chart.bar.fill", tint: .blue)
            LazyVGrid(columns: statColumns, spacing: 14) {
                StatCard(title: "Total distance",
                         value: Format.distance(stats.totalDistanceMeters),
                         systemImage: "ruler", tint: .blue)
                StatCard(title: "This year",
                         value: "\(stats.tripsThisYear) trips",
                         systemImage: "calendar", tint: .green)
                StatCard(title: "Cities",
                         value: "\(stats.uniqueCities)",
                         systemImage: "building.2.fill", tint: .purple)
                if stats.totalTravelTime > 0 {
                    StatCard(title: "Time in transit",
                             value: Format.duration(stats.totalTravelTime),
                             systemImage: "clock.fill", tint: .orange)
                }
                ForEach(stats.modeBreakdown) { mode in
                    StatCard(title: mode.type.label,
                             value: "\(mode.count)",
                             systemImage: mode.type.symbol, tint: mode.type.accent)
                }
            }
        }
    }

    // MARK: Coverage

    private var coverageSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "World Coverage", systemImage: "globe", tint: .teal)
            ContinentCoverageCard(visited: stats.continents)
        }
    }

    // MARK: Stamps

    private var stampsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Stamps", systemImage: "seal.fill", tint: .indigo,
                         accessory: "\(stats.uniqueCountries.count)")
            LazyVGrid(columns: stampColumns, spacing: 14) {
                ForEach(stats.uniqueCountries) { PassportStamp(country: $0) }
            }
        }
    }

    // MARK: Highlights

    @ViewBuilder
    private var highlightsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Highlights", systemImage: "star.fill", tint: .orange)
            VStack(spacing: 10) {
                if let longest = stats.longestTrip {
                    highlightRow(icon: "arrow.up.right.circle.fill", tint: .orange,
                                 title: "Longest trip",
                                 detail: "\(longest.displayTitle) · \(Format.distance(longest.distanceMeters))")
                }
                if let city = stats.favoriteCity {
                    highlightRow(icon: "heart.fill", tint: .pink,
                                 title: "Favorite city",
                                 detail: "\(city.name) · \(city.count) \(city.count == 1 ? "visit" : "visits")")
                }
                if let first = stats.firstTrip {
                    highlightRow(icon: "flag.checkered", tint: .purple,
                                 title: "First trip",
                                 detail: "\(first.displayTitle) · \(Format.date(first.departureDate, in: first.startPlace.timeZone))")
                }
                if let recent = stats.mostRecentTrip {
                    highlightRow(icon: "clock.fill", tint: .teal,
                                 title: "Most recent",
                                 detail: "\(recent.displayTitle) · \(Format.date(recent.departureDate, in: recent.startPlace.timeZone))")
                }
            }
            .glassCard()
        }
    }

    private func highlightRow(icon: String, tint: Color, title: String, detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(detail).font(.callout.weight(.medium)).lineLimit(1)
            }
            Spacer()
        }
    }

    // MARK: Achievements

    private var achievementsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            let unlocked = stats.achievements.filter(\.isUnlocked).count
            SectionTitle(title: "Achievements", systemImage: "trophy.fill", tint: .yellow,
                         accessory: "\(unlocked)/\(stats.achievements.count)")
            LazyVGrid(columns: badgeColumns, spacing: 14) {
                ForEach(stats.achievements) { AchievementBadge(achievement: $0) }
            }
        }
    }
}

#if DEBUG
#Preview {
    PassportView()
        .modelContainer(PreviewData.container)
}
#endif
