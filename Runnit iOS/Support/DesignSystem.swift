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

extension StopCategory {
    /// The color used for this stop category's icon and chip.
    var tint: Color {
        switch self {
        case .food:     return .orange
        case .coffee:   return .brown
        case .gas:      return .green
        case .charging: return .mint
        case .lodging:  return .indigo
        case .scenic:   return .teal
        case .sights:   return .purple
        case .shopping: return .pink
        case .rest:     return .blue
        case .other:    return .gray
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

/// Consistent spacing scale, so padding and stack gaps stay uniform everywhere.
enum Spacing {
    static let xs: CGFloat = 6
    static let sm: CGFloat = 10
    static let md: CGFloat = 16
    static let lg: CGFloat = 20
    static let xl: CGFloat = 28
}

/// A section heading used inside scroll content: a bold title with an optional
/// tinted icon. Distinct from the navigation-bar `SectionHeader`.
struct SectionTitle: View {
    let title: String
    var systemImage: String? = nil
    var tint: Color = .primary
    var accessory: String? = nil

    var body: some View {
        HStack(spacing: 8) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(tint)
            }
            Text(title).font(.title3.weight(.bold))
            Spacer()
            if let accessory {
                Text(accessory)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A subtle staggered entrance: content fades and rises into place, with a delay
/// proportional to its index so a column of cards cascades in cleanly.
struct StaggeredAppear: ViewModifier {
    let index: Int
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 16)
            .onAppear {
                withAnimation(.smooth(duration: 0.5).delay(Double(index) * 0.06)) {
                    shown = true
                }
            }
    }
}

extension View {
    /// Fade + rise entrance, staggered by `index` for a cascading reveal.
    func appear(_ index: Int = 0) -> some View {
        modifier(StaggeredAppear(index: index))
    }
}

/// A tactile button style for tappable cards: a gentle scale-down on press so
/// the whole card feels responsive without a heavy highlight.
struct PressableCardStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.snappy(duration: 0.25), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressableCardStyle {
    static var pressableCard: PressableCardStyle { PressableCardStyle() }
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
