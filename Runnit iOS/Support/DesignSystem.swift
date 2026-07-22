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

extension ShareParticipantSummary {
    /// A stable color for this person, drawn from the same palette the profile
    /// avatar offers. Derived from the display name so someone keeps the same
    /// color on every screen and on every device — a roster that reshuffles its
    /// colors reads as a different set of people.
    var accent: Color {
        let palette = ProfileAccent.allCases
        let hash = displayName.unicodeScalars.reduce(into: 5_381) { total, scalar in
            total = total &* 33 &+ Int(scalar.value)
        }
        return palette[abs(hash) % palette.count].color
    }
}

/// A small glyph saying whether a trip has reached iCloud.
///
/// Quiet, but not invisible: sync is background machinery and shouldn't compete
/// with the countdown or the route, yet a `.tertiary` glyph on the dark glass
/// couldn't be seen at all. `.secondary` on a faint filled circle keeps it
/// legible against both the glass cards and the map.
///
/// All three states show something. Hiding the local-only case made the badge
/// disappear entirely on a device full of demo trips — and "this one isn't in
/// iCloud" is the honest answer for them, not something to conceal.
struct TripSyncBadge: View {
    let state: TripSyncState
    var size: CGFloat = 12

    private var symbol: String {
        switch state {
        case .saved:       return "checkmark.icloud.fill"
        case .pending:     return "arrow.up.icloud"
        case .unavailable: return "exclamationmark.icloud"
        case .localOnly:   return "icloud.slash"
        }
    }

    private var label: String {
        switch state {
        case .saved:       return "Saved to iCloud"
        case .pending:     return "Waiting to save to iCloud"
        case .unavailable: return "Not saved — iCloud isn't set up"
        case .localOnly:   return "Not saved to iCloud"
        }
    }

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size, weight: .semibold))
            // Monochrome on purpose. A warning tint would be wrong for both
            // non-saved states: demo trips are local by design, and "pending"
            // is the permanent resting state whenever iCloud isn't signed in.
            // The glyph carries the meaning; the disc carries the visibility.
            .foregroundStyle(.secondary)
            .frame(width: size * 2, height: size * 2)
            .background(.white.opacity(0.08), in: .circle)
            .accessibilityLabel(label)
    }
}

/// The people on a shared trip, as overlapping monogram avatars.
///
/// The same idiom as `TripCardView`'s multi-modal mode chain — discs overlapped
/// and ringed against the background — so a shared trip reads as the app's own
/// visual language rather than a bolted-on badge. Beyond `visibleLimit` the
/// remainder collapses into a "+N" disc, because the count is the useful part
/// once a trip has more people than the card has room for.
struct ParticipantStack: View {
    let participants: [ShareParticipantSummary]
    var size: CGFloat = 22
    var visibleLimit: Int = 3

    private var visible: [ShareParticipantSummary] {
        Array(participants.prefix(visibleLimit))
    }

    private var overflow: Int {
        max(0, participants.count - visibleLimit)
    }

    var body: some View {
        HStack(spacing: -size * 0.3) {
            ForEach(visible) { participant in
                ProfileAvatar(name: participant.name ?? "",
                              accent: participant.accent,
                              size: size)
                    // A pending invite is a lighter presence than someone who
                    // has actually joined.
                    .opacity(participant.acceptance == .accepted ? 1 : 0.55)
                    .overlay(Circle().strokeBorder(.background, lineWidth: 1.5))
            }
            if overflow > 0 {
                Text("+\(overflow)")
                    .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(width: size, height: size)
                    .glassEffect(.regular, in: .circle)
                    .overlay(Circle().strokeBorder(.background, lineWidth: 1.5))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        let names = participants.map(\.displayName)
        switch names.count {
        case 0:  return "Not shared"
        case 1:  return "Shared with \(names[0])"
        default: return "Shared with \(names.count) people"
        }
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
