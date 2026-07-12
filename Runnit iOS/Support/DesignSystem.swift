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

    static func date(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day().year())
    }

    static func dateTime(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
    }

    /// Relative status label, e.g. "in 3 days" or "2 weeks ago".
    static func relative(_ date: Date) -> String {
        let style = Date.RelativeFormatStyle(presentation: .named, unitsStyle: .wide)
        return date.formatted(style)
    }
}

extension View {
    /// Convenience for wrapping content in a glass rounded rectangle, with an
    /// optional color tint for a more vivid, mode-colored card.
    func glassCard(cornerRadius: CGFloat = 22, tint: Color? = nil) -> some View {
        let glass: Glass = tint.map { Glass.regular.tint($0) } ?? .regular
        return self
            .padding(16)
            .glassEffect(glass, in: .rect(cornerRadius: cornerRadius))
    }
}
