//
//  DesignSystem.swift
//  Runnit iOS
//
//  Shared visual language: per-mode accent colors, formatting helpers, and
//  small view conveniences used across screens.
//

import SwiftUI
import MapKit

extension TripType {
    var accent: Color {
        switch self {
        case .flight:   return .blue
        case .train:    return .orange
        case .roadTrip: return .green
        case .other:    return .purple
        }
    }

    var gradient: LinearGradient {
        LinearGradient(
            colors: [accent, accent.opacity(0.55)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// A short descriptor shown when choosing a mode for a leg.
    var blurb: String {
        switch self {
        case .flight:   return "Airport to airport"
        case .train:    return "Station to station"
        case .roadTrip: return "Drive it yourself"
        case .other:    return "Ferry, bus, or anything else"
        }
    }
}

extension ConnectionRisk {
    var color: Color {
        switch self {
        case .comfortable:      return .green
        case .tight, .atRisk:   return .orange
        case .missed, .cancelled: return .red
        case .unknown:          return TripType.flight.accent
        }
    }
}

/// A small capped label/value pill — "Terminal 2", "Gate E5", "Delay +55m".
struct InfoChip: View {
    let label: String
    let value: String
    let tint: Color

    init(_ label: String, _ value: String, tint: Color) {
        self.label = label
        self.value = value
        self.tint = tint
    }

    var body: some View {
        HStack(spacing: 3) {
            Text(label).foregroundStyle(.secondary)
            Text(value).fontWeight(.semibold)
        }
        .font(.caption2)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(tint.opacity(0.14), in: .capsule)
    }
}

enum Format {
    /// Distance from meters, honoring the user's distance-unit preference.
    static func distance(_ meters: Double) -> String {
        let m = Measurement(value: meters, unit: UnitLength.meters)
        let style = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0))
        switch DistanceUnit.current {
        case .automatic:
            return m.formatted(.measurement(width: .abbreviated, usage: .road, numberFormatStyle: style))
        case .kilometers:
            return m.converted(to: .kilometers)
                .formatted(.measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: style))
        case .miles:
            return m.converted(to: .miles)
                .formatted(.measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: style))
        }
    }

    /// A compact duration like "5 hr 20 min".
    static func duration(_ seconds: TimeInterval) -> String {
        Duration.seconds(max(0, seconds))
            .formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }

    // Times are rendered on the clock at the place they happen — the airport's,
    // not the device's — which is how airlines print them on a boarding pass.
    // Passing no zone keeps the device's, for dates that aren't tied to a place.

    static func date(_ date: Date, in zone: TimeZone? = nil) -> String {
        date.formatted(style(zone).month(.abbreviated).day().year())
    }

    static func dateTime(_ date: Date, in zone: TimeZone? = nil) -> String {
        date.formatted(style(zone).month(.abbreviated).day().hour().minute())
    }

    /// Just the clock time, e.g. "1:15 PM".
    static func time(_ date: Date, in zone: TimeZone? = nil) -> String {
        date.formatted(style(zone).hour().minute())
    }

    private static func style(_ zone: TimeZone?) -> Date.FormatStyle {
        Date.FormatStyle(timeZone: zone ?? .current)
    }

    /// A short zone label for a moment, e.g. "PDT". Nil when the zone is unknown.
    static func zone(_ zone: TimeZone?, at date: Date) -> String? {
        zone?.abbreviation(for: date)
    }

    /// How the clock changes across a leg, e.g. "PDT → EDT · 3 hr ahead".
    /// Nil when both ends share a clock (or either is unknown) — nothing to say.
    static func zoneShift(from origin: TimeZone?, to destination: TimeZone?,
                          departing: Date, arriving: Date) -> String? {
        guard let origin, let destination else { return nil }
        let originOffset = origin.secondsFromGMT(for: departing)
        let destinationOffset = destination.secondsFromGMT(for: arriving)
        guard originOffset != destinationOffset else { return nil }

        let delta = destinationOffset - originOffset
        let hours = Double(abs(delta)) / 3600
        let amount = hours == hours.rounded()
            ? "\(Int(hours)) hr"
            : String(format: "%.1f hr", hours)
        let direction = delta > 0 ? "ahead" : "behind"
        let from = origin.abbreviation(for: departing) ?? origin.identifier
        let to = destination.abbreviation(for: arriving) ?? destination.identifier
        return "\(from) → \(to) · \(amount) \(direction)"
    }

    /// Relative status label, e.g. "in 3 days" or "2 weeks ago".
    static func relative(_ date: Date) -> String {
        let style = Date.RelativeFormatStyle(presentation: .named, unitsStyle: .wide)
        return date.formatted(style)
    }
}

/// A richer navigation-bar title: a colored section icon, the title, and an
/// optional count subtitle — used across all top-level pages.
struct SectionHeader: ViewModifier {
    let title: String
    let systemImage: String
    let tint: Color
    var subtitle: String? = nil

    func body(content: Content) -> some View {
        content
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 10) {
                        Image(systemName: systemImage)
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                            .background(tint.gradient, in: .circle)
                            .shadow(color: tint.opacity(0.5), radius: 5, y: 2)
                        VStack(alignment: .leading, spacing: -1) {
                            Text(title).font(.headline.weight(.bold))
                            if let subtitle {
                                Text(subtitle).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
    }
}

extension View {
    /// Styled section header for a top-level page's navigation bar.
    func sectionHeader(_ title: String, systemImage: String, tint: Color, subtitle: String? = nil) -> some View {
        modifier(SectionHeader(title: title, systemImage: systemImage, tint: tint, subtitle: subtitle))
    }

    /// Convenience for wrapping content in a glass rounded rectangle, with an
    /// optional color tint for a more vivid, mode-colored card.
    func glassCard(cornerRadius: CGFloat = 22, tint: Color? = nil) -> some View {
        let glass: Glass = tint.map { Glass.regular.tint($0) } ?? .regular
        return self
            .padding(16)
            .glassEffect(glass, in: .rect(cornerRadius: cornerRadius))
    }
}
