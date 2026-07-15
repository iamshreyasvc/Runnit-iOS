//
//  PassportComponents.swift
//  Runnit iOS
//
//  The reusable building blocks of the Passport screen: the passport-cover hero,
//  stat tiles, fun-fact cards, world coverage, stamps, and achievement badges.
//

import SwiftUI

/// A premium "passport cover" hero — a fixed dark, gold-accented card that reads
/// like a real travel document regardless of the app's light/dark appearance.
struct PassportHeroCard: View {
    let name: String
    let trips: Int
    let countries: Int
    let continents: Int

    /// Warm gold used for the document's foil-stamped lettering.
    private let gold = Color(red: 0.85, green: 0.72, blue: 0.42)

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                Text("PASSPORT")
                    .font(.footnote.weight(.heavy))
                    .tracking(4)
                Spacer()
                Text("RUNNIT")
                    .font(.caption2.weight(.bold))
                    .tracking(2)
            }
            .foregroundStyle(gold)

            emblem

            Text(name.isEmpty ? "Traveler" : name.uppercased())
                .font(.system(.title3, design: .serif).weight(.bold))
                .tracking(1)
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Divider().overlay(gold.opacity(0.4))

            HStack(spacing: 0) {
                coverStat("\(trips)", trips == 1 ? "Trip" : "Trips")
                coverDivider
                coverStat("\(countries)", countries == 1 ? "Country" : "Countries")
                coverDivider
                coverStat("\(continents)", "Continents")
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(coverBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 28)
                .strokeBorder(gold.opacity(0.55), lineWidth: 1)
        )
        .clipShape(.rect(cornerRadius: 28))
        .shadow(color: .black.opacity(0.35), radius: 18, y: 10)
    }

    private var emblem: some View {
        Image(systemName: "globe.americas.fill")
            .font(.system(size: 62))
            .foregroundStyle(gold.gradient)
            .shadow(color: gold.opacity(0.5), radius: 16)
            .padding(.vertical, 2)
    }

    private func coverStat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 3) {
            Text(value).font(.title3.weight(.bold)).foregroundStyle(.white)
            Text(label.uppercased())
                .font(.caption2.weight(.semibold))
                .tracking(1)
                .foregroundStyle(gold.opacity(0.9))
        }
        .frame(maxWidth: .infinity)
    }

    private var coverDivider: some View {
        Rectangle().fill(gold.opacity(0.3)).frame(width: 1, height: 30)
    }

    private var coverBackground: some View {
        LinearGradient(
            colors: [Color(red: 0.11, green: 0.13, blue: 0.28),
                     Color(red: 0.05, green: 0.05, blue: 0.12)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
        .overlay(
            RadialGradient(colors: [gold.opacity(0.14), .clear],
                           center: .center, startRadius: 4, endRadius: 220)
        )
    }
}

/// A compact, colorful "fun fact" tile — a big value over a plain-language line.
struct FunFactCard: View {
    let fact: FunFact

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: fact.icon)
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(fact.tint.gradient, in: .circle)
            Spacer(minLength: 0)
            Text(fact.value)
                .font(.title.weight(.bold))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            Text(fact.caption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: 150, height: 158, alignment: .leading)
        .glassCard(cornerRadius: 22, tint: fact.tint.opacity(0.25))
    }
}

/// A reusable stat tile: an icon, a bold value, and a caption.
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

/// World coverage: how many continents the traveler has touched, with an
/// animated progress bar and a chip for each continent visited.
struct ContinentCoverageCard: View {
    let visited: [Continent]

    @State private var animateProgress = false

    private var fraction: Double {
        Double(visited.count) / Double(Continent.inhabitedCount)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(visited.count)")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(.teal)
                Text("of \(Continent.inhabitedCount) continents")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.secondary.opacity(0.18))
                    Capsule()
                        .fill(LinearGradient(colors: [.teal, .green],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * (animateProgress ? fraction : 0))
                }
            }
            .frame(height: 10)

            if !visited.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(visited) { continent in
                            Text("\(continent.emoji) \(continent.rawValue)")
                                .font(.caption2.weight(.medium))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(.teal.opacity(0.15), in: .capsule)
                                .fixedSize()
                        }
                    }
                }
                .scrollClipDisabled()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(tint: .teal.opacity(0.2))
        .onAppear {
            withAnimation(.smooth(duration: 0.8).delay(0.2)) { animateProgress = true }
        }
    }
}

/// A milestone badge: bright when unlocked, dimmed with a progress ring when not.
struct AchievementBadge: View {
    let achievement: Achievement

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(.secondary.opacity(0.15), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: achievement.progress)
                    .stroke(achievement.tint.gradient,
                            style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .opacity(achievement.isUnlocked ? 0 : 1)
                Image(systemName: achievement.icon)
                    .font(.title2)
                    .foregroundStyle(achievement.isUnlocked ? .white : .secondary)
                    .frame(width: 52, height: 52)
                    .background(
                        achievement.isUnlocked
                            ? AnyShapeStyle(achievement.tint.gradient)
                            : AnyShapeStyle(Color.secondary.opacity(0.12)),
                        in: .circle
                    )
            }
            .frame(width: 62, height: 62)

            Text(achievement.title)
                .font(.caption.weight(.semibold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            Text(achievement.isUnlocked ? "Unlocked" : achievement.detail)
                .font(.caption2)
                .foregroundStyle(achievement.isUnlocked ? achievement.tint : .secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: 150)
        .padding(10)
        .glassCard(cornerRadius: 20,
                   tint: achievement.isUnlocked ? achievement.tint.opacity(0.2) : nil)
        .opacity(achievement.isUnlocked ? 1 : 0.85)
    }
}

/// A dashed-border country stamp with its flag, name, and visit count.
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
                .strokeBorder(.secondary.opacity(0.25),
                              style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
        )
    }
}
