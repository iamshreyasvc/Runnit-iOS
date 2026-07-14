//
//  PassportView.swift
//  Runnit iOS
//
//  The "Passport": stats & stamps distilled from completed trips.
//

import SwiftUI
import SwiftData

struct PassportView: View {
    @Query private var allTrips: [Trip]

    private var stats: TripStatistics { TripStatistics(trips: allTrips) }

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 14)]

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground(accent: .indigo, secondary: .pink)
                ScrollView {
                if stats.totalTrips == 0 {
                    ContentUnavailableView(
                        "Your Passport is empty",
                        systemImage: "book.closed",
                        description: Text("Completed trips unlock stamps and stats here.")
                    )
                    .padding(.top, 80)
                } else {
                    VStack(spacing: 20) {
                        header
                        statsGrid
                        if !stats.uniqueCountries.isEmpty { stampsSection }
                        highlightsSection
                    }
                    .padding()
                }
                }
            }
            .sectionHeader("Passport", systemImage: "book.closed", tint: .indigo,
                           subtitle: stats.totalTrips == 0 ? nil : "\(stats.uniqueCountries.count) \(stats.uniqueCountries.count == 1 ? "country" : "countries") visited")
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            Image(systemName: "globe.americas.fill")
                .font(.system(size: 44))
                .foregroundStyle(.blue.gradient)
            Text("\(stats.totalTrips) trips")
                .font(.largeTitle.weight(.bold))
            Text("\(stats.uniqueCountries.count) countries · \(stats.uniqueCities) cities")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .glassEffect(.regular, in: .rect(cornerRadius: 28))
    }

    private var statsGrid: some View {
        LazyVGrid(columns: columns, spacing: 14) {
            StatCard(title: "Total distance",
                     value: Format.distance(stats.totalDistanceMeters),
                     systemImage: "ruler", tint: .blue)
            StatCard(title: "This year",
                     value: "\(stats.tripsThisYear) trips",
                     systemImage: "calendar", tint: .green)
            ForEach(stats.modeBreakdown) { mode in
                StatCard(title: mode.type.label,
                         value: "\(mode.count)",
                         systemImage: mode.type.symbol, tint: mode.type.accent)
            }
        }
    }

    private var stampsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Stamps")
                .font(.title3.weight(.semibold))
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(stats.uniqueCountries) { country in
                    PassportStamp(country: country)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var highlightsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Highlights")
                .font(.title3.weight(.semibold))
            VStack(spacing: 10) {
                if let longest = stats.longestTrip {
                    highlightRow(icon: "arrow.up.right.circle.fill", tint: .orange,
                                 title: "Longest trip",
                                 detail: "\(longest.displayTitle) · \(Format.distance(longest.distanceMeters))")
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
        .frame(maxWidth: .infinity, alignment: .leading)
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
}

struct StatCard: View {
    let title: String
    let value: String
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(tint)
            Text(value)
                .font(.title2.weight(.bold))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
        .glassCard(cornerRadius: 20, tint: tint.opacity(0.28))
    }
}

struct PassportStamp: View {
    let country: CountryVisit

    var body: some View {
        VStack(spacing: 6) {
            Text(country.flag)
                .font(.system(size: 40))
            Text(country.name)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text("\(country.tripCount)×")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 110)
        .padding(8)
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(.secondary.opacity(0.25), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
        )
    }
}

#if DEBUG
#Preview {
    PassportView()
        .modelContainer(PreviewData.container)
}
#endif
