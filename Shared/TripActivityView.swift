//
//  TripActivityView.swift
//  Runnit iOS · Shared with RunnitWidgets
//
//  The live card's face. This is deliberately a line-for-line restatement of one
//  row of `ActiveTripsBox` — same icon puck, same headline/title stack, same
//  punctuality-and-countdown column, same progress track, same endpoint strip —
//  so the thing on the Lock Screen reads as the same object as the thing in the
//  Upcoming tab.
//
//  It can't literally reuse `ActiveTripsBox`, because that view reaches into
//  SwiftData for its records and the widget process has no store. It draws from
//  `ContentState` alone instead. The one honest difference: the countdown ticks
//  off a date range here rather than a formatted string, so it keeps counting
//  between the app's updates.
//

#if os(iOS)

import SwiftUI

extension TripActivityAccent {
    var color: Color {
        switch self {
        case .blue:   return .blue
        case .orange: return .orange
        case .green:  return .green
        case .red:    return .red
        case .purple: return .purple
        }
    }
}

/// One live trip, drawn as it appears in the app's "Happening Now" box.
struct TripActivityRow: View {
    let state: TripActivityAttributes.ContentState

    var body: some View {
        let tint = state.accent.color
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: state.icon)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(tint.gradient, in: .circle)

                VStack(alignment: .leading, spacing: 1) {
                    Text(state.headline)
                        .font(.subheadline.weight(.semibold))
                    Text(state.tripTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 1) {
                    Text(state.punctuality)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(tint)
                    countdown
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            TripActivityProgressTrack(progress: state.progress, icon: state.icon, tint: tint)

            HStack {
                Text(state.startCode)
                Spacer()
                if let time = state.endTime {
                    Text("\(state.endTitle) \(time)")
                        .foregroundStyle(state.endIsLate ? .orange : .secondary)
                }
                Spacer()
                Text(state.endCode)
            }
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
    }

    /// The ticking half of the row. `Text(timerInterval:)` re-renders itself on
    /// the system's clock, so the number stays honest even when the app hasn't
    /// been able to push an update for a while.
    @ViewBuilder
    private var countdown: some View {
        if let range = state.countdownRange {
            Text(state.countdownPrefix)
                + Text(timerInterval: range, countsDown: true)
                + Text(state.countdownSuffix)
        } else if let fallback = state.countdownFallback {
            Text(fallback)
        }
    }
}

/// The app's `TripProgressTrack`, restated for the widget process. Kept in step
/// with the compact variant the active-trips box uses.
struct TripActivityProgressTrack: View {
    let progress: Double?
    let icon: String
    let tint: Color

    private let height: CGFloat = 6
    private let puck: CGFloat = 18

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let value = progress ?? 0
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.quaternary)
                    .frame(height: height)
                if progress != nil {
                    Capsule()
                        .fill(tint.gradient)
                        .frame(width: max(width * value, height), height: height)
                    Image(systemName: icon)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: puck, height: puck)
                        .background(tint.gradient, in: .circle)
                        .shadow(color: tint.opacity(0.4), radius: 4, y: 2)
                        .offset(x: min(max(width * value - puck / 2, 0), width - puck))
                }
            }
            .frame(width: width, height: puck)
        }
        .frame(height: puck)
    }
}

/// The full Lock Screen / banner presentation: the box's header, then the row.
struct TripActivityCard: View {
    let state: TripActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(state.accent.color)
                Text("Happening Now")
                    .font(.subheadline.weight(.semibold))
                Spacer()
            }
            TripActivityRow(state: state)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
    }
}

#endif
