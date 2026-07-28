//
//  WidgetSupport.swift
//  RunnitWidgets
//
//  Small shared bits the widget views lean on: turning the SwiftUI-free enums
//  that travel in the activity/snapshot payloads back into real `Color`s, and a
//  breathing "live" dot. Kept in the widget target only — the app has its own
//  DesignSystem for the same ideas.
//

import SwiftUI

extension TripActivityAttributes.Accent {
    var color: Color {
        switch self {
        case .blue:   return .blue
        case .orange: return .orange
        case .green:  return .green
        case .purple: return .purple
        case .red:    return .red
        case .cyan:   return .cyan
        }
    }
}

extension TripActivityAttributes.Mode {
    /// The per-mode accent, matching the app's `TripType.accent`.
    var color: Color {
        switch self {
        case .flight:   return .blue
        case .train:    return .orange
        case .roadTrip: return .green
        case .other:    return .purple
        }
    }
}

/// A small pulsing dot marking a live reading.
struct LivePulseDot: View {
    let color: Color
    @State private var expanded = false

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.25))
                .scaleEffect(expanded ? 1 : 0.5)
                .opacity(expanded ? 0 : 1)
            Circle().fill(color).frame(width: 7, height: 7)
        }
        .frame(width: 16, height: 16)
        .onAppear {
            withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) {
                expanded = true
            }
        }
    }
}

/// A bare, self-updating progress bar for the Live Activity: given the absolute
/// window it should span, it animates on its own between updates. Falls back to a
/// static half-bar when no window is known (e.g. an open-ended drive).
struct LiveProgressBar: View {
    let start: Date?
    let end: Date?
    let tint: Color

    var body: some View {
        if let start, let end, end > start {
            ProgressView(timerInterval: start...end, countsDown: false) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .progressViewStyle(.linear)
            .tint(tint)
        } else {
            ProgressView(value: 0)
                .progressViewStyle(.linear)
                .tint(tint)
        }
    }
}
