//
//  PassportCharts.swift
//  Runnit iOS
//
//  The Passport's data visualizations — hand-drawn to match the app's glass
//  aesthetic: a mode-split donut, a trips-by-year bar chart, a twelve-month
//  travel-rhythm strip, and a continent-coverage constellation.
//

import SwiftUI

// MARK: - Mode split donut

/// A donut ring showing how the traveler's legs divide across modes, with the
/// total in the middle and a tappable-feeling legend beneath.
struct ModeSplitDonut: View {
    let modes: [ModeBreakdown]

    @State private var animate = false

    private var total: Int { modes.reduce(0) { $0 + $1.count } }

    /// One mode's slice of the ring, expressed as start/end fractions.
    private struct Arc: Identifiable {
        let mode: ModeBreakdown
        let start: Double
        let end: Double
        var id: String { mode.id }
    }

    /// Each mode's arc as a (start, end) fraction of the whole ring.
    private var arcs: [Arc] {
        guard total > 0 else { return [] }
        var running = 0.0
        return modes.map { mode in
            let start = running
            running += Double(mode.count) / Double(total)
            return Arc(mode: mode, start: start, end: running)
        }
    }

    var body: some View {
        HStack(spacing: 20) {
            ZStack {
                ForEach(arcs) { arc in
                    Circle()
                        .trim(from: arc.start, to: animate ? arc.end : arc.start)
                        .stroke(arc.mode.type.gradient,
                                style: StrokeStyle(lineWidth: 16, lineCap: .butt))
                        .rotationEffect(.degrees(-90))
                }
                VStack(spacing: 0) {
                    Text("\(total)")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .contentTransition(.numericText())
                    Text(total == 1 ? "leg" : "legs")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 128, height: 128)
            .padding(.vertical, 2)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(modes) { mode in
                    HStack(spacing: 9) {
                        Circle()
                            .fill(mode.type.gradient)
                            .frame(width: 11, height: 11)
                        Text(mode.type.label)
                            .font(.subheadline.weight(.medium))
                        Spacer(minLength: 8)
                        Text("\(percent(mode.count))%")
                            .font(.subheadline.weight(.bold))
                            .monospacedDigit()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(tint: (modes.first?.type.accent ?? .blue).opacity(0.18))
        .onAppear {
            withAnimation(.smooth(duration: 0.9)) { animate = true }
        }
    }

    private func percent(_ count: Int) -> Int {
        total == 0 ? 0 : Int((Double(count) / Double(total) * 100).rounded())
    }
}

// MARK: - Trips by year

/// A vertical bar chart of completed trips per year. Bars grow on appear and the
/// most recent year is highlighted in the accent color.
struct YearBarChart: View {
    let data: [YearTrips]
    var tint: Color = .indigo

    @State private var animate = false

    private var maxCount: Int { max(data.map(\.count).max() ?? 1, 1) }

    var body: some View {
        HStack(alignment: .bottom, spacing: barSpacing) {
            ForEach(Array(data.enumerated()), id: \.element.id) { index, item in
                let isLast = index == data.count - 1
                VStack(spacing: 6) {
                    Text("\(item.count)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(isLast ? tint : .secondary)
                        .opacity(animate ? 1 : 0)

                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isLast
                              ? AnyShapeStyle(tint.gradient)
                              : AnyShapeStyle(tint.opacity(0.28)))
                        .frame(height: animate ? barHeight(item.count) : 0)

                    Text(shortYear(item.year))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 168)
        .frame(maxWidth: .infinity)
        .glassCard(tint: tint.opacity(0.16))
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.75)) { animate = true }
        }
    }

    private var barSpacing: CGFloat { data.count > 8 ? 5 : 10 }

    private func barHeight(_ count: Int) -> CGFloat {
        let track: CGFloat = 118
        return max(track * CGFloat(count) / CGFloat(maxCount), 6)
    }

    /// Two-digit year for compact axis labels ("’23"), full when there's room.
    private func shortYear(_ year: Int) -> String {
        data.count > 6 ? "’\(String(year).suffix(2))" : String(year)
    }
}

// MARK: - Travel rhythm

/// A twelve-month strip showing when across the year the traveler tends to
/// leave. Months with trips fill toward the accent; the peak month is crowned.
struct MonthRhythmChart: View {
    /// Twelve counts, index 0 = January.
    let months: [Int]
    var tint: Color = .pink

    @State private var animate = false

    private static let labels = ["J", "F", "M", "A", "M", "J",
                                 "J", "A", "S", "O", "N", "D"]

    private var peak: Int { max(months.max() ?? 0, 1) }
    private var peakIndex: Int? {
        guard let m = months.max(), m > 0 else { return nil }
        return months.firstIndex(of: m)
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            ForEach(0..<12, id: \.self) { index in
                let count = months[index]
                let isPeak = index == peakIndex
                VStack(spacing: 6) {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(tint)
                        .opacity(isPeak && animate ? 1 : 0)

                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(count == 0
                              ? AnyShapeStyle(Color.secondary.opacity(0.14))
                              : (isPeak ? AnyShapeStyle(tint.gradient)
                                        : AnyShapeStyle(tint.opacity(0.4))))
                        .frame(height: animate ? height(count) : 4)

                    Text(Self.labels[index])
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(isPeak ? tint : .secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 132, alignment: .bottom)
        .frame(maxWidth: .infinity)
        .glassCard(tint: tint.opacity(0.15))
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.8)) { animate = true }
        }
    }

    private func height(_ count: Int) -> CGFloat {
        guard count > 0 else { return 4 }
        let track: CGFloat = 84
        return max(track * CGFloat(count) / CGFloat(peak), 10)
    }
}

// MARK: - Continent coverage constellation

/// World coverage as a constellation of all six inhabited continents: visited
/// ones glow in the accent, the rest sit dim. A headline count and progress bar
/// anchor it. More of a scoreboard than the map behind the sheet.
struct ContinentCoverageCard: View {
    let visited: [Continent]

    @State private var animate = false

    /// Fixed display order so the grid is stable regardless of visit order.
    private static let order: [Continent] = [
        .northAmerica, .southAmerica, .europe, .africa, .asia, .oceania
    ]

    private var visitedSet: Set<Continent> { Set(visited) }
    private var fraction: Double {
        Double(visitedSet.count) / Double(Continent.inhabitedCount)
    }

    private let columns = [GridItem(.adaptive(minimum: 96), spacing: 10)]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(visitedSet.count)")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(.teal)
                Text("of \(Continent.inhabitedCount) continents")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int((fraction * 100).rounded()))%")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.teal)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.secondary.opacity(0.16))
                    Capsule()
                        .fill(LinearGradient(colors: [.teal, .green],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * (animate ? fraction : 0))
                }
            }
            .frame(height: 10)

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(Self.order) { continent in
                    continentPill(continent, visited: visitedSet.contains(continent))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(tint: .teal.opacity(0.18))
        .onAppear {
            withAnimation(.smooth(duration: 0.8).delay(0.15)) { animate = true }
        }
    }

