//
//  PassportInsights.swift
//  Runnit iOS
//
//  Turns raw travel statistics into the playful, human-readable "fun facts" and
//  unlockable achievements shown on the Passport screen.
//

import SwiftUI

/// A single delightful comparison, e.g. "2.4× around the Earth".
struct FunFact: Identifiable {
    let id = UUID()
    let icon: String
    let tint: Color
    let value: String
    let caption: String
}

/// A milestone badge — unlocked once, or shown dimmed with progress toward it.
struct Achievement: Identifiable, Equatable {
    let id = UUID()
    let icon: String
    let tint: Color
    let title: String
    let detail: String
    let isUnlocked: Bool
    let progress: Double

    /// Two badges are the same milestone when they carry the same title — the
    /// stable identity `AchievementTracker` and the celebration queue rely on.
    static func == (lhs: Achievement, rhs: Achievement) -> Bool {
        lhs.title == rhs.title && lhs.isUnlocked == rhs.isUnlocked
    }
}

extension TripStatistics {
    /// Earth's equatorial circumference, in meters.
    private static let earthCircumference = 40_075_000.0
    /// Average Earth–Moon distance, in meters.
    private static let moonDistance = 384_400_000.0

    /// Playful equivalents distilled from the traveler's totals. Only facts that
    /// actually have data behind them are returned.
    var funFacts: [FunFact] {
        var facts: [FunFact] = []
        let distance = totalDistanceMeters

        if distance > 0 {
            let laps = distance / Self.earthCircumference
            facts.append(FunFact(
                icon: "globe.desk.fill", tint: .blue,
                value: laps >= 1 ? String(format: "%.1f×", laps) : "\(Int(laps * 100))%",
                caption: laps >= 1 ? "around the Earth" : "of the way around the Earth"
            ))

            let moon = min(distance / Self.moonDistance * 100, 100)
            facts.append(FunFact(
                icon: "moon.stars.fill", tint: .indigo,
                value: moon >= 1 ? "\(Int(moon))%" : String(format: "%.1f%%", moon),
                caption: "of the way to the Moon"
            ))
        }

        let hours = totalTravelTime / 3600
        if hours >= 1 {
            let days = hours / 24
            facts.append(FunFact(
                icon: "clock.badge.checkmark.fill", tint: .orange,
                value: days >= 1 ? String(format: "%.1f", days) : "\(Int(hours))",
                caption: days >= 1 ? "days spent in transit" : "hours spent in transit"
            ))
        }

        if flightCount > 0 {
            facts.append(FunFact(
                icon: "airplane.departure", tint: .teal,
                value: "\(flightCount)",
                caption: flightCount == 1 ? "flight taken" : "flights taken"
            ))
        }

        if averageDistanceMeters > 0 {
            facts.append(FunFact(
                icon: "ruler.fill", tint: .green,
                value: Format.distance(averageDistanceMeters),
                caption: "average trip length"
            ))
        }

        if let month = busiestMonth {
            facts.append(FunFact(
                icon: "calendar", tint: .pink,
                value: month.name,
                caption: "your busiest travel month"
            ))
        }

        return facts
    }

    /// The milestone badges, unlocked ones first, each with progress to the goal.
    var achievements: [Achievement] {
        let countries = uniqueCountries.count
        let cities = uniqueCities
        let continentCount = continents.count
        let laps = totalDistanceMeters / Self.earthCircumference

        // Mode-specific leg counts, for the road/rail badges.
        let roadLegs = modeBreakdown.first { $0.type == .roadTrip }?.count ?? 0
        let trainLegs = modeBreakdown.first { $0.type == .train }?.count ?? 0
        // The most trips packed into any single calendar year.
        let busiestYear = tripsByYear.map(\.count).max() ?? 0
        // The longest single trip, in whole kilometers.
        let longestKm = Int((longestTrip?.distanceMeters ?? 0) / 1000)

        let raw: [Achievement] = [
            badge("First Stamp", "airplane", .blue,
                  "Complete your first trip", value: totalTrips, goal: 1),
            badge("Globetrotter", "globe.americas.fill", .green,
                  "Visit 5 countries", value: countries, goal: 5),
            badge("World Citizen", "globe.europe.africa.fill", .teal,
                  "Visit 15 countries", value: countries, goal: 15),
            badge("Continental", "map.fill", .orange,
                  "Set foot on 3 continents", value: continentCount, goal: 3),
            badge("Frequent Flyer", "airplane.departure", .indigo,
                  "Take 10 flights", value: flightCount, goal: 10),
            badge("Jet Setter", "airplane.circle.fill", .blue,
                  "Take 50 flights", value: flightCount, goal: 50),
            badge("Explorer", "building.2.fill", .purple,
                  "Discover 10 cities", value: cities, goal: 10),
            badge("Around the World", "arrow.triangle.2.circlepath", .pink,
                  "Travel one lap of the Earth", value: Int(laps * 100), goal: 100),
            badge("Century Club", "suitcase.rolling.fill", .cyan,
                  "Log 25 trips", value: totalTrips, goal: 25),
            badge("Road Warrior", "car.fill", .green,
                  "Take 10 road trips", value: roadLegs, goal: 10),
            badge("Rail Rider", "tram.fill", .orange,
                  "Ride 5 trains", value: trainLegs, goal: 5),
            badge("Long Hauler", "arrow.up.right.circle.fill", .mint,
                  "Fly 10,000 km in one trip", value: longestKm, goal: 10_000),
            badge("Busy Year", "calendar.badge.clock", .red,
                  "Take 10 trips in a single year", value: busiestYear, goal: 10)
        ]
        return raw.sorted { ($0.isUnlocked ? 1 : 0, $0.progress) > ($1.isUnlocked ? 1 : 0, $1.progress) }
    }

    private func badge(_ title: String, _ icon: String, _ tint: Color,
                       _ detail: String, value: Int, goal: Int) -> Achievement {
        Achievement(
            icon: icon, tint: tint, title: title, detail: detail,
            isUnlocked: value >= goal,
            progress: min(Double(value) / Double(goal), 1)
        )
    }
}