    private func continentPill(_ continent: Continent, visited: Bool) -> some View {
        HStack(spacing: 6) {
            Text(continent.emoji)
                .font(.callout)
                .grayscale(visited ? 0 : 1)
                .opacity(visited ? 1 : 0.55)
            Text(continent.rawValue)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(visited ? .primary : .secondary)
            Spacer(minLength: 0)
            if visited {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.teal)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(visited ? Color.teal.opacity(0.16) : Color.secondary.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(visited ? Color.teal.opacity(0.35) : .clear, lineWidth: 1)
        )
    }
}

#if DEBUG
#Preview("Charts") {
    let stats = TripStatistics(trips: Trip.allSamples)
    return ScrollView {
        VStack(spacing: 16) {
            ModeSplitDonut(modes: stats.modeBreakdown)
            YearBarChart(data: [
                YearTrips(year: 2021, count: 2), YearTrips(year: 2022, count: 5),
                YearTrips(year: 2023, count: 3), YearTrips(year: 2024, count: 7),
                YearTrips(year: 2025, count: 4)
            ])
            MonthRhythmChart(months: [1, 0, 2, 3, 1, 4, 5, 2, 0, 1, 3, 2])
            ContinentCoverageCard(visited: [.northAmerica, .europe, .asia])
        }
        .padding()
    }
    .background(Color.black)
    .preferredColorScheme(.dark)
}
#endif
